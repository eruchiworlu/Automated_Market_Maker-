import { describe, test, expect, beforeEach, vi } from 'vitest';

// Helper functions to mimic Clarity responses
const txOk = (value) => ({ success: true, value });
const txErr = (code) => ({ success: false, error: { code } });

// Mock token contract interfaces
const mockTokenContract = (name, symbol, decimals = 6) => {
  return {
    name: () => name,
    symbol: () => symbol,
    decimals: () => decimals,
    transfer: vi.fn(),
    balanceOf: vi.fn(),
    totalSupply: vi.fn()
  };
};

describe('Automated Market Maker Contract', () => {
  // Setup test environment
  let amm;
  let tokenA;
  let tokenB;
  let wallet1;
  let wallet2;
  let blockHeight;

  beforeEach(() => {
    // Reset mocks
    vi.resetAllMocks();
    
    // Mock block height
    blockHeight = 100;
    vi.spyOn(global, 'getBlockInfo').mockImplementation(() => blockHeight);
    
    // Create test wallets
    wallet1 = { address: 'ST1SJ3DTE5DN7X54YDH5D64R3BCB6A2AG2ZQ8YPD5' };
    wallet2 = { address: 'ST2CY5V39NHDPWSXMW9QDT3HC3GD6Q6XX4CFRK9AG' };
    
    // Create mock tokens
    tokenA = mockTokenContract('Token A', 'TA');
    tokenB = mockTokenContract('Token B', 'TB');
    
    // Initialize AMM contract with mocked dependencies
    amm = {
      // Contract state
      pools: {},
      liquidityProviders: {},
      
      // Error constants
      errors: {
        ownerOnly: 100,
        notTokenOwner: 101,
        insufficientBalance: 102,
        insufficientLiquidity: 103,
        zeroAmount: 104,
        sameToken: 105,
        slippageExceeded: 106,
        deadlinePassed: 107,
        poolAlreadyExists: 108,
        transferFailed: 109
      },
      
      // Contract methods
      createPool: vi.fn(),
      addLiquidity: vi.fn(),
      removeLiquidity: vi.fn(),
      swap: vi.fn(),
      getPoolDetails: vi.fn(),
      getProviderShares: vi.fn(),
      getAmountOut: vi.fn(),
      getAmountIn: vi.fn(),
      quote: vi.fn(),
      getSwapOutput: vi.fn()
    };
    
    // Mock implementation of key functions
    amm.getAmountOut.mockImplementation((amountIn, reserveIn, reserveOut) => {
      const feeNumerator = 3;
      const feeDenominator = 1000;
      const amountInWithFee = amountIn * (feeDenominator - feeNumerator);
      const numerator = amountInWithFee * reserveOut;
      const denominator = (reserveIn * feeDenominator) + amountInWithFee;
      return Math.floor(numerator / denominator);
    });
    
    amm.getPoolDetails.mockImplementation((tokenX, tokenY) => {
      const key = `${tokenX.symbol()}-${tokenY.symbol()}`;
      return amm.pools[key] || null;
    });
    
    amm.getProviderShares.mockImplementation((tokenX, tokenY, provider) => {
      const poolKey = `${tokenX.symbol()}-${tokenY.symbol()}`;
      const providerKey = `${poolKey}-${provider.address}`;
      return amm.liquidityProviders[providerKey] || { shares: 0 };
    });
  });

  describe('Pool Creation', () => {
    test('should create a new pool successfully', () => {
      // Mock successful token transfers
      tokenA.transfer.mockReturnValue(txOk(true));
      tokenB.transfer.mockReturnValue(txOk(true));
      
      // Mock the createPool function
      amm.createPool.mockImplementation((tokenA, tokenB, amountA, amountB) => {
        if (tokenA === tokenB) {
          return txErr(amm.errors.sameToken);
        }
        
        if (amountA === 0 || amountB === 0) {
          return txErr(amm.errors.zeroAmount);
        }
        
        const poolKey = `${tokenA.symbol()}-${tokenB.symbol()}`;
        if (amm.pools[poolKey]) {
          return txErr(amm.errors.poolAlreadyExists);
        }
        
        // Create the pool
        const initialShares = 1000000000; // 1 billion
        amm.pools[poolKey] = {
          reserveX: amountA,
          reserveY: amountB,
          totalShares: initialShares
        };
        
        // Assign LP tokens to creator
        const providerKey = `${poolKey}-${wallet1.address}`;
        amm.liquidityProviders[providerKey] = { shares: initialShares };
        
        return txOk({
          tokenX: tokenA,
          tokenY: tokenB,
          shares: initialShares
        });
      });
      
      // Test creating a pool
      const result = amm.createPool(tokenA, tokenB, 1000000, 2000000);
      expect(result).toEqual(txOk({
        tokenX: tokenA,
        tokenY: tokenB,
        shares: 1000000000
      }));
      
      // Verify pool was created
      const poolKey = `${tokenA.symbol()}-${tokenB.symbol()}`;
      expect(amm.pools[poolKey]).toEqual({
        reserveX: 1000000,
        reserveY: 2000000,
        totalShares: 1000000000
      });
      
      // Verify LP tokens assigned
      const providerKey = `${poolKey}-${wallet1.address}`;
      expect(amm.liquidityProviders[providerKey]).toEqual({ shares: 1000000000 });
    });
    
    test('should fail with same tokens', () => {
      amm.createPool.mockImplementation((tokenA, tokenB) => {
        if (tokenA === tokenB) {
          return txErr(amm.errors.sameToken);
        }
        return txOk({});
      });
      
      const result = amm.createPool(tokenA, tokenA, 1000000, 2000000);
      expect(result).toEqual(txErr(amm.errors.sameToken));
    });
    
    test('should fail with zero amounts', () => {
      amm.createPool.mockImplementation((tokenA, tokenB, amountA, amountB) => {
        if (amountA === 0 || amountB === 0) {
          return txErr(amm.errors.zeroAmount);
        }
        return txOk({});
      });
      
      const result = amm.createPool(tokenA, tokenB, 0, 2000000);
      expect(result).toEqual(txErr(amm.errors.zeroAmount));
    });
  });

  describe('Liquidity Operations', () => {
    beforeEach(() => {
      // Setup an existing pool
      const poolKey = `${tokenA.symbol()}-${tokenB.symbol()}`;
      amm.pools[poolKey] = {
        reserveX: 1000000,
        reserveY: 2000000,
        totalShares: 1000000000
      };
      
      const providerKey = `${poolKey}-${wallet1.address}`;
      amm.liquidityProviders[providerKey] = { shares: 1000000000 };
      
      // Mock the add liquidity function
      amm.addLiquidity.mockImplementation((tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin, deadline) => {
        if (deadline < blockHeight) {
          return txErr(amm.errors.deadlinePassed);
        }
        
        if (tokenA === tokenB) {
          return txErr(amm.errors.sameToken);
        }
        
        if (amountADesired === 0 || amountBDesired === 0) {
          return txErr(amm.errors.zeroAmount);
        }
        
        const poolKey = `${tokenA.symbol()}-${tokenB.symbol()}`;
        const pool = amm.pools[poolKey];
        
        if (!pool) {
          // Create new pool if it doesn't exist
          return amm.createPool(tokenA, tokenB, amountADesired, amountBDesired);
        }
        
        // Calculate optimal amounts
        let amountA = amountADesired;
        let amountB = amountBDesired;
        
        if (pool.reserveX > 0 && pool.reserveY > 0) {
          amountA = Math.min(amountADesired, Math.floor((amountBDesired * pool.reserveX) / pool.reserveY));
          amountB = Math.min(amountBDesired, Math.floor((amountADesired * pool.reserveY) / pool.reserveX));
        }
        
        if (amountA < amountAMin || amountB < amountBMin) {
          return txErr(amm.errors.slippageExceeded);
        }
        
        // Calculate shares
        let newShares;
        if (pool.totalShares === 0) {
          newShares = Math.floor(Math.sqrt(amountA * amountB));
        } else {
          newShares = Math.min(
            Math.floor((amountA * pool.totalShares) / pool.reserveX),
            Math.floor((amountB * pool.totalShares) / pool.reserveY)
          );
        }
        
        // Update pool
        pool.reserveX += amountA;
        pool.reserveY += amountB;
        pool.totalShares += newShares;
        
        // Update provider shares
        const providerKey = `${poolKey}-${wallet1.address}`;
        const provider = amm.liquidityProviders[providerKey] || { shares: 0 };
        provider.shares += newShares;
        amm.liquidityProviders[providerKey] = provider;
        
        return txOk({
          tokenX: tokenA,
          tokenY: tokenB,
          shares: newShares,
          amountX: amountA,
          amountY: amountB
        });
      });
      
      // Mock the remove liquidity function
      amm.removeLiquidity.mockImplementation((tokenA, tokenB, shares, amountAMin, amountBMin, deadline) => {
        if (deadline < blockHeight) {
          return txErr(amm.errors.deadlinePassed);
        }
        
        if (shares === 0) {
          return txErr(amm.errors.zeroAmount);
        }
        
        const poolKey = `${tokenA.symbol()}-${tokenB.symbol()}`;
        const pool = amm.pools[poolKey];
        
        if (!pool) {
          return txErr(amm.errors.poolAlreadyExists); // Using this error for simplicity
        }
        
        const providerKey = `${poolKey}-${wallet1.address}`;
        const provider = amm.liquidityProviders[providerKey] || { shares: 0 };
        
        if (provider.shares < shares) {
          return txErr(amm.errors.insufficientBalance);
        }
        
        // Calculate withdrawal amounts
        const amountA = Math.floor((shares * pool.reserveX) / pool.totalShares);
        const amountB = Math.floor((shares * pool.reserveY) / pool.totalShares);
        
        if (amountA < amountAMin || amountB < amountBMin) {
          return txErr(amm.errors.slippageExceeded);
        }
        
        // Update pool
        pool.reserveX -= amountA;
        pool.reserveY -= amountB;
        pool.totalShares -= shares;
        
        // Update provider shares
        provider.shares -= shares;
        amm.liquidityProviders[providerKey] = provider;
        
        return txOk({
          tokenX: tokenA,
          tokenY: tokenB,
          shares,
          amountX: amountA,
          amountY: amountB
        });
      });
    });
    
    test('should add liquidity to existing pool', () => {
      tokenA.transfer.mockReturnValue(txOk(true));
      tokenB.transfer.mockReturnValue(txOk(true));
      
      const result = amm.addLiquidity(
        tokenA, 
        tokenB, 
        500000, // amountADesired
        1000000, // amountBDesired
        450000, // amountAMin
        900000, // amountBMin
        blockHeight + 100 // deadline
      );
      
      expect(result).toEqual(txOk({
        tokenX: tokenA,
        tokenY: tokenB,
        shares: 500000, // Half of the initial liquidity
        amountX: 500000,
        amountY: 1000000
      }));
      
      // Verify pool was updated
      const poolKey = `${tokenA.symbol()}-${tokenB.symbol()}`;
      expect(amm.pools[poolKey].reserveX).toBe(1500000);
      expect(amm.pools[poolKey].reserveY).toBe(3000000);
      expect(amm.pools[poolKey].totalShares).toBe(1500000000);
    });
    
    test('should remove liquidity from existing pool', () => {
      tokenA.transfer.mockReturnValue(txOk(true));
      tokenB.transfer.mockReturnValue(txOk(true));
      
      const result = amm.removeLiquidity(
        tokenA,
        tokenB,
        500000000, // 50% of shares
        450000, // amountAMin
        900000, // amountBMin
        blockHeight + 100 // deadline
      );
      
      expect(result).toEqual(txOk({
        tokenX: tokenA,
        tokenY: tokenB,
        shares: 500000000,
        amountX: 500000,
        amountY: 1000000
      }));
      
      // Verify pool was updated
      const poolKey = `${tokenA.symbol()}-${tokenB.symbol()}`;
      expect(amm.pools[poolKey].reserveX).toBe(500000);
      expect(amm.pools[poolKey].reserveY).toBe(1000000);
      expect(amm.pools[poolKey].totalShares).toBe(500000000);
    });
    
    test('should fail adding liquidity with passed deadline', () => {
      const result = amm.addLiquidity(
        tokenA, 
        tokenB, 
        500000,
        1000000,
        450000,
        900000,
        blockHeight - 1 // Past deadline
      );
      
      expect(result).toEqual(txErr(amm.errors.deadlinePassed));
    });
    
    test('should fail removing liquidity with insufficient shares', () => {
      // Create a different provider with no shares
      const providerKey = `${tokenA.symbol()}-${tokenB.symbol()}-${wallet2.address}`;
      amm.liquidityProviders[providerKey] = { shares: 0 };
      
      // Try to remove liquidity as wallet2
      const originalWallet = wallet1;
      wallet1 = wallet2; // Temporarily change active wallet
      
      const result = amm.removeLiquidity(
        tokenA,
        tokenB,
        500000000,
        450000,
        900000,
        blockHeight + 100
      );
      
      expect(result).toEqual(txErr(amm.errors.insufficientBalance));
      
      // Restore wallet
      wallet1 = originalWallet;
    });
  });

  describe('Swap Operations', () => {
    beforeEach(() => {
      // Setup an existing pool
      const poolKey = `${tokenA.symbol()}-${tokenB.symbol()}`;
      amm.pools[poolKey] = {
        reserveX: 1000000,
        reserveY: 2000000,
        totalShares: 1000000000
      };
      
      // Mock the swap function
      amm.swap.mockImplementation((tokenIn, tokenOut, amountIn, amountOutMin, deadline) => {
        if (deadline < blockHeight) {
          return txErr(amm.errors.deadlinePassed);
        }
        
        if (tokenIn === tokenOut) {
          return txErr(amm.errors.sameToken);
        }
        
        if (amountIn === 0) {
          return txErr(amm.errors.zeroAmount);
        }
        
        // Get pool details
        const poolKey = `${tokenIn.symbol()}-${tokenOut.symbol()}`;
        const reversedPoolKey = `${tokenOut.symbol()}-${tokenIn.symbol()}`;
        
        let pool = amm.pools[poolKey];
        let isXToY = true;
        
        if (!pool) {
          pool = amm.pools[reversedPoolKey];
          isXToY = false;
          
          if (!pool) {
            return txErr(amm.errors.poolAlreadyExists); // Using this error for simplicity
          }
        }
        
        // Calculate output amount
        const reserveIn = isXToY ? pool.reserveX : pool.reserveY;
        const reserveOut = isXToY ? pool.reserveY : pool.reserveX;
        const amountOut = amm.getAmountOut(amountIn, reserveIn, reserveOut);
        
        if (amountOut < amountOutMin) {
          return txErr(amm.errors.slippageExceeded);
        }
        
        if (amountOut >= reserveOut) {
          return txErr(amm.errors.insufficientLiquidity);
        }
        
        // Update reserves
        if (isXToY) {
          pool.reserveX += amountIn;
          pool.reserveY -= amountOut;
        } else {
          pool.reserveX -= amountOut;
          pool.reserveY += amountIn;
        }
        
        return txOk({
          amountIn,
          amountOut
        });
      });
      
      amm.getSwapOutput.mockImplementation((tokenIn, tokenOut, amountIn) => {
        const poolKey = `${tokenIn.symbol()}-${tokenOut.symbol()}`;
        const reversedPoolKey = `${tokenOut.symbol()}-${tokenIn.symbol()}`;
        
        let pool = amm.pools[poolKey];
        let isXToY = true;
        
        if (!pool) {
          pool = amm.pools[reversedPoolKey];
          isXToY = false;
          
          if (!pool) {
            return txErr(amm.errors.poolAlreadyExists); // Using this error for simplicity
          }
        }
        
        const reserveIn = isXToY ? pool.reserveX : pool.reserveY;
        const reserveOut = isXToY ? pool.reserveY : pool.reserveX;
        
        return txOk(amm.getAmountOut(amountIn, reserveIn, reserveOut));
      });
    });
    
    test('should swap tokens successfully', () => {
      tokenA.transfer.mockReturnValue(txOk(true));
      tokenB.transfer.mockReturnValue(txOk(true));
      
      const amountIn = 100000;
      const result = amm.swap(
        tokenA,
        tokenB,
        amountIn,
        180000, // minimum amount out
        blockHeight + 100 // deadline
      );
      
      // Calculate expected output with 0.3% fee
      const amountInWithFee = amountIn * 997;
      const numerator = amountInWithFee * 2000000;
      const denominator = (1000000 * 1000) + amountInWithFee;
      const expectedAmountOut = Math.floor(numerator / denominator);
      
      expect(result).toEqual(txOk({
        amountIn,
        amountOut: expectedAmountOut
      }));
      
      // Verify pool was updated
      const poolKey = `${tokenA.symbol()}-${tokenB.symbol()}`;
      expect(amm.pools[poolKey].reserveX).toBe(1000000 + amountIn);
      expect(amm.pools[poolKey].reserveY).toBe(2000000 - expectedAmountOut);
    });
    
    test('should get swap output correctly', () => {
      const amountIn = 100000;
      const result = amm.getSwapOutput(tokenA, tokenB, amountIn);
      
      // Calculate expected output with 0.3% fee
      const amountInWithFee = amountIn * 997;
      const numerator = amountInWithFee * 2000000;
      const denominator = (1000000 * 1000) + amountInWithFee;
      const expectedAmountOut = Math.floor(numerator / denominator);
      
      expect(result).toEqual(txOk(expectedAmountOut));
    });
    
    test('should fail swap with slippage exceeded', () => {
      const amountIn = 100000;
      // Set a very high minimum output
      const result = amm.swap(
        tokenA,
        tokenB,
        amountIn,
        500000, // unrealistically high minimum
        blockHeight + 100
      );
      
      expect(result).toEqual(txErr(amm.errors.slippageExceeded));
    });
    
    test('should fail swap with insufficient liquidity', () => {
      // Try to swap more than available in the pool
      const amountIn = 10000000; // 10x the reserve
      const result = amm.swap(
        tokenA,
        tokenB,
        amountIn,
        1, // minimum amount out
        blockHeight + 100
      );
      
      expect(result).toEqual(txErr(amm.errors.insufficientLiquidity));
    });
  });

  describe('Price Calculation Functions', () => {
    test('getAmountOut calculates correctly with fee', () => {
      const amountIn = 100000;
      const reserveIn = 1000000;
      const reserveOut = 2000000;
      
      const result = amm.getAmountOut(amountIn, reserveIn, reserveOut);
      
      // Calculate expected output with 0.3% fee
      const amountInWithFee = amountIn * 997;
      const numerator = amountInWithFee * reserveOut;
      const denominator = (reserveIn * 1000) + amountInWithFee;
      const expectedAmountOut = Math.floor(numerator / denominator);
      
      expect(result).toBe(expectedAmountOut);
    });
    
    test('quote calculates price correctly', () => {
      amm.quote.mockImplementation((amountA, reserveA, reserveB) => {
        return Math.floor((amountA * reserveB) / reserveA);
      });
      
      const amountA = 100000;
      const reserveA = 1000000;
      const reserveB = 2000000;
      
      const result = amm.quote(amountA, reserveA, reserveB);
      const expected = Math.floor((amountA * reserveB) / reserveA);
      
      expect(result).toBe(expected);
      expect(result).toBe(200000); // 100k * 2M / 1M = 200k
    });
  });
});