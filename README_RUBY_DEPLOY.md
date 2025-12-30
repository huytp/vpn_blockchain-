# Hướng dẫn Deploy DEVPNToken bằng Ruby

Script này sử dụng Ruby để deploy contract DEVPNToken lên Polygon Amoy testnet thông qua Tatum RPC Gateway.

## Yêu cầu

1. **Ruby** (>= 2.7)
2. **Bundler** để quản lý gems
3. **Tatum API Key** - Đăng ký tại [Tatum Dashboard](https://dashboard.tatum.io/)
4. **Private Key** của wallet có đủ MATIC để trả gas fees
5. **Contract đã được compile** - Chạy `npm run compile` hoặc `npx hardhat compile` trước

## Cài đặt

### 1. Cài đặt dependencies

```bash
cd blockchain
bundle install
```

### 2. Cấu hình Environment Variables

Tạo hoặc cập nhật file `.env` trong thư mục `blockchain/`:

```bash
# Tatum RPC Configuration
TATUM_POLYGON_AMOY_URL=https://polygon-amoy.gateway.tatum.io/
TATUM_API_KEY=your_tatum_api_key_here

# Private Key (không có 0x prefix)
PRIVATE_KEY=your_64_char_hex_private_key
```

**⚠️ Lưu ý bảo mật:**
- Không bao giờ commit file `.env` vào git
- Private key phải có đủ MATIC để trả gas fees
- Format: không có `0x` prefix, 64 hex characters

### 3. Compile Contract (nếu chưa có)

```bash
npm install
npx hardhat compile
```

Script sẽ đọc bytecode từ `artifacts/contracts/DEVPNToken.sol/DEVPNToken.json`

## Sử dụng

### Deploy Contract

```bash
ruby scripts/deploy.rb
```

Script sẽ:
1. ✅ Load contract artifact (bytecode + ABI)
2. ✅ Kết nối với Tatum RPC Gateway
3. ✅ Kiểm tra balance và chain ID
4. ✅ Estimate gas
5. ✅ Tạo và sign transaction
6. ✅ Gửi transaction lên blockchain
7. ✅ Đợi confirmation
8. ✅ Lưu contract address vào `.env`

### Output mẫu

```
============================================================
🚀 Deploying DEVPNToken Contract
============================================================
Network: Polygon Amoy Testnet
Chain ID: 80002
Deployer Address: 0x...

💰 Balance: 1.5 MATIC
📝 Nonce: 0
⛽ Gas Price: 30000000000 wei (30.0 gwei)
⛽ Estimated Gas Limit: 2500000

✍️  Signing transaction...
📤 Sending transaction to Tatum RPC...

✅ Transaction sent!
📋 Transaction Hash: 0x...

⏳ Waiting for confirmation...
.....

🎉 Contract deployed successfully!
📍 Contract Address: 0x...
📋 Transaction Hash: 0x...
⛽ Gas Used: 2456789

💾 Saved contract address to .env file

============================================================
✨ Deployment hoàn tất!
============================================================
```

## Tatum RPC Gateway

Script sử dụng Tatum RPC Gateway với các tính năng:

- ✅ **Custom Headers**: Tự động thêm `x-api-key` header
- ✅ **Rate Limiting**: Tatum xử lý rate limiting
- ✅ **Reliability**: High availability infrastructure
- ✅ **Support**: Hỗ trợ đầy đủ JSON-RPC methods

### Tatum RPC Endpoints

- **Polygon Amoy Testnet**: `https://polygon-amoy.gateway.tatum.io/`
- **Polygon Mainnet**: `https://polygon-mainnet.gateway.tatum.io/`

Xem thêm: [Tatum Polygon RPC Documentation](https://docs.tatum.io/reference/rpc-polygon)

## Troubleshooting

### "TATUM_API_KEY không được tìm thấy"
- Kiểm tra file `.env` có tồn tại không
- Đảm bảo biến `TATUM_API_KEY` đã được set
- Lấy API key tại [Tatum Dashboard](https://dashboard.tatum.io/)

### "PRIVATE_KEY không được tìm thấy"
- Kiểm tra file `.env` có tồn tại không
- Đảm bảo private key không có `0x` prefix
- Private key phải có 64 hex characters

### "Insufficient funds"
- Cần có MATIC trong wallet để trả gas
- Lấy testnet MATIC từ [Polygon Faucet](https://faucet.polygon.technology/)

### "Contract artifact not found"
- Chạy `npx hardhat compile` để compile contracts
- Đảm bảo file `artifacts/contracts/DEVPNToken.sol/DEVPNToken.json` tồn tại

### "RPC Error: Too Many Requests"
- Tatum có rate limiting
- Đợi một chút rồi thử lại
- Hoặc upgrade Tatum plan để có higher limits

### "Transaction failed"
- Kiểm tra gas price có đủ không
- Kiểm tra balance có đủ không
- Xem transaction trên [PolygonScan Amoy](https://amoy.polygonscan.com/)

## So sánh với JavaScript/Node.js

| Tính năng | Ruby Script | JavaScript (Hardhat) |
|-----------|-------------|---------------------|
| Deploy Contract | ✅ | ✅ |
| Tatum RPC Support | ✅ | ✅ (với custom provider) |
| Contract Verification | ❌ | ✅ |
| Testing | ❌ | ✅ |
| Type Safety | ❌ | ✅ (TypeScript) |

**Khi nào dùng Ruby:**
- Khi muốn tích hợp với Ruby backend
- Khi cần deploy từ Ruby application
- Khi muốn tùy chỉnh deployment flow

**Khi nào dùng JavaScript:**
- Khi cần verify contract
- Khi cần test contracts
- Khi làm việc với Hardhat ecosystem

## Tài liệu tham khảo

- [Tatum RPC Documentation](https://docs.tatum.io/reference/rpc-polygon)
- [Eth Ruby Gem](https://github.com/q9f/eth.rb)
- [Polygon Amoy Explorer](https://amoy.polygonscan.com/)
- [Tatum Dashboard](https://dashboard.tatum.io/)

