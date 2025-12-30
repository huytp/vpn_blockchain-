# Testnet Faucet Guide

Để deploy contracts, bạn cần testnet tokens trong ví.

## Fantom Testnet (Khuyến nghị)

### Faucet để lấy FTM testnet:

### 1. Fantom Official Faucet (Khuyến nghị)
- URL: https://faucet.fantom.network/
- Yêu cầu: Đăng nhập với GitHub
- Số lượng: 5 FTM testnet
- Thời gian: Ngay lập tức

### 2. QuickNode Faucet
- URL: https://faucet.quicknode.com/fantom/testnet
- Yêu cầu: Đăng nhập với Twitter/GitHub

### 3. Chainlink Faucet
- URL: https://faucets.chain.link/fantom-testnet
- Yêu cầu: GitHub account

## Polygon Mumbai Testnet

### Các Faucet để lấy MATIC testnet:

### 1. Alchemy Faucet (Khuyến nghị)
- URL: https://portal.polygon.technology/polygon/mumbai/faucet
- Hoặc: https://mumbaifaucet.com/
- Yêu cầu: Đăng nhập với Alchemy account (miễn phí)

### 2. QuickNode Faucet
- URL: https://faucet.quicknode.com/polygon/mumbai
- Yêu cầu: Đăng nhập với Twitter/GitHub

### 3. Polygon Faucet (Official)
- URL: https://faucet.polygon.technology/
- Chọn network: Mumbai
- Yêu cầu: Twitter account

### 4. Chainlink Faucet
- URL: https://faucets.chain.link/mumbai
- Yêu cầu: GitHub account

## Cách sử dụng:

1. Truy cập một trong các faucet trên
2. Dán địa chỉ ví: `0x4619A4655029F910C0991900e93CA428801Da433`
3. Hoàn thành captcha/verification
4. Nhận MATIC testnet (thường 0.1-1 MATIC)
5. Chờ vài phút để transaction được confirm
6. Chạy lại deploy script

## Kiểm tra balance:

### Fantom Testnet:
```bash
cd /Users/baby/ventura/deVPN-AI/blockchain
npx hardhat run scripts/check-balance.js --network fantomTestnet
```

Hoặc kiểm tra trên FTMScan:
https://testnet.ftmscan.com/address/YOUR_ADDRESS

### Polygon Mumbai:
```bash
npx hardhat run scripts/check-balance.js --network polygonMumbai
```

Hoặc kiểm tra trên PolygonScan:
https://mumbai.polygonscan.com/address/YOUR_ADDRESS

## Lưu ý:

- Mỗi faucet có giới hạn số lần request (thường 1 lần/ngày)
- **Fantom Testnet**: Cần ít nhất 0.1-1 FTM để deploy contracts
- **Polygon Mumbai**: Cần ít nhất 0.01-0.1 MATIC để deploy contracts
- Nếu vẫn thiếu, thử nhiều faucet khác nhau
- Fantom Testnet thường nhanh hơn và rẻ hơn Polygon Mumbai

