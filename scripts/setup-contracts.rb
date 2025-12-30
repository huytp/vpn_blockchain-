#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'eth'
require 'net/http'
require 'uri'
require 'dotenv/load'

# Load environment variables
Dotenv.load

# Configuration
TATUM_RPC_URL = ENV['TATUM_POLYGON_AMOY_URL'] || 'https://polygon-amoy.gateway.tatum.io/'
TATUM_API_KEY = ENV['TATUM_API_KEY']
PRIVATE_KEY = ENV['PRIVATE_KEY']
POLYGON_AMOY_CHAIN_ID = 80_002

# Load contract addresses from .env
DEVPN_TOKEN_ADDRESS = ENV['DEVPN_TOKEN_ADDRESS']
REWARD_ADDRESS = ENV['REWARD_ADDRESS']
VESTING_ADDRESS = ENV['VESTING_ADDRESS']

# ============================================================================
# TatumRPCClient - Reuse from deploy.rb
# ============================================================================
class TatumRPCClient
  RATE_LIMIT_INTERVAL = 0.4
  MAX_RETRIES = 3
  BASE_RETRY_DELAY = 1.0

  def initialize(url, api_key)
    @url = URI(url)
    @api_key = api_key
    @last_request_time = 0
  end

  def eth_get_balance(address)
    call_with_retry('eth_getBalance', [address, 'latest'])
  end

  def eth_get_transaction_count(address)
    call_with_retry('eth_getTransactionCount', [address, 'latest'])
  end

  def eth_send_raw_transaction(signed_tx)
    call_with_retry('eth_sendRawTransaction', [signed_tx], 5)
  end

  def eth_get_transaction_receipt(tx_hash)
    call_with_retry('eth_getTransactionReceipt', [tx_hash])
  end

  def eth_chain_id
    call_with_retry('eth_chainId')
  end

  def eth_gas_price
    call_with_retry('eth_gasPrice')
  end

  def eth_estimate_gas(transaction)
    call_with_retry('eth_estimateGas', [transaction])
  end

  private

  def wait_for_rate_limit
    current_time = Time.now.to_f
    time_since_last = current_time - @last_request_time

    if time_since_last < RATE_LIMIT_INTERVAL
      sleep(RATE_LIMIT_INTERVAL - time_since_last)
    end

    @last_request_time = Time.now.to_f
  end

  def call_with_retry(method, params = [], max_retries = MAX_RETRIES)
    retries = 0

    begin
      return call_internal(method, params)
    rescue => e
      return handle_retry(e, method, params, retries, max_retries)
    end
  end

  def handle_retry(error, method, params, retries, max_retries)
    return raise error unless error.message.include?('429') || error.message.include?('Too Many Requests')

    retries += 1
    return handle_max_retries_exceeded(max_retries) if retries > max_retries

    delay = BASE_RETRY_DELAY * (2 ** (retries - 1)) + rand(0.5)
    puts "⏳ Rate limit hit, waiting #{delay.round(1)}s before retry (#{retries}/#{max_retries})..."
    sleep(delay)

    call_with_retry(method, params, max_retries)
  end

  def handle_max_retries_exceeded(max_retries)
    puts "\n❌ Rate limit exceeded after #{max_retries} retries"
    raise "Rate limit exceeded"
  end

  def call_internal(method, params = [])
    wait_for_rate_limit

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
      raise "HTTP Error: #{response.code} - #{response.message}"
    end

    result = JSON.parse(response.body)

    if result['error']
      raise "RPC Error: #{result['error']['message']} (Code: #{result['error']['code']})"
    end

    result['result']
  end
end

