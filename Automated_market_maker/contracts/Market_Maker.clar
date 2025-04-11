
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