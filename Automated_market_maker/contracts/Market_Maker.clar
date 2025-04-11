
;; title: Automated Market Maker (AMM) contract for Stacks

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-token-owner (err u101))
(define-constant err-insufficient-balance (err u102))
(define-constant err-insufficient-liquidity (err u103))
(define-constant err-zero-amount (err u104))
(define-constant err-same-token (err u105))
(define-constant err-slippage-exceeded (err u106))
(define-constant err-deadline-passed (err u107))
(define-constant fee-denominator u1000)
(define-constant fee-numerator u3) ;; 0.3% fee


;; Data variables
(define-data-var total-liquidity uint u0)

;; Data maps
(define-map pools 
  { token-x: principal, token-y: principal } 
  { 
    reserve-x: uint, 
    reserve-y: uint,
    total-shares: uint 
  }
)

(define-map liquidity-providers
  { token-x: principal, token-y: principal, provider: principal }
  { shares: uint }
)

;; Read-only functions
(define-read-only (get-pool-details (token-x principal) (token-y principal))
  (map-get? pools { token-x: token-x, token-y: token-y })
)

(define-read-only (get-provider-shares (token-x principal) (token-y principal) (provider principal))
  (default-to
    { shares: u0 }
    (map-get? liquidity-providers { token-x: token-x, token-y: token-y, provider: provider })
  )
)


(define-read-only (get-amount-out (amount-in uint) (reserve-in uint) (reserve-out uint))
  (let 
    (
      (amount-in-with-fee (mul amount-in (- fee-denominator fee-numerator)))
      (numerator (mul amount-in-with-fee reserve-out))
      (denominator (+ (* reserve-in fee-denominator) amount-in-with-fee))
    )
    (/ numerator denominator)
  )
)

(define-read-only (get-amount-in (amount-out uint) (reserve-in uint) (reserve-out uint))
  (let 
    (
      (numerator (mul reserve-in amount-out fee-denominator))
      (denominator (mul (- reserve-out amount-out) (- fee-denominator fee-numerator)))
    )
    (+ (/ numerator denominator) u1)
  )
)

(define-read-only (quote (amount-a uint) (reserve-a uint) (reserve-b uint))
  (/ (mul amount-a reserve-b) reserve-a)
)

;; Private functions
(define-private (get-ordered-pair (token-a principal) (token-b principal))
  (if (< token-a token-b)
    { token-x: token-a, token-y: token-b }
    { token-x: token-b, token-y: token-a }
  )
)

(define-private (transfer-token (token principal) (amount uint) (sender principal) (recipient principal))
  (contract-call? token transfer amount sender recipient none)
)

;; Public functions
(define-public (create-pool (token-a principal) (token-b principal) (amount-a uint) (amount-b uint))
  (let 
    (
      (pair (get-ordered-pair token-a token-b))
      (token-x (get token-x pair))
      (token-y (get token-y pair))
      (amount-x (if (is-eq token-a token-x) amount-a amount-b))
      (amount-y (if (is-eq token-a token-x) amount-b amount-a))
      (initial-shares u1000000000) ;; 1 billion initial LP tokens
    )
    
    ;; Ensure tokens are different
    (asserts! (not (is-eq token-a token-b)) err-same-token)
    ;; Ensure amounts are not zero
    (asserts! (and (> amount-x u0) (> amount-y u0)) err-zero-amount)
    ;; Ensure pool doesn't exist yet
    (asserts! (is-none (get-pool-details token-x token-y)) (err u108))
    
    ;; Transfer tokens to contract
    (unwrap! (transfer-token token-x amount-x tx-sender (as-contract tx-sender)) (err u109))
    (unwrap! (transfer-token token-y amount-y tx-sender (as-contract tx-sender)) (err u110))
    
    ;; Create the pool
    (map-set pools 
      { token-x: token-x, token-y: token-y } 
      { reserve-x: amount-x, reserve-y: amount-y, total-shares: initial-shares }
    )
    
    ;; Assign LP tokens to creator
    (map-set liquidity-providers
      { token-x: token-x, token-y: token-y, provider: tx-sender }
      { shares: initial-shares }
    )
    
    (ok { token-x: token-x, token-y: token-y, shares: initial-shares })
  )
)