# ============================================================================
# ContractCaller - Handles contract function calls
# ============================================================================
class ContractCaller
  DEFAULT_GAS_LIMIT = 200_000
  DEFAULT_GAS_PRICE = 30_000_000_000
  WEI_TO_MATIC = 1_000_000_000_000_000_000.0

  def initialize(rpc_client, private_key, chain_id)
    @rpc = rpc_client
    @private_key = private_key
    @chain_id = chain_id
    @key = Eth::Key.new(priv: private_key)
  end

  # Encode function selector (first 4 bytes of keccak256(function signature))
  # Using hardcoded values calculated with ethers.js
  def encode_function_selector(function_signature)
    case function_signature
    when 'setRewardContract(address)'
      # keccak256("setRewardContract(address)")[0:4] = 0x51508f0a
      '51508f0a'
    when 'initializeDistribution(address)'
      # keccak256("initializeDistribution(address)")[0:4] = 0x9341aa4e
      '9341aa4e'
    else
      raise "Unknown function signature: #{function_signature}"
    end
  end

  # Encode address parameter (pad to 32 bytes)
  def encode_address(address)
    addr = address.to_s
    addr = addr[2..-1] if addr.start_with?('0x')
    addr.downcase.rjust(64, '0')
  end

  # Encode uint256 parameter (pad to 32 bytes hex)
  def encode_uint256(value)
    value.to_i.to_s(16).rjust(64, '0')
  end

  # Call contract function
  def call_function(contract_address, function_signature, params = [])
    puts "=" * 60
    puts "📞 Calling Contract Function"
    puts "=" * 60
    puts "Contract: #{contract_address}"
    puts "Function: #{function_signature}"
    puts "Params: #{params.inspect}"
    puts "=" * 60

    # Encode function call data
    selector = encode_function_selector(function_signature)
    encoded_params = encode_params(function_signature, params)
    data = "0x#{selector}#{encoded_params}"

    puts "\n🔍 Encoded function call:"
    puts "   Selector: 0x#{selector}"
    puts "   Params encoded: #{encoded_params.length / 2} bytes"
    puts "   Full data: #{data[0..100]}..."
    puts "   Data length: #{(data.length - 2) / 2} bytes"

    # Get transaction parameters
    nonce = get_nonce
    gas_price = get_gas_price
    gas_limit = estimate_gas(contract_address, data)

    # Build and send transaction
    transaction = build_transaction(contract_address, data, nonce, gas_price, gas_limit)
    signed_tx = sign_transaction(transaction)
    tx_hash = send_transaction(signed_tx)
    receipt = wait_for_receipt(tx_hash)

    process_result(receipt, tx_hash)
  end

  private

  def encode_params(function_signature, params)
    # Simple encoding - only supports address and uint256
    encoded = ''

    # Extract parameter types from signature
    # Example: "setRewardContract(address)" -> ["address"]
    match = function_signature.match(/\(([^)]*)\)/)
    return encoded if match.nil? || match[1].empty?

    param_types = match[1].split(',').map(&:strip)

    params.each_with_index do |param, index|
      param_type = param_types[index]

      case param_type
      when 'address'
        encoded += encode_address(param)
      when 'uint256'
        encoded += encode_uint256(param)
      else
        raise "Unsupported parameter type: #{param_type}"
      end
    end

    encoded
  end

  def get_nonce
    nonce_hex = @rpc.eth_get_transaction_count(@key.address)
    hex_to_int(nonce_hex)
  end

  def get_gas_price
    gas_price_hex = @rpc.eth_gas_price
    gas_price = hex_to_int(gas_price_hex)

    if gas_price == 0
      puts "⚠️  Could not get gas price, using default: 30 gwei"
      gas_price = DEFAULT_GAS_PRICE
    end

    gas_price
  end

  def estimate_gas(contract_address, data)
    transaction_data = {
      from: @key.address,
      to: contract_address,
      data: data
    }

    begin
      gas_limit_hex = @rpc.eth_estimate_gas(transaction_data)
      gas_limit = hex_to_int(gas_limit_hex)

      if gas_limit == 0
        raise "Gas limit estimation returned 0"
      end

      puts "⛽ Estimated Gas Limit: #{gas_limit}"
      gas_limit
    rescue => e
      puts "⚠️  Could not estimate gas: #{e.message}"
      puts "⛽ Using default Gas Limit: #{DEFAULT_GAS_LIMIT}"
      DEFAULT_GAS_LIMIT
    end
  end

  def build_transaction(contract_address, data, nonce, gas_price, gas_limit)
    Eth::Tx.new(
      chain_id: @chain_id,
      nonce: nonce,
      gas_price: gas_price,
      gas_limit: gas_limit,
      to: contract_address,
      data: data
    )
  end

  def sign_transaction(transaction)
    puts "\n✍️  Signing transaction..."
    transaction.sign(@key)

    signed_tx = transaction.hex
    signed_tx = "0x#{signed_tx}" unless signed_tx.start_with?('0x')
    signed_tx
  end

  def send_transaction(signed_tx)
    puts "📤 Sending transaction..."

    begin
      tx_hash = @rpc.eth_send_raw_transaction(signed_tx)

      if tx_hash.nil? || tx_hash.to_s.strip.empty?
        raise "Transaction hash is empty"
      end

      tx_hash = tx_hash.to_s.strip
      tx_hash = "0x#{tx_hash}" unless tx_hash.start_with?('0x')

      puts "\n✅ Transaction sent!"
      puts "📋 Transaction Hash: #{tx_hash}"
      puts "🔗 View on explorer: https://amoy.polygonscan.com/tx/#{tx_hash}"
      puts "\n⏳ Waiting for confirmation..."

      tx_hash
    rescue => e
      puts "\n❌ Failed to send transaction: #{e.message}"
      raise
    end
  end

  def wait_for_receipt(tx_hash, max_attempts = 40, delay = 3)
    attempts = 0

    while attempts < max_attempts
      begin
        receipt = @rpc.eth_get_transaction_receipt(tx_hash)
        if receipt && !receipt.empty?
          puts "\n✅ Transaction confirmed!"
          return receipt
        end
      rescue => e
        # Receipt not ready yet
      end

      print "."
      sleep delay
      attempts += 1
    end

    puts "\n⚠️  Timeout waiting for receipt"
    nil
  end

  def process_result(receipt, tx_hash)
    return nil if receipt.nil?

    status_int = hex_to_int(receipt['status'])

    if status_int == 1
      gas_used = hex_to_int(receipt['gasUsed'])
      puts "\n🎉 Function call successful!"
      puts "📋 Transaction Hash: #{tx_hash}"
      puts "⛽ Gas Used: #{gas_used}"
      puts "🔗 View transaction: https://amoy.polygonscan.com/tx/#{tx_hash}"
      { success: true, tx_hash: tx_hash, receipt: receipt }
    else
      puts "\n❌ Transaction failed!"
      puts "   Status: #{receipt['status']}"
      puts "   Transaction hash: #{tx_hash}"
      { success: false, tx_hash: tx_hash }
    end
  end

  def hex_to_int(hex_value)
    return 0 if hex_value.nil?
    hex_str = hex_value.to_s
    hex_str = hex_str.start_with?('0x') ? hex_str : "0x#{hex_str}"
    hex_str.to_i(16)
  rescue => e
    puts "⚠️  Error converting hex to int: #{e.message}"
    0
  end
