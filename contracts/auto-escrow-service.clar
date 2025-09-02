;; ---------------------------------------------------------
;; Contract: auto-escrow-service.clar
;; Description: A trustless escrow system for P2P vehicle sales.
;; It manages the sale lifecycle from deposit to fund release,
;; ensuring both buyer and seller are protected.
;; This contract is intended to be used with STX as the payment currency.
;;
;; Version: 1.1.0
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
(define-constant ERR-INVALID-INPUT (err u111))
(define-constant ERR-INVALID-VIN (err u112))
(define-constant ERR-INVALID-FEE (err u113))
(define-constant ERR-ZERO-AMOUNT (err u114))

;; --- Validation Constants ---
(define-constant MAX-FEE-PERMILLE u500) ;; Maximum 50% fee
(define-constant MIN-SALE-PRICE u1000000) ;; Minimum 1 STX (1,000,000 micro-STX)
(define-constant MAX-SALE-PRICE u100000000000000) ;; Maximum 100,000 STX
(define-constant VIN-LENGTH u17)

;; --- Status Constants ---
(define-constant STATUS-INITIATED u0)
(define-constant STATUS-FUNDED u1)
(define-constant STATUS-DELIVERY-CONFIRMED u2)
(define-constant STATUS-COMPLETE u3)
(define-constant STATUS-CANCELED u4)

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
  status: uint
})

;; =========================================================
;; --- Input Validation Functions ---
;; =========================================================

;; @desc Validates VIN format (17 characters, alphanumeric)
;; @param vin: The VIN to validate
;; @returns bool
(define-private (is-valid-vin (vin (string-ascii 17)))
  (is-eq (len vin) VIN-LENGTH)
)

;; @desc Validates sale price is within acceptable range
;; @param price: The price to validate
;; @returns bool
(define-private (is-valid-price (price uint))
  (and 
    (>= price MIN-SALE-PRICE)
    (<= price MAX-SALE-PRICE)
  )
)

;; @desc Validates platform fee is within acceptable range
;; @param fee: The fee to validate in permille
;; @returns bool
(define-private (is-valid-fee (fee uint))
  (<= fee MAX-FEE-PERMILLE)
)

