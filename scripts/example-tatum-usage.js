/**
 * Ví dụ sử dụng Tatum Gateway với custom provider
 *
 * Chạy script này:
 * npx hardhat run scripts/example-tatum-usage.js
 */

require("dotenv").config();
const { getTatumProvider } = require("./tatum-provider");

async function main() {
  // Kiểm tra API key
  if (!process.env.TATUM_API_KEY) {
    console.error("❌ TATUM_API_KEY không được tìm thấy trong .env");
    console.log("Vui lòng thêm vào .env:");
    console.log("TATUM_API_KEY=your_tatum_api_key_here");
    process.exit(1);
  }

  const tatumUrl = process.env.TATUM_POLYGON_AMOY_URL || "https://polygon-amoy.gateway.tatum.io/";

  console.log("🔗 Đang kết nối với Tatum Gateway...");
  console.log(`URL: ${tatumUrl}`);

  // Tạo custom provider với API key
  const provider = getTatumProvider(tatumUrl, process.env.TATUM_API_KEY);

  try {
    // Test connection bằng cách lấy block number
    console.log("📡 Đang lấy block number...");
    const blockNumber = await provider.getBlockNumber();
    console.log(`✅ Kết nối thành công! Block number: ${blockNumber}`);

    // Test khác: lấy network info
    const network = await provider.getNetwork();
    console.log(`🌐 Network: ${network.name} (Chain ID: ${network.chainId})`);

    // Test: lấy gas price
    const feeData = await provider.getFeeData();
    console.log(`⛽ Gas Price: ${feeData.gasPrice?.toString()} wei`);

    console.log("\n✅ Tất cả tests đều thành công!");
    console.log("\n💡 Bạn có thể sử dụng provider này trong các script khác:");
    console.log("   const { getTatumProvider } = require('./scripts/tatum-provider');");
    console.log("   const provider = getTatumProvider(url, apiKey);");
    console.log("   // Sử dụng provider thay vì hre.ethers.provider");

  } catch (error) {
    console.error("❌ Lỗi khi kết nối:", error.message);
    if (error.message.includes("401") || error.message.includes("Unauthorized")) {
      console.error("💡 Có thể API key không đúng hoặc đã hết hạn");
    }
    process.exit(1);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

