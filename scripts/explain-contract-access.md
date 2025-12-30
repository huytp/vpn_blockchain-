# Hướng dẫn Truy cập và Kiểm soát Contracts

## ⚠️ Quan trọng: Contract Address vs Wallet Address

**`0xa1f2ad275ff2476849a099d7aa20cf1960785b4a`** là **Contract Address** (địa chỉ của smart contract), KHÔNG phải là wallet address.

### Sự khác biệt:

| Loại | Contract Address | Wallet Address |
|------|------------------|----------------|
| **Bản chất** | Smart contract code | Tài khoản cá nhân |
| **Private Key** | ❌ Không có | ✅ Có private key |
| **Kiểm soát** | Qua owner address | Qua private key |
| **Ví dụ** | `0xa1f2ad...` (Vesting) | `0x369c33...` (Deployer) |

## 🔑 Cách Kiểm soát Contracts

### 1. Owner Address

Contracts sử dụng **Ownable pattern** từ OpenZeppelin:
- **Owner** là address deploy contract (deployer address)
- Owner có quyền gọi các functions có modifier `onlyOwner`
- Owner có thể transfer ownership cho address khác

### 2. Deployer Address (Owner)

Khi bạn deploy contract bằng script Ruby:
- Script sử dụng `PRIVATE_KEY` từ `.env` file
- Address tương ứng với `PRIVATE_KEY` đó là **owner** của tất cả contracts
- Address này có quyền kiểm soát contracts

### 3. Kiểm tra Owner

Chạy script để kiểm tra owner của contracts:

```bash
ruby scripts/check-contract-owner.rb
```

Script sẽ hiển thị:
- Deployer address (từ PRIVATE_KEY)
- Owner của mỗi contract
- So sánh xem bạn có phải owner không

## 📋 Các Contracts và Quyền Truy cập

### DEVPNToken
- **Owner**: Deployer address
- **Functions cần owner**:
  - `setRewardContract(address)`
  - `setVestingContract(address)`
  - `initializeDistribution(address)`
  - `setRewardMinter(address, bool)`

### Reward Contract
- **Owner**: Deployer address (set trong constructor)
- **Functions cần owner**:
  - `commitEpoch(uint, bytes32)` - Commit merkle root
  - `transferOwnership(address)` - Transfer ownership

### Vesting Contract
- **Owner**: Deployer address (từ Ownable)
- **Functions cần owner**:
  - `createVestingSchedule(...)` - Tạo vesting schedule
  - `revoke(address)` - Revoke vesting
  - `transferOwnership(address)` - Transfer ownership

## 🛠️ Cách Sử dụng Quyền Owner

### Option 1: Sử dụng Script Ruby

Script `setup-contracts.rb` đã sử dụng PRIVATE_KEY của bạn để:
- Gọi `setRewardContract()` với quyền owner
- Gọi `initializeDistribution()` với quyền owner

```bash
ruby scripts/setup-contracts.rb
```

### Option 2: Sử dụng Web3 Tools

Với ethers.js hoặc web3.py:

```javascript
// JavaScript/Node.js
const { ethers } = require('ethers');
const provider = new ethers.JsonRpcProvider(RPC_URL);
const wallet = new ethers.Wallet(PRIVATE_KEY, provider);
const contract = new ethers.Contract(CONTRACT_ADDRESS, ABI, wallet);

// Gọi function với quyền owner
await contract.setRewardContract(rewardAddress);
```

### Option 3: Sử dụng Hardhat Console

```bash
npx hardhat console --network polygonAmoy
```

```javascript
const [owner] = await ethers.getSigners();
const contract = await ethers.getContractAt("Vesting", VESTING_ADDRESS, owner);
await contract.createVestingSchedule(...);
```

## 🔐 Bảo mật

### ⚠️ Lưu ý quan trọng:

1. **PRIVATE_KEY trong .env** là chìa khóa để control contracts
   - Giữ bí mật tuyệt đối
   - Không commit vào git
   - Có backup an toàn

2. **Owner Address** = Address từ PRIVATE_KEY
   - Mất PRIVATE_KEY = mất quyền kiểm soát
   - Không thể recover nếu mất private key

3. **Transfer Ownership** nếu cần:
   - Có thể transfer ownership cho multisig wallet
   - Hoặc cho address khác an toàn hơn

## 📝 Ví dụ: Kiểm tra Quyền Truy cập

```bash
# 1. Kiểm tra owner của contracts
ruby scripts/check-contract-owner.rb

# 2. Nếu bạn là owner, có thể gọi functions:
ruby scripts/setup-contracts.rb

# 3. Hoặc tạo script mới để gọi functions khác
```

## 💡 Tóm tắt

- ✅ **Bạn ĐÃ CÓ quyền truy cập** thông qua PRIVATE_KEY trong .env
- ✅ **Owner address** = Address từ PRIVATE_KEY của bạn
- ✅ **Có thể gọi functions** bằng script Ruby hoặc web3 tools
- ⚠️ **Giữ PRIVATE_KEY an toàn** - đây là chìa khóa duy nhất

