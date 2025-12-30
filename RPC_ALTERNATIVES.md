# Polygon Amoy RPC Alternatives

Nếu gặp lỗi "Too Many Requests", hãy thử các RPC endpoints sau:

## Free Public RPCs

### 1. Polygon Official
```
POLYGON_AMOY_RPC=https://rpc-amoy.polygon.technology
```

### 2. Alchemy (Cần API key - miễn phí)
1. Đăng ký tại: https://www.alchemy.com/
2. Tạo app cho Polygon Amoy
3. Copy RPC URL:
```
POLYGON_AMOY_RPC=https://polygon-amoy.g.alchemy.com/v2/YOUR_API_KEY
```

### 3. Infura (Cần API key - miễn phí)
1. Đăng ký tại: https://www.infura.io/
2. Tạo project cho Polygon Amoy
3. Copy RPC URL:
```
POLYGON_AMOY_RPC=https://polygon-amoy.infura.io/v3/YOUR_PROJECT_ID
```

### 4. QuickNode (Cần API key - miễn phí)
1. Đăng ký tại: https://www.quicknode.com/
2. Tạo endpoint cho Polygon Amoy
3. Copy RPC URL từ dashboard

### 5. Tatum Gateway (Cần API key - miễn phí)
1. Đăng ký tại: https://tatum.io/
2. Tạo API key từ dashboard
3. Sử dụng Tatum Gateway URL:
```bash
TATUM_POLYGON_AMOY_URL=https://polygon-amoy.gateway.tatum.io/
TATUM_API_KEY=your_tatum_api_key_here
```

**Lưu ý:**
- Hardhat không hỗ trợ custom HTTP headers trực tiếp trong network config
- Nếu cần sử dụng Tatum Gateway với API key, có thể:
  1. Sử dụng network `polygonAmoyTatum` (không có custom headers - có thể không hoạt động)
  2. Hoặc sử dụng custom provider helper trong scripts (xem `scripts/tatum-provider.js`)
  3. Hoặc sử dụng các RPC provider khác (Alchemy, Infura) thay thế

### 6. Public RPC (Không cần API key)
```
POLYGON_AMOY_RPC=https://polygon-amoy.public.blastapi.io
```

## Giải pháp tạm thời

Nếu vẫn gặp rate limit, script deploy đã được cập nhật với:
- ✅ **Retry logic** với exponential backoff (tự động retry khi gặp rate limit)
- ✅ **Delay giữa transactions** (2-3 giây) để tránh spam RPC
- ✅ **Timeout tăng lên 60s** trong hardhat.config.js

## Khuyến nghị

**Tốt nhất:** Dùng Alchemy hoặc Infura với API key (miễn phí, rate limit cao hơn)

**Nhanh nhất:** Dùng Fantom Testnet (không bị rate limit nhiều):
```bash
npx hardhat run scripts/deploy.js --network fantomTestnet
```

## Cập nhật .env

Thêm vào file `.env`:
```bash
# Chọn một trong các options:

# Option 1: Polygon Official RPC
POLYGON_AMOY_RPC=https://rpc-amoy.polygon.technology

# Option 2: Alchemy (cần API key)
POLYGON_AMOY_RPC=https://polygon-amoy.g.alchemy.com/v2/YOUR_KEY

# Option 3: Infura (cần API key)
POLYGON_AMOY_RPC=https://polygon-amoy.infura.io/v3/YOUR_PROJECT_ID

# Option 4: Tatum Gateway (cần API key - lưu ý về custom headers)
TATUM_POLYGON_AMOY_URL=https://polygon-amoy.gateway.tatum.io/
TATUM_API_KEY=your_tatum_api_key_here
# Lưu ý: Hardhat không hỗ trợ custom headers trực tiếp, xem scripts/tatum-provider.js

# Option 5: Public RPC (không cần API key)
POLYGON_AMOY_RPC=https://polygon-amoy.public.blastapi.io
```

