;; Define trait for executable proposals
(use-trait proposal-trait .proposal-trait.proposal-trait)

;; Define constants
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-ALREADY-MEMBER (err u101))
(define-constant ERR-NOT-MEMBER (err u102))
(define-constant ERR-PROPOSAL-NOT-FOUND (err u103))
(define-constant ERR-ALREADY-VOTED (err u104))
(define-constant ERR-VOTING-CLOSED (err u105))

;; Define data variables
(define-data-var proposal-count uint u0)

;; Define data maps
(define-map members principal bool)
(define-map proposals 
  uint 
  { 
    proposer: principal, 
    description: (string-utf8 256), 
    votes-for: uint, 
    votes-against: uint, 
    status: (string-utf8 20),
    execution-function: (optional principal)
  }
)
(define-map votes {proposal-id: uint, voter: principal} bool)

;; Contract owner
(define-data-var contract-owner principal tx-sender)

;; Functions

;; Add a new member
(define-public (add-member (new-member principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (asserts! (is-none (map-get? members new-member)) ERR-ALREADY-MEMBER)
    (ok (map-set members new-member true))
  )
)

;; Create a new proposal
(define-public (create-proposal (description (string-utf8 256)) (execution-function (optional principal)))
  (let ((proposal-id (+ (var-get proposal-count) u1)))
    (asserts! (is-some (map-get? members tx-sender)) ERR-NOT-MEMBER)
    (map-set proposals proposal-id 
      {
        proposer: tx-sender,
        description: description,
        votes-for: u0,
        votes-against: u0,
        status: u"active",
        execution-function: execution-function
      }
    )
    (var-set proposal-count proposal-id)
    (ok proposal-id)
  )
)

;; Vote on a proposal
(define-public (vote (proposal-id uint) (vote-for bool))
  (let (
    (proposal (unwrap! (map-get? proposals proposal-id) ERR-PROPOSAL-NOT-FOUND))
    (has-voted (default-to false (map-get? votes {proposal-id: proposal-id, voter: tx-sender})))
  )
    (asserts! (is-some (map-get? members tx-sender)) ERR-NOT-MEMBER)
    (asserts! (not has-voted) ERR-ALREADY-VOTED)
    (asserts! (is-eq (get status proposal) u"active") ERR-VOTING-CLOSED)
    (map-set votes {proposal-id: proposal-id, voter: tx-sender} true)
    (if vote-for
      (map-set proposals proposal-id (merge proposal {votes-for: (+ (get votes-for proposal) u1)}))
      (map-set proposals proposal-id (merge proposal {votes-against: (+ (get votes-against proposal) u1)}))
    )
    (ok true)
  )
)

;; Close voting on a proposal
(define-public (close-voting (proposal-id uint))
  (let (
    (proposal (unwrap! (map-get? proposals proposal-id) ERR-PROPOSAL-NOT-FOUND))
  )
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status proposal) u"active") ERR-VOTING-CLOSED)
    (if (> (get votes-for proposal) (get votes-against proposal))
      (map-set proposals proposal-id (merge proposal {status: u"approved"}))
      (map-set proposals proposal-id (merge proposal {status: u"rejected"}))
    )
    (ok true)
  )
)

;; Execute an approved proposal
(define-public (execute-proposal (proposal-id uint) (executable <proposal-trait>))
  (let (
    (proposal (unwrap! (map-get? proposals proposal-id) ERR-PROPOSAL-NOT-FOUND))
  )
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status proposal) u"approved") ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (some (contract-of executable)) (get execution-function proposal)) ERR-NOT-AUTHORIZED)
    (contract-call? executable execute)
  )
)

;; Read-only functions

;; Check if an address is a member
(define-read-only (is-member (address principal))
  (default-to false (map-get? members address))
)

;; Get proposal details
(define-read-only (get-proposal (proposal-id uint))
  (map-get? proposals proposal-id)
)

;; Get the total number of proposals
(define-read-only (get-proposal-count)
  (var-get proposal-count)
)