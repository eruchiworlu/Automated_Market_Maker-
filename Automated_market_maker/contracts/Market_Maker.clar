
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
