# Auto Escrow Service Smart Contract

A trustless escrow system for peer-to-peer vehicle sales built on the Stacks blockchain. This smart contract manages the complete sale lifecycle from initial deposit to fund release, ensuring both buyers and sellers are protected throughout the transaction.

## 🚗 Overview

The Auto Escrow Service eliminates the need for trusted intermediaries in vehicle sales by providing:

- **Secure Fund Management**: STX tokens are held in escrow until delivery confirmation
- **Automated Release**: Funds are automatically distributed after buyer confirmation
- **Dispute Prevention**: Clear status tracking and cancellation mechanisms
- **Platform Fees**: Configurable fee structure for service sustainability
- **VIN Validation**: Ensures proper vehicle identification

## 📋 Features

- ✅ Trustless P2P vehicle sales
- ✅ Multi-stage transaction workflow
- ✅ Automatic fund distribution
- ✅ Comprehensive input validation
- ✅ Event logging for transparency
- ✅ Flexible cancellation system
- ✅ Admin fee management
- ✅ Zero-fee handling support

## 🔧 Technical Specifications

- **Language**: Clarity Smart Contract Language
- **Blockchain**: Stacks (STX)
- **Version**: 1.1.0
- **Clarinet Compatibility**: 0.31.1+
- **Minimum Sale Price**: 1 STX (1,000,000 micro-STX)
- **Maximum Sale Price**: 100,000 STX
- **Maximum Platform Fee**: 50% (500 permille)

## 🏗️ Contract Architecture

### Data Structures

```clarity
;; Sale Record
{
  seller: principal,
  buyer: principal, 
  sale-price: uint,
  vin: (string-ascii 17),
  status: uint
}
```

### Status Flow

```
Initiated (0) → Funded (1) → Delivery Confirmed (2) → Complete (3)
     ↓              ↓
  Canceled (4) ← Canceled (4)
```

## 🚀 Getting Started

### Prerequisites

