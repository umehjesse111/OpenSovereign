;; OpenSovereign DAO Contract - Enhanced Version
;; Implements robust DAO functionality with additional safety features and improvements

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-PROPOSAL-NOT-FOUND (err u101))
(define-constant ERR-INVALID-VOTE (err u102))
(define-constant ERR-ALREADY-VOTED (err u103))
(define-constant ERR-PROPOSAL-EXPIRED (err u104))
(define-constant ERR-ALREADY-EXECUTED (err u105))
(define-constant ERR-PROPOSAL-REJECTED (err u106))
(define-constant ERR-ZERO-AMOUNT (err u107))
(define-constant ERR-INSUFFICIENT-QUORUM (err u108))
(define-constant ERR-INVALID-PROPOSAL (err u109))
(define-constant ERR-PROPOSAL-IN-PROGRESS (err u110))

;; Configuration
(define-constant VOTING-PERIOD u144) ;; ~24 hours in blocks
(define-constant MIN-PROPOSAL-THRESHOLD u100000) ;; Minimum tokens needed to create proposal
(define-constant QUORUM-THRESHOLD u300000) ;; Minimum total votes needed
(define-constant MIN_DESCRIPTION_LENGTH u10)
(define-constant PROPOSAL_COOLDOWN u72) ;; ~12 hours cooldown between proposals

;; Data Variables
(define-data-var total-supply uint u1000000)
(define-data-var proposal-count uint u0)
(define-data-var paused bool false)
(define-data-var last-proposal-time uint u0)

;; Data Maps
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
        executed: bool,
        canceled: bool,
        execution-delay: uint,
        total-votes-cast: uint
    }
)

(define-map balances principal uint)
(define-map votes 
    {proposal-id: uint, voter: principal} 
    {amount: uint, support: bool}
)

;; Authorization check
(define-private (is-contract-owner)
    (is-eq tx-sender CONTRACT-OWNER)
)

;; Emergency pause
(define-public (set-pause (pause bool))
    (begin
        (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
        (var-set paused pause)
        (ok true)
    )
)

;; Token transfer function with additional checks
(define-public (transfer (amount uint) (recipient principal))
    (begin
        (asserts! (not (var-get paused)) ERR-NOT-AUTHORIZED)
        (asserts! (> amount u0) ERR-ZERO-AMOUNT)
        (asserts! (not (is-eq tx-sender recipient)) ERR-INVALID-VOTE)
        
        (let ((sender-balance (default-to u0 (map-get? balances tx-sender))))
            (asserts! (>= sender-balance amount) (err u1))
            
            (map-set balances tx-sender (- sender-balance amount))
            (map-set balances recipient (+ (default-to u0 (map-get? balances recipient)) amount))
            (ok true)
        )
    )
)

;; Create new proposal with additional validation
(define-public (create-proposal (title (string-ascii 100)) (description (string-ascii 500)) (execution-delay uint))
    (begin
        (asserts! (not (var-get paused)) ERR-NOT-AUTHORIZED)
        (asserts! (>= (len description) MIN_DESCRIPTION_LENGTH) ERR-INVALID-PROPOSAL)
        (asserts! (>= (get-balance tx-sender) MIN-PROPOSAL-THRESHOLD) ERR-NOT-AUTHORIZED)
        (asserts! (>= (- block-height (var-get last-proposal-time)) PROPOSAL_COOLDOWN) ERR-PROPOSAL-IN-PROGRESS)
        
        (let (
            (proposal-id (var-get proposal-count))
            (start-block block-height)
            (end-block (+ block-height VOTING-PERIOD))
        )
            (map-set proposals proposal-id {
                title: title,
                description: description,
                proposer: tx-sender,
                start-block: start-block,
                end-block: end-block,
                yes-votes: u0,
                no-votes: u0,
                executed: false,
                canceled: false,
                execution-delay: execution-delay,
                total-votes-cast: u0
            })
            (var-set proposal-count (+ proposal-id u1))
            (var-set last-proposal-time block-height)
            (ok proposal-id)
        )
    )
)

;; Enhanced voting function with vote tracking
(define-public (vote (proposal-id uint) (support bool))
    (begin
        (asserts! (not (var-get paused)) ERR-NOT-AUTHORIZED)
        
        (let (
            (proposal (unwrap! (map-get? proposals proposal-id) ERR-PROPOSAL-NOT-FOUND))
            (voter-balance (default-to u0 (map-get? balances tx-sender)))
        )
            (asserts! (>= block-height (get start-block proposal)) ERR-INVALID-VOTE)
            (asserts! (<= block-height (get end-block proposal)) ERR-PROPOSAL-EXPIRED)
            (asserts! (not (get canceled proposal)) ERR-PROPOSAL-EXPIRED)
            (asserts! (is-none (map-get? votes {proposal-id: proposal-id, voter: tx-sender})) ERR-ALREADY-VOTED)
            (asserts! (> voter-balance u0) ERR-NOT-AUTHORIZED)
            
            (map-set votes {proposal-id: proposal-id, voter: tx-sender} 
                {amount: voter-balance, support: support})
                
            (map-set proposals proposal-id 
                (merge proposal {
                    yes-votes: (if support (+ (get yes-votes proposal) voter-balance) (get yes-votes proposal)),
                    no-votes: (if support (get no-votes proposal) (+ (get no-votes proposal) voter-balance)),
                    total-votes-cast: (+ (get total-votes-cast proposal) voter-balance)
                }))
            
            (ok true)
        )
    )
)

;; Cancel proposal
(define-public (cancel-proposal (proposal-id uint))
    (let (
        (proposal (unwrap! (map-get? proposals proposal-id) ERR-PROPOSAL-NOT-FOUND))
    )
        (asserts! (or (is-contract-owner) (is-eq tx-sender (get proposer proposal))) ERR-NOT-AUTHORIZED)
        (asserts! (not (get executed proposal)) ERR-ALREADY-EXECUTED)
        (asserts! (<= block-height (get end-block proposal)) ERR-PROPOSAL-EXPIRED)
        
        (map-set proposals proposal-id (merge proposal {canceled: true}))
        (ok true)
    )
)

;; Enhanced proposal execution with quorum check
(define-public (execute-proposal (proposal-id uint))
    (let (
        (proposal (unwrap! (map-get? proposals proposal-id) ERR-PROPOSAL-NOT-FOUND))
    )
        (asserts! (not (var-get paused)) ERR-NOT-AUTHORIZED)
        (asserts! (> block-height (+ (get end-block proposal) (get execution-delay proposal))) ERR-PROPOSAL-NOT-FOUND)
        (asserts! (not (get executed proposal)) ERR-ALREADY-EXECUTED)
        (asserts! (not (get canceled proposal)) ERR-PROPOSAL-EXPIRED)
        (asserts! (>= (get total-votes-cast proposal) QUORUM-THRESHOLD) ERR-INSUFFICIENT-QUORUM)
        (asserts! (> (get yes-votes proposal) (get no-votes proposal)) ERR-PROPOSAL-REJECTED)
        
        (begin
            (map-set proposals proposal-id (merge proposal {executed: true}))
            ;; Add custom execution logic here
            (ok true)
        )
    )
)

;; Read-only functions
(define-read-only (get-proposal (proposal-id uint))
    (map-get? proposals proposal-id)
)

(define-read-only (get-vote (proposal-id uint) (voter principal))
    (map-get? votes {proposal-id: proposal-id, voter: voter})
)

(define-read-only (get-balance (account principal))
    (default-to u0 (map-get? balances account))
)