(define-public (add-liquidity (token-a principal) (token-b principal) (amount-a-desired uint) (amount-b-desired uint) (amount-a-min uint) (amount-b-min uint) (deadline uint))
  (let 
    (
      (pair (get-ordered-pair token-a token-b))
      (token-x (get token-x pair))
      (token-y (get token-y pair))
      (amount-x-desired (if (is-eq token-a token-x) amount-a-desired amount-b-desired))
      (amount-y-desired (if (is-eq token-a token-x) amount-b-desired amount-a-desired))
      (amount-x-min (if (is-eq token-a token-x) amount-a-min amount-b-min))
      (amount-y-min (if (is-eq token-a token-x) amount-b-min amount-a-min))
      (current-block-height (unwrap! (get-block-info? height (- block-height u1)) (err u111)))
    )
    
    ;; Ensure deadline is not passed
    (asserts! (<= current-block-height deadline) err-deadline-passed)
    ;; Ensure tokens are different
    (asserts! (not (is-eq token-a token-b)) err-same-token)
    ;; Ensure amounts are not zero
    (asserts! (and (> amount-x-desired u0) (> amount-y-desired u0)) err-zero-amount)
    
    (match (get-pool-details token-x token-y)
      pool
      (let 
        (
          (reserve-x (get reserve-x pool))
          (reserve-y (get reserve-y pool))
          (total-shares (get total-shares pool))
          
          ;; Calculate optimal amounts
          (amount-x (if (is-eq reserve-x u0) 
                      amount-x-desired 
                      (min amount-x-desired (/ (* amount-y-desired reserve-x) reserve-y))))
          (amount-y (if (is-eq reserve-y u0) 
                      amount-y-desired 
                      (min amount-y-desired (/ (* amount-x-desired reserve-y) reserve-x))))
        )
        
        ;; Check minimums
        (asserts! (>= amount-x amount-x-min) err-slippage-exceeded)
        (asserts! (>= amount-y amount-y-min) err-slippage-exceeded)
        
        ;; Calculate liquidity shares
        (let 
          (
            (new-shares (if (is-eq total-shares u0)
                          (sqrti (* amount-x amount-y))
                          (min 
                            (/ (* amount-x total-shares) reserve-x)
                            (/ (* amount-y total-shares) reserve-y)
                          )
                        ))
            (old-shares (get shares (default-to { shares: u0 } (map-get? liquidity-providers { token-x: token-x, token-y: token-y, provider: tx-sender }))))
          )
          
          ;; Transfer tokens to contract
          (unwrap! (transfer-token token-x amount-x tx-sender (as-contract tx-sender)) (err u112))
          (unwrap! (transfer-token token-y amount-y tx-sender (as-contract tx-sender)) (err u113))
          
          ;; Update pool
          (map-set pools 
            { token-x: token-x, token-y: token-y } 
            { 
              reserve-x: (+ reserve-x amount-x), 
              reserve-y: (+ reserve-y amount-y), 
              total-shares: (+ total-shares new-shares) 
            }
          )
          
          ;; Update provider shares
          (map-set liquidity-providers
            { token-x: token-x, token-y: token-y, provider: tx-sender }
            { shares: (+ old-shares new-shares) }
          )
          
          (ok { token-x: token-x, token-y: token-y, shares: new-shares, amount-x: amount-x, amount-y: amount-y })
        )
      )
      ;; If pool doesn't exist, create it
      (create-pool token-a token-b amount-a-desired amount-b-desired)
    )
  )
)