- [Clarinet](https://github.com/hirosystems/clarinet) v0.31.1 or higher
- [Stacks CLI](https://docs.hiro.so/stacks-cli)
- Basic understanding of Clarity smart contracts

### Installation

1. Clone the repository:
```bash
git clone <repository-url>
cd auto-escrow-service
```

2. Initialize Clarinet project (if not already done):
```bash
clarinet new auto-escrow-service
cd auto-escrow-service
```

3. Add the contract to your `contracts/` directory

4. Verify the contract:
```bash
clarinet check
```

5. Run tests:
```bash
clarinet test
```

## 📖 Usage Guide

### For Sellers

1. **Initiate Sale**: Create a new sale agreement
```clarity
(contract-call? .auto-escrow-service initiate-sale buyer-principal sale-price-microSTX vin)
```

2. **Monitor Status**: Check sale progress
```clarity
(contract-call? .auto-escrow-service get-sale-details sale-id)
```

3. **Cancel if Needed**: Cancel before completion (if necessary)
```clarity
(contract-call? .auto-escrow-service cancel-sale sale-id)
```

### For Buyers

1. **Fund Escrow**: Deposit STX to secure the vehicle
```clarity
(contract-call? .auto-escrow-service fund-escrow sale-id)
```

2. **Confirm Delivery**: Confirm receipt of vehicle and title
```clarity
(contract-call? .auto-escrow-service confirm-delivery sale-id)
```

3. **Cancel if Needed**: Cancel and get refund (before confirmation)
```clarity
(contract-call? .auto-escrow-service cancel-sale sale-id)
```

### Fund Release

Anyone can trigger fund release after delivery confirmation:
```clarity
(contract-call? .auto-escrow-service release-funds sale-id)
```

## 🔍 API Reference

### Public Functions

#### Administrative Functions

##### `set-platform-fee`
Updates the platform fee percentage (contract owner only).
- **Parameters**: `new-fee-permille` (uint) - Fee in permille (1/1000)
- **Returns**: `(response bool uint)`
- **Access**: Contract owner only
- **Max Fee**: 50% (500 permille)

#### Core Escrow Functions

##### `initiate-sale`
Creates a new sale agreement.
- **Parameters**:
  - `buyer` (principal) - Buyer's wallet address
  - `sale-price` (uint) - Price in micro-STX
  - `vin` (string-ascii 17) - Vehicle identification number
- **Returns**: `(response uint uint)` - Sale ID
- **Validation**: 
  - VIN must be exactly 17 characters
  - Price between 1-100,000 STX
  - Buyer ≠ Seller

##### `fund-escrow`
Buyer deposits STX into escrow.
- **Parameters**: `sale-id` (uint)
- **Returns**: `(response bool uint)`
- **Access**: Buyer only
- **Prerequisite**: Sale status must be "Initiated"

##### `confirm-delivery`
Buyer confirms receipt of vehicle.
- **Parameters**: `sale-id` (uint)  
- **Returns**: `(response bool uint)`
- **Access**: Buyer only
- **Prerequisite**: Sale status must be "Funded"

##### `release-funds`
Releases funds to seller and platform.
- **Parameters**: `sale-id` (uint)
- **Returns**: `(response bool uint)`  
- **Access**: Anyone
- **Prerequisite**: Sale status must be "Delivery Confirmed"

##### `cancel-sale`
Cancels the sale and refunds buyer if funded.
- **Parameters**: `sale-id` (uint)
- **Returns**: `(response bool uint)`
- **Access**: Buyer or Seller
- **Limitation**: Only before completion

### Read-Only Functions

##### `get-sale-details`
Retrieves complete sale information.
- **Parameters**: `sale-id` (uint)
- **Returns**: `(optional {...})` - Sale details or none

##### `get-platform-fee`
Gets current platform fee percentage.
- **Returns**: `uint` - Fee in permille

##### `get-last-sale-id`
Gets the latest sale ID counter.
- **Returns**: `uint` - Last used sale ID

##### `get-status-string`
Converts status code to human-readable string.
- **Parameters**: `status` (uint)
- **Returns**: `(string-ascii 20)` - Status description

##### `calculate-fees`
Previews fee breakdown for a given price.
- **Parameters**: `sale-price` (uint)
- **Returns**: `{platform-fee: uint, seller-amount: uint, total: uint}`

## 📊 Transaction Flow Example

```
1. Seller creates sale: initiate-sale(buyer, 50000000, "1HGBH41JXMN109186")
   → Returns sale-id: 1
   → Status: Initiated

2. Buyer funds escrow: fund-escrow(1)
   → 50 STX locked in contract
   → Status: Funded

3. Vehicle delivery occurs (off-chain)

4. Buyer confirms: confirm-delivery(1)
   → Status: Delivery Confirmed

5. Anyone triggers: release-funds(1)
   → Seller receives: 49.5 STX (99%)
   → Platform receives: 0.5 STX (1%)
   → Status: Complete
```

## ⚠️ Security Considerations

### Input Validation
- All user inputs are validated before processing
- VIN format verification (17 characters)
- Price range validation (1-100,000 STX)
- Principal validation (no zero addresses)

### Access Controls
- Buyer-only functions: `fund-escrow`, `confirm-delivery`
- Seller/Buyer only: `cancel-sale`
- Owner-only: `set-platform-fee`
- Public: `release-funds` (by design)

### Error Handling
The contract includes comprehensive error codes:
- `ERR-NOT-AUTHORIZED` (101): Access denied
- `ERR-SALE-NOT-FOUND` (102): Invalid sale ID
- `ERR-INVALID-SALE-STATUS` (103): Wrong status for operation
- `ERR-BUYER-ONLY` (104): Function restricted to buyer
- `ERR-SELLER-ONLY` (105): Function restricted to seller
- `ERR-INSUFFICIENT-FUNDS` (106): Not enough STX balance
- `ERR-INVALID-INPUT` (111): Invalid input parameters
- `ERR-INVALID-VIN` (112): VIN format error
- `ERR-INVALID-FEE` (113): Fee percentage too high
- `ERR-ZERO-AMOUNT` (114): Invalid price amount

## 🧪 Testing

### Unit Tests
Create comprehensive tests covering:
- Happy path scenarios
- Error conditions  
- Edge cases
- Access control validation
- Input validation

### Example Test Structure
```clarity
;; Test successful sale flow
(define-public (test-complete-sale-flow)
  ;; Implementation
)

;; Test cancellation scenarios  
(define-public (test-cancellation-flows)
  ;; Implementation  
)

;; Test input validation
(define-public (test-input-validation)
  ;; Implementation
)
```

## 📈 Events & Logging

The contract emits detailed events for:
- `initiate-sale`: New sale creation
- `fund-escrow`: Escrow funding
- `confirm-delivery`: Delivery confirmation
- `release-funds`: Fund distribution
- `cancel-sale`: Sale cancellation
- `platform-fee-updated`: Fee changes

## 🔧 Configuration

### Default Settings
- **Platform Fee**: 1% (100 permille)
- **Minimum Sale**: 1 STX
- **Maximum Sale**: 100,000 STX  
- **Maximum Fee**: 50%

### Customization
Platform fees can be adjusted by the contract owner using `set-platform-fee`.

## 🚨 Limitations & Assumptions

- **Off-chain Coordination**: Vehicle inspection and title transfer occur off-chain
- **Dispute Resolution**: No built-in dispute resolution mechanism
- **STX Only**: Currently supports STX payments only
- **Single Owner**: Contract has a single owner for fee management
- **No Partial Refunds**: Cancellations result in full refunds only

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Write comprehensive tests
4. Ensure `clarinet check` passes without warnings
5. Submit a pull request

## 📄 License

[Specify your license here]

## 🆘 Support

For questions, issues, or feature requests:
- Create an issue on GitHub
- Contact the development team
- Check the documentation

## 📚 Additional Resources

- [Clarity Language Reference](https://docs.stacks.co/clarity)
- [Stacks Documentation](https://docs.stacks.co)
- [Clarinet Documentation](https://docs.hiro.so/clarinet)
- [Smart Contract Best Practices](https://docs.stacks.co/clarity/security)

---

**Version**: 1.1.0  
**Last Updated**: [Current Date]  
**Compatibility**: Clarinet 0.31.1+