#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'eth'
require 'net/http'
require 'uri'
require 'dotenv/load'

Dotenv.load

# Configuration
TATUM_RPC_URL = ENV['TATUM_POLYGON_AMOY_URL'] || 'https://polygon-amoy.gateway.tatum.io/'
TATUM_API_KEY = ENV['TATUM_API_KEY']
PRIVATE_KEY = ENV['PRIVATE_KEY']

# Contract addresses from .env
DEVPN_TOKEN_ADDRESS = ENV['DEVPN_TOKEN_ADDRESS']
REWARD_ADDRESS = ENV['REWARD_ADDRESS']
VESTING_ADDRESS = ENV['VESTING_ADDRESS']
NODE_REGISTRY_ADDRESS = ENV['NODE_REGISTRY_ADDRESS']

# ============================================================================
# Simple RPC Client
# ============================================================================
class SimpleRPCClient
  def initialize(url, api_key)
    @url = URI(url)
    @api_key = api_key
  end

  def call(method, params = [])
    http = Net::HTTP.new(@url.host, @url.port)
    http.use_ssl = @url.scheme == 'https'

    path = @url.path.empty? ? '/' : @url.path
    request = Net::HTTP::Post.new(path)
    request['Content-Type'] = 'application/json'
    request['x-api-key'] = @api_key if @api_key

    payload = {
      jsonrpc: '2.0',
      method: method,
      params: params,
      id: 1
    }

    request.body = payload.to_json
    response = http.request(request)

    unless response.code.to_i == 200
      raise "HTTP Error: #{response.code}"
    end

    result = JSON.parse(response.body)

    if result['error']
      raise "RPC Error: #{result['error']['message']}"
    end

    result['result']
  end

  def eth_call(to, data)
    call('eth_call', [{
      to: to,
      data: data
    }, 'latest'])
  end
end

# ============================================================================
# Contract Info Checker
# ============================================================================
class ContractInfoChecker
  # Function selectors for common functions
  OWNER_SELECTOR = '8da5cb5b' # owner() - from Ownable contract
  TOKEN_SELECTOR = 'fc0c546a' # token() - returns token address

  def initialize(rpc_client)
    @rpc = rpc_client
  end

  def check_owner(contract_address)
    data = "0x#{OWNER_SELECTOR}"

    begin
      result = @rpc.eth_call(contract_address, data)
      return nil if result.nil? || result == '0x'

      # Decode address (last 20 bytes = 40 hex chars)
      address_hex = result[-40..-1]
      "0x#{address_hex}"
    rescue => e
      puts "⚠️  Error checking owner: #{e.message}"
      nil
    end
  end

  def check_token_address(contract_address)
    data = "0x#{TOKEN_SELECTOR}"

    begin
      result = @rpc.eth_call(contract_address, data)
      return nil if result.nil? || result == '0x'

      address_hex = result[-40..-1]
      "0x#{address_hex}"
    rescue => e
      puts "⚠️  Error checking token: #{e.message}"
      nil
    end
  end
end

# ============================================================================
# Main execution
# ============================================================================
begin
  puts "=" * 60
  puts "🔍 Checking Contract Ownership & Access"
  puts "=" * 60
  puts ""

  unless TATUM_API_KEY
    raise "TATUM_API_KEY không được tìm thấy trong .env file"
  end

  unless PRIVATE_KEY
    raise "PRIVATE_KEY không được tìm thấy trong .env file"
  end

  # Get deployer address
  key = Eth::Key.new(priv: PRIVATE_KEY)
  deployer_address = key.address

  puts "📋 Deployer Address (from PRIVATE_KEY):"
  puts "   #{deployer_address}"
  puts ""

  # Initialize RPC client
  rpc = SimpleRPCClient.new(TATUM_RPC_URL, TATUM_API_KEY)
  checker = ContractInfoChecker.new(rpc)

  contracts_to_check = []

  if DEVPN_TOKEN_ADDRESS
    contracts_to_check << {
      name: 'DEVPNToken',
      address: DEVPN_TOKEN_ADDRESS,
      has_owner: true
    }
  end

  if REWARD_ADDRESS
    contracts_to_check << {
      name: 'Reward',
      address: REWARD_ADDRESS,
      has_owner: true
    }
  end

  if VESTING_ADDRESS
    contracts_to_check << {
      name: 'Vesting',
      address: VESTING_ADDRESS,
      has_owner: true
    }
  end

  if contracts_to_check.empty?
    puts "⚠️  No contract addresses found in .env file"
    exit 1
  end

  puts "🔍 Checking contract ownership..."
  puts ""

  contracts_to_check.each do |contract|
    puts "─" * 60
    puts "Contract: #{contract[:name]}"
    puts "Address:  #{contract[:address]}"

    if contract[:has_owner]
      owner = checker.check_owner(contract[:address])
      if owner
        puts "Owner:    #{owner}"

        owner_str = owner.to_s.downcase
        deployer_str = deployer_address.to_s.downcase

        if owner_str == deployer_str
          puts "✅ You ARE the owner (matches deployer address)"
        else
          puts "⚠️  You are NOT the owner"
          puts "   To control this contract, you need the private key for: #{owner}"
        end
      else
        puts "⚠️  Could not determine owner"
      end
    end

    # Check token address for contracts that have it
    if ['Reward', 'Vesting'].include?(contract[:name])
      token_address = checker.check_token_address(contract[:address])
      if token_address
        puts "Token:    #{token_address}"
        if DEVPN_TOKEN_ADDRESS && token_address.to_s.downcase == DEVPN_TOKEN_ADDRESS.to_s.downcase
          puts "✅ Token address matches DEVPNToken"
        end
      end
    end

    puts ""
  end

  puts "=" * 60
  puts "💡 Important Information"
  puts "=" * 60
  puts ""
  puts "1. Contract Address vs Wallet Address:"
  puts "   - Contract addresses (0x...) are smart contracts, not wallets"
  puts "   - You cannot 'access' a contract address directly"
  puts "   - You control contracts through the owner address"
  puts ""
  puts "2. To Control Contracts:"
  puts "   - You need the PRIVATE_KEY of the owner address"
  puts "   - Your deployer address: #{deployer_address}"
  puts "   - Your PRIVATE_KEY is in .env file (keep it secret!)"
  puts ""
  puts "3. What You Can Do:"
  puts "   - Call functions as owner using your PRIVATE_KEY"
  puts "   - Use scripts like setup-contracts.rb"
  puts "   - Interact via web3 tools (ethers.js, web3.py, etc.)"
  puts ""
  puts "4. Security:"
  puts "   ⚠️  NEVER share your PRIVATE_KEY"
  puts "   ⚠️  NEVER commit .env file to git"
  puts "   ⚠️  Keep backups of your private key"
  puts ""

rescue => e
  puts "\n❌ Error: #{e.message}"
  puts e.backtrace.first(5).join("\n")
  exit 1
end