(define-public (remove-liquidity (token-a principal) (token-b principal) (shares uint) (amount-a-min uint) (amount-b-min uint) (deadline uint))
  (let 
    (
      (pair (get-ordered-pair token-a token-b))
      (token-x (get token-x pair))
      (token-y (get token-y pair))
      (amount-x-min (if (is-eq token-a token-x) amount-a-min amount-b-min))
      (amount-y-min (if (is-eq token-a token-x) amount-b-min amount-a-min))
      (current-block-height (unwrap! (get-block-info? height (- block-height u1)) (err u111)))
    )
    
    ;; Ensure deadline is not passed
    (asserts! (<= current-block-height deadline) err-deadline-passed)
    ;; Ensure shares is not zero
    (asserts! (> shares u0) err-zero-amount)
    
    (match (get-pool-details token-x token-y)
      pool
      (let 
        (
          (reserve-x (get reserve-x pool))
          (reserve-y (get reserve-y pool))
          (total-shares (get total-shares pool))
          (provider-shares (get shares (get-provider-shares token-x token-y tx-sender)))
        )
        
        ;; Ensure provider has enough shares
        (asserts! (>= provider-shares shares) err-insufficient-balance)
        
        ;; Calculate withdrawal amounts
        (let 
          (
            (amount-x (/ (* shares reserve-x) total-shares))
            (amount-y (/ (* shares reserve-y) total-shares))
          )
          
          ;; Check minimums
          (asserts! (>= amount-x amount-x-min) err-slippage-exceeded)
          (asserts! (>= amount-y amount-y-min) err-slippage-exceeded)
          
          ;; Update pool and provider shares
          (map-set pools 
            { token-x: token-x, token-y: token-y } 
            { 
              reserve-x: (- reserve-x amount-x), 
              reserve-y: (- reserve-y amount-y), 
              total-shares: (- total-shares shares) 
            }
          )
          
          (map-set liquidity-providers
            { token-x: token-x, token-y: token-y, provider: tx-sender }
            { shares: (- provider-shares shares) }
          )
          
          ;; Transfer tokens from contract to user
          (as-contract (transfer-token token-x amount-x (as-contract tx-sender) tx-sender))
          (as-contract (transfer-token token-y amount-y (as-contract tx-sender) tx-sender))
          
          (ok { token-x: token-x, token-y: token-y, shares: shares, amount-x: amount-x, amount-y: amount-y })
        )
      )
      (err u114) ;; Pool does not exist
    )
  )
)

(define-public (swap (token-in principal) (token-out principal) (amount-in uint) (amount-out-min uint) (deadline uint))
  (let 
    (
      (pair (get-ordered-pair token-in token-out))
      (token-x (get token-x pair))
      (token-y (get token-y pair))
      (is-x-to-y (is-eq token-in token-x))
      (current-block-height (unwrap! (get-block-info? height (- block-height u1)) (err u111)))
    )
    
    ;; Ensure deadline is not passed
    (asserts! (<= current-block-height deadline) err-deadline-passed)
    ;; Ensure tokens are different
    (asserts! (not (is-eq token-in token-out)) err-same-token)
    ;; Ensure amount is not zero
    (asserts! (> amount-in u0) err-zero-amount)
    
    (match (get-pool-details token-x token-y)
      pool
      (let 
        (
          (reserve-x (get reserve-x pool))
          (reserve-y (get reserve-y pool))
          (reserve-in (if is-x-to-y reserve-x reserve-y))
          (reserve-out (if is-x-to-y reserve-y reserve-x))
          (amount-out (get-amount-out amount-in reserve-in reserve-out))
        )
        
        ;; Ensure output meets minimum
        (asserts! (>= amount-out amount-out-min) err-slippage-exceeded)
        ;; Ensure there's sufficient liquidity
        (asserts! (< amount-out reserve-out) err-insufficient-liquidity)
        
        ;; Transfer token-in to contract
        (unwrap! (transfer-token token-in amount-in tx-sender (as-contract tx-sender)) (err u115))
        
        ;; Update reserves
        (map-set pools 
          { token-x: token-x, token-y: token-y } 
          { 
            reserve-x: (if is-x-to-y (+ reserve-x amount-in) (- reserve-x amount-out)),
            reserve-y: (if is-x-to-y (- reserve-y amount-out) (+ reserve-y amount-in)),
            total-shares: (get total-shares pool)
          }
        )
        
        ;; Transfer token-out to user
        (as-contract (transfer-token token-out amount-out (as-contract tx-sender) tx-sender))
        
        (ok { amount-in: amount-in, amount-out: amount-out })
      )
      (err u114) ;; Pool does not exist
    )
  )
)