end

# ============================================================================
# Main execution
# ============================================================================
begin
  puts "=" * 60
  puts "🔧 Setup Contracts - Initialize Distribution"
  puts "=" * 60
  puts ""

  # Validate environment
  unless TATUM_API_KEY
    raise "TATUM_API_KEY không được tìm thấy trong .env file"
  end

  unless PRIVATE_KEY
    raise "PRIVATE_KEY không được tìm thấy trong .env file"
  end

  # Validate contract addresses
  unless DEVPN_TOKEN_ADDRESS
    raise "DEVPN_TOKEN_ADDRESS không được tìm thấy trong .env file"
  end

  unless REWARD_ADDRESS
    raise "REWARD_ADDRESS không được tìm thấy trong .env file"
  end

  unless VESTING_ADDRESS
    raise "VESTING_ADDRESS không được tìm thấy trong .env file"
  end

  puts "📋 Contract Addresses:"
  puts "   DEVPN Token: #{DEVPN_TOKEN_ADDRESS}"
  puts "   Reward:      #{REWARD_ADDRESS}"
  puts "   Vesting:     #{VESTING_ADDRESS}"
  puts ""

  # Initialize
  rpc = TatumRPCClient.new(TATUM_RPC_URL, TATUM_API_KEY)
  chain_id_hex = rpc.eth_chain_id
  chain_id = chain_id_hex.to_s.to_i(16)

  puts "🔗 Connected to chain ID: #{chain_id}"
  puts ""

  caller = ContractCaller.new(rpc, PRIVATE_KEY, chain_id)

  # Step 1: Set Reward contract
  puts "\n" + "=" * 60
  puts "[1/2] Setting Reward Contract"
  puts "=" * 60
  result1 = caller.call_function(
    DEVPN_TOKEN_ADDRESS,
    'setRewardContract(address)',
    [REWARD_ADDRESS]
  )

  unless result1 && result1[:success]
    raise "Failed to set Reward contract"
  end

  sleep(2) # Wait to avoid rate limit

  # Step 2: Initialize distribution
  puts "\n" + "=" * 60
  puts "[2/2] Initializing Distribution"
  puts "=" * 60
  result2 = caller.call_function(
    DEVPN_TOKEN_ADDRESS,
    'initializeDistribution(address)',
    [VESTING_ADDRESS]
  )

  unless result2 && result2[:success]
    raise "Failed to initialize distribution"
  end

  puts "\n" + "=" * 60
  puts "✨ Setup hoàn tất!"
  puts "=" * 60
  puts "\n✅ All contracts configured successfully!"
  puts "   - Reward contract set"
  puts "   - Distribution initialized (100M tokens to Vesting)"
  puts "=" * 60

rescue => e
  puts "\n❌ Error: #{e.message}"
  puts e.backtrace.first(5).join("\n")
  exit 1
end

