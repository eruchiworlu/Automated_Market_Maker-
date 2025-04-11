
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