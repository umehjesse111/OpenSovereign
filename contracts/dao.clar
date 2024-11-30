;; OpenSoverign DAO Contract
;; Implements basic DAO functionality including proposals, voting, and token management

(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-PROPOSAL-NOT-FOUND (err u101))
(define-constant ERR-INVALID-VOTE (err u102))
(define-constant ERR-ALREADY-VOTED (err u103))
(define-constant ERR-PROPOSAL-EXPIRED (err u104))
(define-constant VOTING-PERIOD u144) ;; ~24 hours in blocks (assuming 10 min block time)

;; Define data variables
(define-data-var total-supply uint u1000000) ;; Initial token supply
(define-data-var proposal-count uint u0)

;; Define data maps
(define-map proposals
    uint
    {
        title: (string-ascii 100),
        description: (string-ascii 500),
        proposer: principal,
        start-block: uint,
        end-block: uint,
        yes-votes: uint,
        no-votes: uint,
        executed: bool
    }
)

(define-map balances principal uint)
(define-map votes {proposal-id: uint, voter: principal} bool)

;; Initialize contract
(define-private (initialize)
    (begin
        (map-set balances CONTRACT-OWNER (var-get total-supply))
        (ok true)
    )
)

;; Token transfer function
(define-public (transfer (amount uint) (recipient principal))
    (let ((sender-balance (default-to u0 (map-get? balances tx-sender))))
        (if (>= sender-balance amount)
            (begin
                (map-set balances tx-sender (- sender-balance amount))
                (map-set balances recipient (+ (default-to u0 (map-get? balances recipient)) amount))
                (ok true)
            )
            (err u1) ;; Insufficient balance
        )
    )
)

;; Create new proposal
(define-public (create-proposal (title (string-ascii 100)) (description (string-ascii 500)))
    (let (
        (proposal-id (var-get proposal-count))
        (start-block block-height)
        (end-block (+ block-height VOTING-PERIOD))
    )
        (begin
            (map-set proposals proposal-id {
                title: title,
                description: description,
                proposer: tx-sender,
                start-block: start-block,
                end-block: end-block,
                yes-votes: u0,
                no-votes: u0,
                executed: false
            })
            (var-set proposal-count (+ proposal-id u1))
            (ok proposal-id)
        )
    )
)

;; Cast vote on proposal
(define-public (vote (proposal-id uint) (support bool))
    (let (
        (proposal (unwrap! (map-get? proposals proposal-id) ERR-PROPOSAL-NOT-FOUND))
        (voter-balance (default-to u0 (map-get? balances tx-sender)))
    )
        (asserts! (>= block-height (get start-block proposal)) ERR-INVALID-VOTE)
        (asserts! (<= block-height (get end-block proposal)) ERR-PROPOSAL-EXPIRED)
        (asserts! (not (default-to false (map-get? votes {proposal-id: proposal-id, voter: tx-sender}))) ERR-ALREADY-VOTED)
        
        (begin
            (map-set votes {proposal-id: proposal-id, voter: tx-sender} true)
            (if support
                (map-set proposals proposal-id 
                    (merge proposal {yes-votes: (+ (get yes-votes proposal) voter-balance)}))
                (map-set proposals proposal-id 
                    (merge proposal {no-votes: (+ (get no-votes proposal) voter-balance)}))
            )
            (ok true)
        )
    )
)

;; Read proposal details
(define-read-only (get-proposal (proposal-id uint))
    (map-get? proposals proposal-id)
)

;; Get voter balance
(define-read-only (get-balance (account principal))
    (default-to u0 (map-get? balances account))
)

;; Execute proposal
(define-public (execute-proposal (proposal-id uint))
    (let (
        (proposal (unwrap! (map-get? proposals proposal-id) ERR-PROPOSAL-NOT-FOUND))
    )
        (asserts! (> block-height (get end-block proposal)) ERR-PROPOSAL-NOT-FOUND)
        (asserts! (not (get executed proposal)) (err u105))
        (asserts! (> (get yes-votes proposal) (get no-votes proposal)) (err u106))
        
        (begin
            (map-set proposals proposal-id (merge proposal {executed: true}))
            ;; Add custom execution logic here
            (ok true)
        )
    )
)