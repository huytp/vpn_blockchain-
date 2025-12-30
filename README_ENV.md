# Environment Variables Setup Guide

## Quick Setup

1. **Copy example file**:
```bash
cp .env.example .env
```

2. **Edit .env file** với các giá trị của bạn

## Required Variables

### 1. PRIVATE_KEY (Required)
Private key của wallet dùng để deploy contracts.

**⚠️ SECURITY WARNING:**
- Không bao giờ commit file `.env` vào git
- Private key phải có đủ ETH để trả gas fees
- Format: không có `0x` prefix

**Example:**
```
PRIVATE_KEY=abc123def456...
```

### 2. RPC URLs (Required - chọn ít nhất 1 network)

#### Fantom Testnet (Khuyến nghị)
```
FANTOM_TESTNET_RPC=https://rpc.testnet.fantom.network/
```

Hoặc dùng public RPC khác:
```
FANTOM_TESTNET_RPC=https://fantom-testnet.public.blastapi.io
```

#### Polygon Amoy Testnet (Mới - thay thế Mumbai)
```
POLYGON_AMOY_RPC=https://rpc-amoy.polygon.technology
```

Hoặc dùng Alchemy:
```
POLYGON_AMOY_RPC=https://polygon-amoy.g.alchemy.com/v2/YOUR_ALCHEMY_KEY
```

Hoặc dùng Tatum Gateway (lưu ý về custom headers):
```
TATUM_POLYGON_AMOY_URL=https://polygon-amoy.gateway.tatum.io/
TATUM_API_KEY=your_tatum_api_key_here
```
**Lưu ý:** Hardhat không hỗ trợ custom HTTP headers trực tiếp. Xem `scripts/tatum-provider.js` để sử dụng custom provider.

#### Polygon Mumbai Testnet (Deprecated - sử dụng Amoy thay thế)
```
POLYGON_MUMBAI_RPC=https://rpc-mumbai.maticvigil.com
```

#### Base Goerli Testnet
```
BASE_GOERLI_RPC=https://goerli.base.org
```

#### Arbitrum Goerli Testnet
```
ARBITRUM_GOERLI_RPC=https://goerli-rollup.arbitrum.io/rpc
```

### 3. Explorer API Keys (Optional - cho contract verification)

#### PolygonScan
1. Đăng ký tại https://polygonscan.com
2. Tạo API key tại https://polygonscan.com/apis
3. Thêm vào .env:
```
POLYGONSCAN_API_KEY=your_key_here
```

#### BaseScan
1. Đăng ký tại https://basescan.org
2. Tạo API key
3. Thêm vào .env:
```
BASESCAN_API_KEY=your_key_here
```

#### Arbiscan
1. Đăng ký tại https://arbiscan.io
2. Tạo API key
3. Thêm vào .env:
```
ARBISCAN_API_KEY=your_key_here
```

## Optional Variables

### DEFAULT_NETWORK
Network mặc định khi deploy:
```
DEFAULT_NETWORK=fantomTestnet
```
Hoặc:
```
DEFAULT_NETWORK=polygonMumbai
```

### GAS_PRICE & GAS_LIMIT
Custom gas settings (optional):
```
GAS_PRICE=20000000000
GAS_LIMIT=5000000
```

## After Deployment

Sau khi deploy, contract addresses sẽ được tự động lưu vào `.env`:
```
DEVPN_TOKEN_ADDRESS=0x...
REWARD_ADDRESS=0x...
NODE_REGISTRY_ADDRESS=0x...
VESTING_ADDRESS=0x...
```

## Example .env File

```bash
# Private Key
PRIVATE_KEY=your_64_char_hex_string_without_0x

# RPC URLs
FANTOM_TESTNET_RPC=https://rpc.testnet.fantom.network/
POLYGON_MUMBAI_RPC=https://polygon-mumbai.g.alchemy.com/v2/YOUR_KEY
BASE_GOERLI_RPC=https://goerli.base.org
ARBITRUM_GOERLI_RPC=https://goerli-rollup.arbitrum.io/rpc

# API Keys
FTMSCAN_API_KEY=your_ftmscan_key
POLYGONSCAN_API_KEY=your_polygonscan_key
BASESCAN_API_KEY=your_basescan_key
ARBISCAN_API_KEY=your_arbiscan_key

# Network
DEFAULT_NETWORK=fantomTestnet

# Contract Addresses (saved after deployment)
DEVPN_TOKEN_ADDRESS=
REWARD_ADDRESS=
NODE_REGISTRY_ADDRESS=
VESTING_ADDRESS=
```

## Security Best Practices

1. ✅ **Never commit .env to git** - đã có trong .gitignore
2. ✅ **Use separate wallet** - không dùng main wallet
3. ✅ **Get testnet tokens** - từ faucets:
   - Fantom Testnet: https://faucet.fantom.network/ (Khuyến nghị - nhanh và dễ)
   - Polygon Mumbai: https://faucet.polygon.technology
   - Base Goerli: https://www.coinbase.com/faucets/base-ethereum-goerli-faucet
   - Arbitrum Goerli: https://faucet.quicknode.com/arbitrum/goerli
4. ✅ **Rotate keys** - nếu private key bị lộ
5. ✅ **Use environment-specific files** - .env.local, .env.production

## Troubleshooting

### "Insufficient funds"
- Cần có ETH trong wallet để trả gas
- Get testnet ETH từ faucets

### "Invalid private key"
- Đảm bảo không có `0x` prefix
- Đảm bảo đủ 64 hex characters

### "Network error"
- Kiểm tra RPC URL có đúng không
- Thử RPC khác (Alchemy, Infura)

