const hre = require("hardhat");

// Rate limiting: 3 requests/second = 400ms delay between requests
// Using 500ms to be safe and account for network latency
const RATE_LIMIT_DELAY = 500; // milliseconds

// Helper function to add delay
const delay = (ms) => new Promise(resolve => setTimeout(resolve, ms));

// Helper function to make rate-limited RPC calls with retry
async function rateLimitedCall(fn, description = "RPC call", maxRetries = 5) {
  for (let attempt = 1; attempt <= maxRetries; attempt++) {
    try {
      const result = await fn();
      await delay(RATE_LIMIT_DELAY);
      return result;
    } catch (error) {
      const errorMessage = error.message || error.toString();
      const errorStack = error.stack || "";

      // Check for rate limit errors in message or stack
      if (errorMessage.includes("Too Many Requests") ||
          errorMessage.includes("429") ||
          errorStack.includes("Too Many Requests") ||
          errorMessage.includes("rate limit")) {
        const waitTime = Math.min(3000 * attempt, 15000); // Exponential backoff, max 15s
        console.log(`⏳ Rate limit hit during "${description}" (attempt ${attempt}/${maxRetries}), waiting ${waitTime}ms before retry...`);
        await delay(waitTime);
        if (attempt === maxRetries) {
          throw new Error(`Rate limit exceeded after ${maxRetries} attempts for "${description}". Please try again later.`);
        }
        continue;
      }
      throw error;
    }
  }
}

async function main() {
  console.log("🚀 Starting DeVPN Token deployment to Polygon Amoy...\n");
  console.log("⏱️  Rate limiting: 3 requests/second (500ms delay)\n");

  // Check environment variables
  if (!process.env.PRIVATE_KEY) {
    throw new Error("❌ PRIVATE_KEY not found in .env file");
  }
  if (!process.env.TATUM_POLYGON_AMOY_URL) {
    throw new Error("❌ TATUM_POLYGON_AMOY_URL not found in .env file");
  }
  if (process.env.TATUM_API_KEY) {
    console.log("✅ TATUM_API_KEY found in .env file");
  } else {
    console.log("⚠️  TATUM_API_KEY not found - using without API key (may have rate limits)");
  }

  // Get the deployer account
  const [deployer] = await hre.ethers.getSigners();
  console.log("📝 Deploying contracts with account:", deployer.address);

  // Check balance with rate limiting
  const balance = await rateLimitedCall(
    () => hre.ethers.provider.getBalance(deployer.address),
    "Get balance"
  );
  console.log("💰 Account balance:", hre.ethers.formatEther(balance), "MATIC\n");

  if (balance === 0n) {
    console.warn("⚠️  Warning: Account balance is 0. Make sure you have MATIC for gas fees.");
  }

  // Deploy DEVPNToken
  console.log("⏳ Deploying DEVPNToken...");

  // Add delay before getting contract factory
  await delay(RATE_LIMIT_DELAY);
  const DEVPNToken = await hre.ethers.getContractFactory("DEVPNToken");

  // Add delay before deploy to ensure rate limit compliance
  await delay(RATE_LIMIT_DELAY);

  // Wrap deploy in rate limiting - deploy() makes multiple RPC calls internally
  // (getNonce, estimateGas, sendTransaction, etc.)
  console.log("   Sending deployment transaction...");
  const devpnToken = await rateLimitedCall(
    async () => {
      const contract = await DEVPNToken.deploy();
      return contract;
    },
    "Deploy contract"
  );

  await rateLimitedCall(
    () => devpnToken.waitForDeployment(),
    "Wait for deployment"
  );
  const tokenAddress = await rateLimitedCall(
    () => devpnToken.getAddress(),
    "Get contract address"
  );

  console.log("✅ DEVPNToken deployed to:", tokenAddress);
  console.log("📋 Transaction hash:", devpnToken.deploymentTransaction()?.hash);

  // Wait for a few block confirmations
  console.log("\n⏳ Waiting for block confirmations...");
  if (devpnToken.deploymentTransaction()) {
    await rateLimitedCall(
      () => devpnToken.deploymentTransaction().wait(3),
      "Wait for confirmations"
    );
  }
  console.log("✅ Transaction confirmed!\n");

  // Get token details with rate limiting
  const name = await rateLimitedCall(
    () => devpnToken.name(),
    "Get token name"
  );
  const symbol = await rateLimitedCall(
    () => devpnToken.symbol(),
    "Get token symbol"
  );
  const decimals = await rateLimitedCall(
    () => devpnToken.decimals(),
    "Get token decimals"
  );
  const totalSupply = await rateLimitedCall(
    () => devpnToken.totalSupply(),
    "Get total supply"
  );

  console.log("📊 Token Information:");
  console.log("   Name:", name);
  console.log("   Symbol:", symbol);
  console.log("   Decimals:", decimals.toString());
  console.log("   Total Supply:", hre.ethers.formatEther(totalSupply), symbol);
  console.log("   Total Supply (raw):", totalSupply.toString());

  // Check deployer balance
  const deployerBalance = await rateLimitedCall(
    () => devpnToken.balanceOf(deployer.address),
    "Get deployer balance"
  );
  console.log("\n👤 Deployer Balance:");
  console.log("   Address:", deployer.address);
  console.log("   Balance:", hre.ethers.formatEther(deployerBalance), symbol);

  // Get network info
  const network = await rateLimitedCall(
    () => hre.ethers.provider.getNetwork(),
    "Get network info"
  );

  console.log("\n✨ Deployment completed successfully!");
  console.log("\n💡 Save this information:");
  console.log("   Contract Address:", tokenAddress);
  console.log("   Network: Polygon Amoy Testnet");
  console.log("   Explorer: https://amoy.polygonscan.com/address/" + tokenAddress);
  console.log("   Chain ID:", network.chainId);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("❌ Deployment failed:");
    console.error(error);
    process.exit(1);
  });

