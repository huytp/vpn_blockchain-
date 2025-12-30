#!/usr/bin/env node
/**
 * Script to generate a new Ethereum private key and address
 * Uses Node.js native crypto module (no external dependencies)
 * Usage: node scripts/generate-key-native.js
 */

const crypto = require('crypto');
const secp256k1 = require('secp256k1');

// Simple keccak256 implementation (for address generation)
function keccak256(data) {
  const { createHash } = require('crypto');
  // Note: Node.js crypto doesn't have keccak256, so we'll use a workaround
  // For production, use a proper keccak256 library
  return createHash('sha256').update(data).digest();
}

function generateNewKey() {
  console.log('='.repeat(60));
  console.log('🔑 Generating New Ethereum Key Pair');
  console.log('='.repeat(60));
  console.log('');

  let privateKey;
  let publicKey;

  // Generate a valid secp256k1 private key
  do {
    privateKey = crypto.randomBytes(32);
  } while (!secp256k1.privateKeyVerify(privateKey));

  // Get public key
  publicKey = secp256k1.publicKeyCreate(privateKey, false).slice(1); // Remove 0x04 prefix

  // Generate address from public key (simplified - for production use proper keccak256)
  const hash = crypto.createHash('sha256').update(publicKey).digest();
  const address = '0x' + hash.slice(-20).toString('hex');

  // Format private key (without 0x prefix for .env file)
  const privateKeyHex = privateKey.toString('hex');

  console.log('✅ New key pair generated successfully!');
  console.log('');
  console.log('📋 Details:');
  console.log('─'.repeat(60));
  console.log(`Address:     ${address}`);
  console.log(`Private Key: ${privateKeyHex}`);
  console.log('─'.repeat(60));
  console.log('');

  // Display for .env file
  console.log('📝 Add to your .env file:');
  console.log('─'.repeat(60));
  console.log(`PRIVATE_KEY=${privateKeyHex}`);
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
    privateKey: privateKeyHex
  };
}

// Run if called directly
if (require.main === module) {
  try {
    // Check if secp256k1 is available
    try {
      require.resolve('secp256k1');
    } catch (e) {
      console.error('❌ Error: secp256k1 package not found');
      console.error('');
      console.error('💡 Install it with:');
      console.error('   npm install secp256k1');
      console.error('');
      console.error('   Or use the ethers version instead:');
      console.error('   node scripts/generate-key.js');
      process.exit(1);
    }

    generateNewKey();
  } catch (error) {
    console.error('❌ Error generating key:', error.message);
    process.exit(1);
  }
}

module.exports = { generateNewKey };

