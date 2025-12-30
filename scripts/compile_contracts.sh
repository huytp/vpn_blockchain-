#!/bin/bash
# Script to compile Solidity contracts using Hardhat

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BLOCKCHAIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "============================================================"
echo "🔨 Compiling Solidity Contracts"
echo "============================================================"
echo ""

cd "$BLOCKCHAIN_DIR"

# Check if package.json exists
if [ ! -f "package.json" ]; then
    echo "❌ package.json not found!"
    echo ""
    echo "💡 Please initialize Hardhat project first:"
    echo "   cd blockchain"
    echo "   npm init -y"
    echo "   npm install --save-dev hardhat @nomicfoundation/hardhat-toolbox"
    echo "   npx hardhat init"
    echo ""
    exit 1
fi

# Check if node_modules exists
if [ ! -d "node_modules" ]; then
    echo "📦 Installing dependencies..."
    npm install
    echo ""
fi

# Check if hardhat.config.js exists
if [ ! -f "hardhat.config.js" ] && [ ! -f "hardhat.config.ts" ]; then
    echo "⚠️  Hardhat config not found!"
    echo ""
    echo "💡 Creating basic hardhat.config.js..."
    cat > hardhat.config.js << 'EOF'
require("@nomicfoundation/hardhat-toolbox");

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    version: "0.8.20",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  paths: {
    sources: "./contracts",
    artifacts: "./artifacts",
  },
};
EOF
    echo "✅ Created hardhat.config.js"
    echo ""
fi

# Compile contracts
echo "🔨 Compiling contracts..."
npx hardhat compile

echo ""
echo "✅ Compilation complete!"
echo "📁 Artifacts saved to: $BLOCKCHAIN_DIR/artifacts"
echo ""