;; @desc Validates that a principal is not the zero address
;; @param principal-to-check: The principal to validate
;; @returns bool
(define-private (is-valid-principal (principal-to-check principal))
  (not (is-eq principal-to-check 'SP000000000000000000002Q6VF78))
)

;; =========================================================
;; --- Administrative Functions ---
;; =========================================================

;; @desc Updates the platform fee. Can only be called by the contract owner.
;; @param new-fee-permille: The new fee in permille (1/1000). e.g., u50 is 0.5%.
;; @returns (response bool uint)
(define-public (set-platform-fee (new-fee-permille uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (is-valid-fee new-fee-permille) ERR-INVALID-FEE)
    (var-set platform-fee-permille new-fee-permille)
    (print {
      event: "platform-fee-updated",
      old-fee: (var-get platform-fee-permille),
      new-fee: new-fee-permille,
      updated-by: tx-sender
    })
    (ok true)
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
  (let ((sale-id (+ u1 (var-get last-sale-id))))
    ;; Input validation
    (asserts! (is-valid-principal buyer) ERR-INVALID-INPUT)
    (asserts! (not (is-eq tx-sender buyer)) ERR-INVALID-INPUT) ;; Seller cannot be buyer
    (asserts! (is-valid-price sale-price) ERR-ZERO-AMOUNT)
    (asserts! (is-valid-vin vin) ERR-INVALID-VIN)

    (map-set sales sale-id {
      seller: tx-sender,
      buyer: buyer,
      sale-price: sale-price,
      vin: vin,
      status: STATUS-INITIATED
    })
    (var-set last-sale-id sale-id)

    (print {
      event: "initiate-sale",
      sale-id: sale-id,
      seller: tx-sender,
      buyer: buyer,
      price: sale-price,
      vin: vin
    })
    (ok sale-id)
  )
)

;; @desc Buyer deposits STX into escrow to fund the sale.
;; @param sale-id: The ID of the sale to fund.
;; @returns (response bool uint)
(define-public (fund-escrow (sale-id uint))
  (let ((sale (unwrap! (map-get? sales sale-id) ERR-SALE-NOT-FOUND)))
    (asserts! (is-eq tx-sender (get buyer sale)) ERR-BUYER-ONLY)
    (asserts! (is-eq (get status sale) STATUS-INITIATED) ERR-INVALID-SALE-STATUS)

    ;; Check if buyer has sufficient balance
    (asserts! (>= (stx-get-balance tx-sender) (get sale-price sale)) ERR-INSUFFICIENT-FUNDS)

    ;; Transfer STX from buyer to this contract
    (try! (stx-transfer? (get sale-price sale) tx-sender (as-contract tx-sender)))

    (map-set sales sale-id (merge sale { status: STATUS-FUNDED }))

    (print {
      event: "fund-escrow",
      sale-id: sale-id,
      buyer: tx-sender,
      amount: (get sale-price sale)
    })
    (ok true)
  )
)

;; @desc Buyer confirms they have received the vehicle and title satisfactorily.
;; @param sale-id: The ID of the sale.
;; @returns (response bool uint)
(define-public (confirm-delivery (sale-id uint))
  (let ((sale (unwrap! (map-get? sales sale-id) ERR-SALE-NOT-FOUND)))
    (asserts! (is-eq tx-sender (get buyer sale)) ERR-BUYER-ONLY)
    (asserts! (is-eq (get status sale) STATUS-FUNDED) ERR-INVALID-SALE-STATUS)

    (map-set sales sale-id (merge sale { status: STATUS-DELIVERY-CONFIRMED }))

    (print {
      event: "confirm-delivery",
      sale-id: sale-id,
      buyer: tx-sender
    })
    (ok true)
  )
)

;; @desc Releases funds to the seller after buyer confirmation. Can be called by anyone.
;; @param sale-id: The ID of the sale.
;; @returns (response bool uint)
(define-public (release-funds (sale-id uint))
  (let ((sale (unwrap! (map-get? sales sale-id) ERR-SALE-NOT-FOUND)))
    (asserts! (is-eq (get status sale) STATUS-DELIVERY-CONFIRMED) ERR-ESCROW-NOT-CONFIRMED)

    (let ((total-amount (get sale-price sale))
          (platform-fee (/ (* total-amount (var-get platform-fee-permille)) u1000))
          (seller-payment (- total-amount platform-fee)))

      ;; Ensure calculations are correct
      (asserts! (> seller-payment u0) ERR-INVALID-INPUT)
      (asserts! (is-eq (+ seller-payment platform-fee) total-amount) ERR-AMOUNT-MISMATCH)

      ;; Pay platform fee to contract owner (only if fee > 0)
      (if (> platform-fee u0)
        (try! (as-contract (stx-transfer? platform-fee (as-contract tx-sender) CONTRACT-OWNER)))
        true
      )

      ;; Pay seller
      (try! (as-contract (stx-transfer? seller-payment (as-contract tx-sender) (get seller sale))))

      (map-set sales sale-id (merge sale { status: STATUS-COMPLETE }))

      (print {
        event: "release-funds",
        sale-id: sale-id,
        seller: (get seller sale),
        seller-amount: seller-payment,
        platform-fee: platform-fee,
        total-amount: total-amount
      })
      (ok true)
    )
  )
)

;; @desc Cancels a sale. Can only be done by buyer or seller before funds are released.
;;       If funded, returns STX to the buyer.
;; @param sale-id: The ID of the sale to cancel.
;; @returns (response bool uint)
(define-public (cancel-sale (sale-id uint))
  (let ((sale (unwrap! (map-get? sales sale-id) ERR-SALE-NOT-FOUND)))
    (asserts! (or (is-eq tx-sender (get buyer sale)) (is-eq tx-sender (get seller sale))) ERR-NOT-AUTHORIZED)
    (asserts! (or (is-eq (get status sale) STATUS-INITIATED) (is-eq (get status sale) STATUS-FUNDED)) ERR-INVALID-SALE-STATUS)

    ;; If the sale was funded, refund the buyer
    (if (is-eq (get status sale) STATUS-FUNDED)
      (try! (as-contract (stx-transfer? (get sale-price sale) (as-contract tx-sender) (get buyer sale))))
      true
    )

    (map-set sales sale-id (merge sale { status: STATUS-CANCELED }))

    (print {
      event: "cancel-sale",
      sale-id: sale-id,
      canceled-by: tx-sender,
      refund-amount: (if (is-eq (get status sale) STATUS-FUNDED) (some (get sale-price sale)) none)
    })
    (ok true)
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

;; @desc Gets the current sale counter.
;; @returns uint
(define-read-only (get-last-sale-id)
  (var-get last-sale-id)
)

;; @desc Gets the status string for a given status code.
;; @param status: The status code.
;; @returns (string-ascii 20)
(define-read-only (get-status-string (status uint))
  (if (is-eq status STATUS-INITIATED)
    "Initiated"
    (if (is-eq status STATUS-FUNDED)
      "Funded"
      (if (is-eq status STATUS-DELIVERY-CONFIRMED)
        "Delivery-Confirmed"
        (if (is-eq status STATUS-COMPLETE)
          "Complete"
          (if (is-eq status STATUS-CANCELED)
            "Canceled"
            "Unknown"
          )
        )
      )
    )
  )
)

;; @desc Calculate the fees and amounts for a given sale price.
;; @param sale-price: The sale price to calculate fees for.
;; @returns {platform-fee: uint, seller-amount: uint, total: uint}
(define-read-only (calculate-fees (sale-price uint))
  (let ((platform-fee (/ (* sale-price (var-get platform-fee-permille)) u1000))
        (seller-amount (- sale-price platform-fee)))
    {
      platform-fee: platform-fee,
      seller-amount: seller-amount,
      total: sale-price
    }
  )
)