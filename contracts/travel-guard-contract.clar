;; TravelGuard - Smart Contract Travel Insurance
;; A decentralized travel insurance platform that provides automatic payouts
;; based on verifiable travel disruptions like flight delays, cancellations, etc.

;; Define constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-policy-not-found (err u101))
(define-constant err-already-claimed (err u102))
(define-constant err-not-policy-holder (err u103))
(define-constant err-not-oracle (err u104))
(define-constant err-invalid-premium (err u105))
(define-constant err-invalid-coverage (err u106))
(define-constant err-policy-expired (err u107))
(define-constant err-insufficient-funds (err u108))
(define-constant err-not-disrupted (err u109))

;; Define data maps
(define-map policies
  { policy-id: uint }
  {
    holder: principal,
    premium-paid: uint,
    coverage-amount: uint,
    flight-number: (string-ascii 10),
    departure-date: uint,
    expiration-date: uint,
    claimed: bool
  }
)

(define-map oracles
  { oracle: principal }
  { active: bool }
)

(define-map flight-disruptions
  { flight-number: (string-ascii 10), date: uint }
  { 
    disrupted: bool,
    disruption-type: (string-ascii 20),
    delay-minutes: uint
  }
)

;; Define data variables
(define-data-var policy-counter uint u0)
(define-data-var treasury-balance uint u0)

;; Read-only functions

(define-read-only (get-policy (policy-id uint))
  (map-get? policies { policy-id: policy-id })
)

(define-read-only (get-policy-count)
  (var-get policy-counter)
)

(define-read-only (get-treasury-balance)
  (var-get treasury-balance)
)

(define-read-only (check-flight-disruption (flight-number (string-ascii 10)) (date uint))
  (map-get? flight-disruptions { flight-number: flight-number, date: date })
)

(define-read-only (is-oracle (address principal))
  (default-to false (get active (map-get? oracles { oracle: address })))
)

;; Public functions

;; Purchase a new insurance policy
(define-public (purchase-policy 
    (premium uint) 
    (coverage-amount uint) 
    (flight-number (string-ascii 10)) 
    (departure-date uint)
    (expiration-date uint))
  (let
    (
      (new-policy-id (+ (var-get policy-counter) u1))
    )
    ;; Validate inputs
    (asserts! (> premium u0) err-invalid-premium)
    (asserts! (> coverage-amount premium) err-invalid-coverage)
    (asserts! (> expiration-date departure-date) err-invalid-coverage)

    ;; Transfer premium payment to contract
    (try! (stx-transfer? premium tx-sender (as-contract tx-sender)))

    ;; Update treasury balance
    (var-set treasury-balance (+ (var-get treasury-balance) premium))

    ;; Create new policy
    (map-set policies
      { policy-id: new-policy-id }
      {
        holder: tx-sender,
        premium-paid: premium,
        coverage-amount: coverage-amount,
        flight-number: flight-number,
        departure-date: departure-date,
        expiration-date: expiration-date,
        claimed: false
      }
    )

    ;; Increment policy counter
    (var-set policy-counter new-policy-id)

    ;; Return policy ID
    (ok new-policy-id)
  )
)

;; Report flight disruption (oracle only)
(define-public (report-disruption 
    (flight-number (string-ascii 10)) 
    (date uint) 
    (disruption-type (string-ascii 20))
    (delay-minutes uint))
  (begin
    ;; Check if sender is an authorized oracle
    (asserts! (is-oracle tx-sender) err-not-oracle)

    ;; Record the disruption
    (map-set flight-disruptions
      { flight-number: flight-number, date: date }
      { 
        disrupted: true,
        disruption-type: disruption-type,
        delay-minutes: delay-minutes
      }
    )

    (ok true)
  )
)

;; Claim insurance payout
(define-public (claim-payout (policy-id uint))
  (let
    (
      (policy (unwrap! (get-policy policy-id) err-policy-not-found))
      (holder (get holder policy))
      (claimed (get claimed policy))
      (coverage (get coverage-amount policy))
      (flight (get flight-number policy))
      (date (get departure-date policy))
      (expiration (get expiration-date policy))
      (disruption (unwrap! (check-flight-disruption flight date) err-policy-not-found))
      (is-disrupted (get disrupted disruption))
      (current-time block-height)
    )

    ;; Validate claim
    (asserts! (is-eq tx-sender holder) err-not-policy-holder)
    (asserts! (not claimed) err-already-claimed)
    (asserts! (< current-time expiration) err-policy-expired)
    (asserts! is-disrupted err-not-disrupted)

    ;; Update policy to claimed
    (map-set policies
      { policy-id: policy-id }
      (merge policy { claimed: true })
    )

    ;; Update treasury balance
    (var-set treasury-balance (- (var-get treasury-balance) coverage))

    ;; Transfer coverage amount to policy holder
    (as-contract (stx-transfer? coverage contract-caller holder))
  )
)

;; Admin functions

;; Add or update oracle
(define-public (set-oracle (oracle principal) (active bool))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (map-set oracles { oracle: oracle } { active: active })
    (ok true)
  )
)

;; Withdraw funds from treasury (owner only)
(define-public (withdraw-funds (amount uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (<= amount (var-get treasury-balance)) err-insufficient-funds)

    ;; Update treasury balance
    (var-set treasury-balance (- (var-get treasury-balance) amount))

    ;; Transfer funds to owner
    (as-contract (stx-transfer? amount tx-sender contract-owner))
  )
)