#!/usr/bin/env node
/**
 * Script to generate a new Ethereum private key and address
 * Usage: node scripts/generate-key.js
 */

const { ethers } = require('ethers');

function generateNewKey() {
  console.log('='.repeat(60));
  console.log('🔑 Generating New Ethereum Key Pair');
  console.log('='.repeat(60));
  console.log('');

  // Generate new random wallet
  const wallet = ethers.Wallet.createRandom();

  // Get private key (without 0x prefix for .env file)
  const privateKey = wallet.privateKey.slice(2); // Remove '0x' prefix

  // Get address
  const address = wallet.address;

  console.log('✅ New key pair generated successfully!');
  console.log('');
  console.log('📋 Details:');
  console.log('─'.repeat(60));
  console.log(`Address:     ${address}`);
  console.log(`Private Key: ${privateKey}`);
  console.log('─'.repeat(60));
  console.log('');

  // Display for .env file
  console.log('📝 Add to your .env file:');
  console.log('─'.repeat(60));
  console.log(`PRIVATE_KEY=${privateKey}`);
  console.log('─'.repeat(60));
  console.log('');

  // Security warnings
  console.log('⚠️  SECURITY WARNINGS:');
  console.log('   1. Keep this private key SECRET and SAFE');
  console.log('   2. Never share or commit to git');
  console.log('   3. Store in a secure location');
  console.log('   4. Make sure you have backup');
  console.log('   5. This key controls the wallet - lose it = lose access');
  console.log('');

  // Testnet faucet info
  console.log('💡 Next steps:');
  console.log('   1. Add PRIVATE_KEY to your .env file');
  console.log('   2. Get testnet MATIC from faucet:');
  console.log('      https://faucet.polygon.technology/');
  console.log('   3. Use this address to receive testnet tokens');
  console.log('');

  return {
    address,
    privateKey
  };
}

// Run if called directly
if (require.main === module) {
  try {
    generateNewKey();
  } catch (error) {
    console.error('❌ Error generating key:', error.message);
    console.error('');
    console.error('💡 Make sure ethers is installed:');
    console.error('   npm install ethers');
    process.exit(1);
  }
}

module.exports = { generateNewKey };

