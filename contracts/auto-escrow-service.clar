;; ---------------------------------------------------------
;; Contract: auto-escrow-service.clar
;; Description: A trustless escrow system for P2P vehicle sales.
;; It manages the sale lifecycle from deposit to fund release,
;; ensuring both buyer and seller are protected.
;; This contract is intended to be used with STX as the payment currency.
;;
;; Version: 1.0.0
;; ---------------------------------------------------------

;; --- Constants and Errors ---
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u101))
(define-constant ERR-SALE-NOT-FOUND (err u102))
(define-constant ERR-INVALID-SALE-STATUS (err u103))
(define-constant ERR-BUYER-ONLY (err u104))
(define-constant ERR-SELLER-ONLY (err u105))
(define-constant ERR-INSUFFICIENT-FUNDS (err u106))
(define-constant ERR-SALE-ALREADY-EXISTS (err u107))
(define-constant ERR-AMOUNT-MISMATCH (err u108))
(define-constant ERR-SALE-NOT-FUNDED (err u109))
(define-constant ERR-ESCROW-NOT-CONFIRMED (err u110))

;; --- Data Storage ---
(define-data-var last-sale-id uint u0)
;; Fee percentage taken by the contract owner on successful sales. (e.g., u100 = 1.00%)
(define-data-var platform-fee-permille uint u100) ;; 1% fee

;; --- Data Maps ---
;; Maps a sale ID to the details of the sale agreement.
(define-map sales uint {
  seller: principal,
  buyer: principal,
  sale-price: uint,
  vin: (string-ascii 17),
  status: uint ;; u0: Initiated, u1: Funded, u2: Delivery-Confirmed, u3: Complete, u4: Canceled
})

;; =========================================================
;; --- Administrative Functions ---
;; =========================================================

;; @desc Updates the platform fee. Can only be called by the contract owner.
;; @param new-fee-permille: The new fee in permille (1/1000). e.g., u50 is 0.5%.
;; @returns (response bool uint)
(define-public (set-platform-fee (new-fee-permille uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (ok (var-set platform-fee-permille new-fee-permille))
  )
)

;; =========================================================
;; --- Core Escrow Functions ---
;; =========================================================

;; @desc Creates a new sale agreement. Initiated by the seller.
;; @param buyer: The principal of the prospective buyer.
;; @param sale-price: The agreed price of the vehicle in micro-STX.
;; @param vin: The VIN of the vehicle being sold.
;; @returns (response uint uint) The new sale ID.
(define-public (initiate-sale (buyer principal) (sale-price uint) (vin (string-ascii 17)))
  (begin
    (let ((sale-id (+ u1 (var-get last-sale-id))))
      (map-set sales sale-id {
        seller: tx-sender,
        buyer: buyer,
        sale-price: sale-price,
        vin: vin,
        status: u0 ;; Status: Initiated
      })
      (var-set last-sale-id sale-id)

      (print {
        event: "initiate-sale",
        sale-id: sale-id,
        seller: tx-sender,
        buyer: buyer,
        price: sale-price
      })
      (ok sale-id)
    )
  )
)

;; @desc Buyer deposits STX into escrow to fund the sale.
;; @param sale-id: The ID of the sale to fund.
;; @returns (response bool uint)
(define-public (fund-escrow (sale-id uint))
  (begin
    (let ((sale (unwrap! (map-get? sales sale-id) ERR-SALE-NOT-FOUND)))
      (asserts! (is-eq tx-sender (get buyer sale)) ERR-BUYER-ONLY)
      (asserts! (is-eq (get status sale) u0) ERR-INVALID-SALE-STATUS) ;; Must be 'Initiated'

      ;; Transfer STX from buyer to this contract
      (try! (stx-transfer? (get sale-price sale) tx-sender (as-contract tx-sender)))

      (map-set sales sale-id (merge sale { status: u1 })) ;; Status: Funded

      (print {
        event: "fund-escrow",
        sale-id: sale-id,
        buyer: tx-sender,
        amount: (get sale-price sale)
      })
      (ok true)
    )
  )
)

;; @desc Buyer confirms they have received the vehicle and title satisfactorily.
;; @param sale-id: The ID of the sale.
;; @returns (response bool uint)
(define-public (confirm-delivery (sale-id uint))
  (begin
    (let ((sale (unwrap! (map-get? sales sale-id) ERR-SALE-NOT-FOUND)))
      (asserts! (is-eq tx-sender (get buyer sale)) ERR-BUYER-ONLY)
      (asserts! (is-eq (get status sale) u1) ERR-INVALID-SALE-STATUS) ;; Must be 'Funded'

      (map-set sales sale-id (merge sale { status: u2 })) ;; Status: Delivery-Confirmed

      (print {
        event: "confirm-delivery",
        sale-id: sale-id,
        buyer: tx-sender
      })
      (ok true)
    )
  )
)

;; @desc Releases funds to the seller after buyer confirmation. Can be called by anyone.
;; @param sale-id: The ID of the sale.
;; @returns (response bool uint)
(define-public (release-funds (sale-id uint))
  (begin
    (let ((sale (unwrap! (map-get? sales sale-id) ERR-SALE-NOT-FOUND)))
      (asserts! (is-eq (get status sale) u2) ERR-ESCROW-NOT-CONFIRMED) ;; Must be 'Delivery-Confirmed'

      (let ((total-amount (get sale-price sale))
            (platform-fee (/ (* total-amount (var-get platform-fee-permille)) u1000))
            (seller-payment (- total-amount platform-fee)))

        ;; Pay platform fee to contract owner
        (try! (as-contract (stx-transfer? platform-fee (as-contract tx-sender) CONTRACT-OWNER)))
        ;; Pay seller
        (try! (as-contract (stx-transfer? seller-payment (as-contract tx-sender) (get seller sale))))

        (map-set sales sale-id (merge sale { status: u3 })) ;; Status: Complete

        (print {
          event: "release-funds",
          sale-id: sale-id,
          seller: (get seller sale),
          amount: seller-payment
        })
        (ok true)
      )
    )
  )
)

;; @desc Cancels a sale. Can only be done by buyer or seller before funds are released.
;;       If funded, returns STX to the buyer.
;; @param sale-id: The ID of the sale to cancel.
;; @returns (response bool uint)
(define-public (cancel-sale (sale-id uint))
  (begin
    (let ((sale (unwrap! (map-get? sales sale-id) ERR-SALE-NOT-FOUND)))
      (asserts! (or (is-eq tx-sender (get buyer sale)) (is-eq tx-sender (get seller sale))) ERR-NOT-AUTHORIZED)
      (asserts! (or (is-eq (get status sale) u0) (is-eq (get status sale) u1)) ERR-INVALID-SALE-STATUS)

      ;; If the sale was funded, refund the buyer
      (if (is-eq (get status sale) u1)
        (try! (as-contract (stx-transfer? (get sale-price sale) (as-contract tx-sender) (get buyer sale))))
        true
      )

      (map-set sales sale-id (merge sale { status: u4 })) ;; Status: Canceled

      (print {
        event: "cancel-sale",
        sale-id: sale-id,
        canceled-by: tx-sender
      })
      (ok true)
    )
  )
)

;; =========================================================
;; --- Read-Only Functions ---
;; =========================================================

;; @desc Gets the details for a specific sale.
;; @param sale-id: The ID of the sale.
;; @returns (optional {seller: principal, buyer: principal, ...})
(define-read-only (get-sale-details (sale-id uint))
  (map-get? sales sale-id)
)

;; @desc Gets the current platform fee.
;; @returns uint
(define-read-only (get-platform-fee)
  (var-get platform-fee-permille)
)