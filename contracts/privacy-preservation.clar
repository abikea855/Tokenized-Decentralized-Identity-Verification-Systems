;; Privacy Preservation Contract
;; Manages data privacy and selective disclosure

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u200))
(define-constant ERR_INVALID_PRIVACY_LEVEL (err u201))
(define-constant ERR_ACCESS_DENIED (err u202))
(define-constant ERR_INVALID_PROOF (err u203))

;; Privacy levels
(define-constant PRIVACY_PUBLIC u0)
(define-constant PRIVACY_SELECTIVE u1)
(define-constant PRIVACY_PRIVATE u2)

;; Data Variables
(define-data-var encryption-key (string-ascii 64) "default-encryption-key")

;; Data Maps
(define-map user-privacy-settings
  { user: principal }
  {
    privacy-level: uint,
    disclosed-fields: (list 10 (string-ascii 32)),
    encryption-enabled: bool,
    zero-knowledge-enabled: bool
  }
)

(define-map encrypted-data
  { user: principal, field: (string-ascii 32) }
  {
    encrypted-value: (string-ascii 128),
    access-hash: (string-ascii 64),
    timestamp: uint
  }
)

(define-map access-permissions
  { data-owner: principal, accessor: principal }
  {
    allowed-fields: (list 10 (string-ascii 32)),
    expiry-time: uint,
    access-count: uint,
    max-access: uint
  }
)

(define-map zero-knowledge-proofs
  { user: principal, proof-id: uint }
  {
    proof-hash: (string-ascii 64),
    verification-key: (string-ascii 64),
    is-valid: bool,
    created-at: uint
  }
)

;; Public Functions

;; Set privacy preferences
(define-public (set-privacy-level (privacy-level uint) (disclosed-fields (list 10 (string-ascii 32))))
  (let (
    (caller tx-sender)
  )
    ;; Validate privacy level
    (asserts! (<= privacy-level u2) ERR_INVALID_PRIVACY_LEVEL)

    (map-set user-privacy-settings
      { user: caller }
      {
        privacy-level: privacy-level,
        disclosed-fields: disclosed-fields,
        encryption-enabled: (> privacy-level u0),
        zero-knowledge-enabled: (is-eq privacy-level u2)
      }
    )

    (ok true)
  )
)

;; Store encrypted data
(define-public (store-encrypted-data (field (string-ascii 32)) (encrypted-value (string-ascii 128)) (access-hash (string-ascii 64)))
  (let (
    (caller tx-sender)
  )
    (map-set encrypted-data
      { user: caller, field: field }
      {
        encrypted-value: encrypted-value,
        access-hash: access-hash,
        timestamp: block-height
      }
    )

    (ok true)
  )
)

;; Grant access permission
(define-public (grant-access (accessor principal) (allowed-fields (list 10 (string-ascii 32))) (duration uint) (max-access uint))
  (let (
    (caller tx-sender)
    (expiry-time (+ block-height duration))
  )
    (map-set access-permissions
      { data-owner: caller, accessor: accessor }
      {
        allowed-fields: allowed-fields,
        expiry-time: expiry-time,
        access-count: u0,
        max-access: max-access
      }
    )

    (ok true)
  )
)

;; Revoke access permission
(define-public (revoke-access (accessor principal))
  (let (
    (caller tx-sender)
  )
    (map-delete access-permissions { data-owner: caller, accessor: accessor })
    (ok true)
  )
)

;; Submit zero-knowledge proof
(define-public (submit-zk-proof (proof-id uint) (proof-hash (string-ascii 64)) (verification-key (string-ascii 64)))
  (let (
    (caller tx-sender)
  )
    (map-set zero-knowledge-proofs
      { user: caller, proof-id: proof-id }
      {
        proof-hash: proof-hash,
        verification-key: verification-key,
        is-valid: true, ;; In real implementation, this would verify the proof
        created-at: block-height
      }
    )

    (ok true)
  )
)

;; Access encrypted data (with permission check)
(define-public (access-data (data-owner principal) (field (string-ascii 32)))
  (let (
    (caller tx-sender)
    (permission-data (unwrap! (map-get? access-permissions { data-owner: data-owner, accessor: caller }) ERR_ACCESS_DENIED))
    (encrypted-info (unwrap! (map-get? encrypted-data { user: data-owner, field: field }) ERR_ACCESS_DENIED))
  )
    ;; Check if access is still valid
    (asserts! (< block-height (get expiry-time permission-data)) ERR_ACCESS_DENIED)
    (asserts! (< (get access-count permission-data) (get max-access permission-data)) ERR_ACCESS_DENIED)

    ;; Check if field is allowed
    (asserts! (is-some (index-of (get allowed-fields permission-data) field)) ERR_ACCESS_DENIED)

    ;; Update access count
    (map-set access-permissions
      { data-owner: data-owner, accessor: caller }
      (merge permission-data { access-count: (+ (get access-count permission-data) u1) })
    )

    (ok encrypted-info)
  )
)

;; Read-only functions

;; Get privacy settings
(define-read-only (get-privacy-settings (user principal))
  (map-get? user-privacy-settings { user: user })
)

;; Get access permissions
(define-read-only (get-access-permissions (data-owner principal) (accessor principal))
  (map-get? access-permissions { data-owner: data-owner, accessor: accessor })
)

;; Check if data access is allowed
(define-read-only (is-access-allowed (data-owner principal) (accessor principal) (field (string-ascii 32)))
  (match (map-get? access-permissions { data-owner: data-owner, accessor: accessor })
    permission-data (and
                      (< block-height (get expiry-time permission-data))
                      (< (get access-count permission-data) (get max-access permission-data))
                      (is-some (index-of (get allowed-fields permission-data) field)))
    false
  )
)

;; Get zero-knowledge proof
(define-read-only (get-zk-proof (user principal) (proof-id uint))
  (map-get? zero-knowledge-proofs { user: user, proof-id: proof-id })
)

;; Verify zero-knowledge proof
(define-read-only (verify-zk-proof (user principal) (proof-id uint) (challenge (string-ascii 64)))
  (match (map-get? zero-knowledge-proofs { user: user, proof-id: proof-id })
    proof-data (get is-valid proof-data) ;; Simplified verification
    false
  )
)

;; Check privacy level
(define-read-only (get-privacy-level (user principal))
  (match (map-get? user-privacy-settings { user: user })
    settings (get privacy-level settings)
    PRIVACY_PUBLIC
  )
)

;; Admin functions

;; Update encryption key (admin only)
(define-public (update-encryption-key (new-key (string-ascii 64)))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (var-set encryption-key new-key)
    (ok true)
  )
)
