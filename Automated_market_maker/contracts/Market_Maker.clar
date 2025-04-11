
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