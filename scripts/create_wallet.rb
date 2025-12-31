#!/usr/bin/env ruby
# frozen_string_literal: true

require 'eth'
require 'json'
require 'dotenv/load'

Dotenv.load

# Generate a new wallet
puts "=" * 60
puts "🔐 Creating New Wallet"
puts "=" * 60

# Generate new key pair
key = Eth::Key.new
private_key = key.private_hex
address = key.address.to_s

puts "\n✅ Wallet created successfully!"
puts "\n📋 Wallet Information:"
puts "   Address: #{address}"
puts "   Private Key: #{private_key}"
puts "\n⚠️  IMPORTANT: Save your private key securely!"
puts "   Never share your private key with anyone!"
puts "   Losing your private key means losing access to your wallet!"

# Save to file
wallet_file = File.join(__dir__, '..', 'wallet.json')
wallet_data = {
  address: address,
  private_key: private_key,
  created_at: Time.now.iso8601
}

File.write(wallet_file, JSON.pretty_generate(wallet_data))
puts "\n💾 Wallet saved to: #{wallet_file}"

# Optionally save to .env
env_file = File.join(__dir__, '..', '.env')
if File.exist?(env_file)
  env_content = File.read(env_file)

  # Update or add wallet address
  if env_content.include?('WALLET_ADDRESS=')
    env_content.gsub!(/WALLET_ADDRESS=.*/, "WALLET_ADDRESS=#{address}")
  else
    env_content += "\n# Generated Wallet\nWALLET_ADDRESS=#{address}\n"
  end

  if env_content.include?('WALLET_PRIVATE_KEY=')
    env_content.gsub!(/WALLET_PRIVATE_KEY=.*/, "WALLET_PRIVATE_KEY=#{private_key}")
  else
    env_content += "WALLET_PRIVATE_KEY=#{private_key}\n"
  end

  File.write(env_file, env_content)
  puts "💾 Wallet info also saved to .env file"
end

puts "\n" + "=" * 60
puts "✨ Done!"
puts "=" * 60

