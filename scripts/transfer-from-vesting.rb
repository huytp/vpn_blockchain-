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
POLYGON_AMOY_CHAIN_ID = 80_002

# Contract addresses
VESTING_ADDRESS = ENV['VESTING_ADDRESS']
DEVPN_TOKEN_ADDRESS = ENV['DEVPN_TOKEN_ADDRESS']

# Amount to transfer (100 DEVPN tokens)
AMOUNT = 100 * 10**18 # 100 tokens with 18 decimals

# ============================================================================
# Reuse RPC Client from setup-contracts.rb
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

  def eth_call(to, data)
    call_with_retry('eth_call', [{
      to: to,
      data: data
    }, 'latest'])
  end

  def get_token_balance(token_address, holder_address)
    # ERC20 balanceOf(address) selector = 0x70a08231
    balance_selector = '70a08231'
    # Encode address parameter (64 hex chars, padded)
    addr = holder_address.to_s
    addr = addr[2..-1] if addr.start_with?('0x')
    addr = addr.downcase.rjust(64, '0')
    data = "0x#{balance_selector}#{addr}"

    result = eth_call(token_address, data)
    return 0 if result.nil? || result == '0x'
    hex_to_int(result)
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
  DEFAULT_GAS_LIMIT = 300_000
  DEFAULT_GAS_PRICE = 30_000_000_000

  def initialize(rpc_client, private_key, chain_id)
    @rpc = rpc_client
    @private_key = private_key
    @chain_id = chain_id
    @key = Eth::Key.new(priv: private_key)
  end

  def address
    @key.address.to_s
  end

  def encode_function_selector(function_signature)
    case function_signature
    when 'createVestingSchedule(address,uint256,uint256,uint256,uint256)'
      # keccak256("createVestingSchedule(address,uint256,uint256,uint256,uint256)")[0:4] = 0x1bf0b08b
      '1bf0b08b'
    when 'release(address)'
      # keccak256("release(address)")[0:4] = 0x19165587
      '19165587'
    when 'transfer(address,uint256)'
      # keccak256("transfer(address,uint256)")[0:4] = 0xa9059cbb
      'a9059cbb'
    when 'vestingSchedules(address)'
      # This is a public mapping, we need to call it with the slot
      # For now, we'll use a workaround by checking totalAmount
      '00000000'
    when 'getReleasableAmount(address)'
      # keccak256("getReleasableAmount(address)")[0:4] = need to calculate
      # Let's use a simpler approach - call the view function
      '00000000'
    else
      raise "Unknown function signature: #{function_signature}"
    end
  end


  def encode_address(address)
    addr = address.to_s
    addr = addr[2..-1] if addr.start_with?('0x')
    addr.downcase.rjust(64, '0')
  end

  def encode_uint256(value)
    value.to_i.to_s(16).rjust(64, '0')
  end

  def encode_params(function_signature, params)
    encoded = ''

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

  def call_function(contract_address, function_signature, params = [])
    puts "=" * 60
    puts "📞 Calling Contract Function"
    puts "=" * 60
    puts "Contract: #{contract_address}"
    puts "Function: #{function_signature}"
    puts "Params: #{params.inspect}"
    puts "=" * 60

    selector = encode_function_selector(function_signature)
    encoded_params = encode_params(function_signature, params)
    data = "0x#{selector}#{encoded_params}"

    puts "\n🔍 Encoded function call:"
    puts "   Selector: 0x#{selector}"
    puts "   Data: #{data[0..100]}..."

    nonce = get_nonce
    gas_price = get_gas_price
    gas_limit = estimate_gas(contract_address, data)

    transaction = build_transaction(contract_address, data, nonce, gas_price, gas_limit)
    signed_tx = sign_transaction(transaction)
    tx_hash = send_transaction(signed_tx)
    receipt = wait_for_receipt(tx_hash)

    process_result(receipt, tx_hash)
  end

  private

  def get_nonce
    nonce_hex = @rpc.eth_get_transaction_count(@key.address)
    hex_to_int(nonce_hex)
  end

  def get_gas_price
    gas_price_hex = @rpc.eth_gas_price
    gas_price = hex_to_int(gas_price_hex)
    gas_price = DEFAULT_GAS_PRICE if gas_price == 0
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
      raise "Gas limit estimation returned 0" if gas_limit == 0
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
      { success: true, tx_hash: tx_hash, receipt: receipt }
    else
      puts "\n❌ Transaction failed!"
      puts "   Status: #{receipt['status']}"
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

# Add hex_to_int helper for TatumRPCClient
class TatumRPCClient
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
  puts "💰 Transfer DEVPN Tokens from Vesting"
  puts "=" * 60
  puts ""

  # Validate environment
  unless TATUM_API_KEY
    raise "TATUM_API_KEY không được tìm thấy trong .env file"
  end

  unless PRIVATE_KEY
    raise "PRIVATE_KEY không được tìm thấy trong .env file"
  end

  unless VESTING_ADDRESS
    raise "VESTING_ADDRESS không được tìm thấy trong .env file"
  end

  # Target address
  target_address = '0x28335Eb7C85CC39F16eCA146A283D82365A9bADA'

  puts "[1/2] Preparing transfer to target wallet..."
  puts "   Target Address: #{target_address}"
  puts "   Amount: 100 DEVPN (#{AMOUNT} wei)"
  puts ""

  # Step 2: Create vesting schedule for target address
  puts "[2/2] Creating vesting schedule and releasing tokens..."
  puts "   Beneficiary: #{target_address}"
  puts ""

  rpc = TatumRPCClient.new(TATUM_RPC_URL, TATUM_API_KEY)
  chain_id_hex = rpc.eth_chain_id
  chain_id = chain_id_hex.to_s.to_i(16)

  caller = ContractCaller.new(rpc, PRIVATE_KEY, chain_id)
  sender_address = caller.address

  # Check balances
  if DEVPN_TOKEN_ADDRESS
    puts "🔍 Checking token balances..."
    vesting_balance = rpc.get_token_balance(DEVPN_TOKEN_ADDRESS, VESTING_ADDRESS)
    vesting_balance_tokens = vesting_balance / 10**18
    puts "   Vesting Contract Balance: #{vesting_balance_tokens} DEVPN (#{vesting_balance} wei)"

    sender_balance = rpc.get_token_balance(DEVPN_TOKEN_ADDRESS, sender_address)
    sender_balance_tokens = sender_balance / 10**18
    puts "   Your Wallet Balance: #{sender_balance_tokens} DEVPN (#{sender_balance} wei)"
    puts ""

    # Transfer tokens to vesting contract if needed
    if vesting_balance < AMOUNT
      shortfall = AMOUNT - vesting_balance
      shortfall_tokens = shortfall / 10**18

      puts "⚠️  Vesting contract has insufficient tokens!"
      puts "   Required: #{AMOUNT / 10**18} DEVPN"
      puts "   Available: #{vesting_balance_tokens} DEVPN"
      puts "   Shortfall: #{shortfall_tokens} DEVPN"
      puts ""

      if sender_balance >= shortfall
        puts "💸 Transferring #{shortfall_tokens} DEVPN tokens to vesting contract..."
        puts "   From: #{sender_address}"
        puts "   To:   #{VESTING_ADDRESS}"
        puts ""

        transfer_result = caller.call_function(
          DEVPN_TOKEN_ADDRESS,
          'transfer(address,uint256)',
          [VESTING_ADDRESS, shortfall]
        )

        if transfer_result && transfer_result[:success]
          puts "   ✅ Tokens transferred successfully!"
          puts "\n⏳ Waiting for block confirmation..."
          sleep(5)

          # Verify new balance
          new_vesting_balance = rpc.get_token_balance(DEVPN_TOKEN_ADDRESS, VESTING_ADDRESS)
          new_vesting_balance_tokens = new_vesting_balance / 10**18
          puts "   📊 New Vesting Contract Balance: #{new_vesting_balance_tokens} DEVPN"
          puts ""
        else
          puts "   ❌ Failed to transfer tokens!"
          raise "Could not transfer tokens to vesting contract"
        end
      else
        puts "❌ ERROR: Your wallet doesn't have enough tokens!"
        puts "   Required: #{shortfall_tokens} DEVPN"
        puts "   Available: #{sender_balance_tokens} DEVPN"
        puts "   Shortfall: #{(shortfall - sender_balance) / 10**18} DEVPN"
        puts ""
        puts "💡 Please ensure your wallet has enough DEVPN tokens"
        raise "Insufficient token balance in sender wallet"
      end
    else
      puts "   ✅ Vesting contract has sufficient balance"
      puts ""
    end
  end

  # Try to create vesting schedule (will fail if already exists, that's OK)
  puts "📝 Attempting to create vesting schedule..."
  current_time = Time.now.to_i
  start_time = current_time - 3600 # Set to 1 hour ago to ensure immediate release
  duration = 1 # 1 second (minimum duration)
  cliff = 0 # No cliff period

  result1 = caller.call_function(
    VESTING_ADDRESS,
    'createVestingSchedule(address,uint256,uint256,uint256,uint256)',
    [target_address, AMOUNT, start_time, duration, cliff]
  )

  if result1 && result1[:success]
    puts "   ✅ Vesting schedule created successfully"
    puts "\n⏳ Waiting for block confirmation..."
    sleep(5) # Wait for block confirmation
  else
    # Check if it's because schedule already exists
    if result1 && result1[:tx_hash]
      puts "   ⚠️  Transaction failed - schedule might already exist"
      puts "   ℹ️  This is OK, we'll try to release existing schedule"
    else
      puts "   ⚠️  Could not create schedule (might already exist)"
    end
    puts "   ⏭️  Continuing to release tokens..."
  end
  puts ""

  # Step 3: Release tokens
  puts "💰 Releasing tokens to target wallet..."
  result2 = caller.call_function(
    VESTING_ADDRESS,
    'release(address)',
    [target_address]
  )

  unless result2 && result2[:success]
    puts "\n❌ Release transaction failed!"
    puts "\n⚠️  Possible reasons:"
    puts "   1. Vesting contract doesn't have enough tokens (balance: #{vesting_balance_tokens} DEVPN)"
    puts "   2. No tokens are releasable yet (check vesting schedule timing)"
    puts "   3. Vesting schedule was revoked"
    puts "   4. Vesting schedule doesn't exist"
    puts "\n🔗 Check failed transaction:"
    if result2 && result2[:tx_hash]
      puts "   https://amoy.polygonscan.com/tx/#{result2[:tx_hash]}"
    end
    puts "\n💡 Solutions:"
    puts "   1. Transfer tokens to vesting contract: #{VESTING_ADDRESS}"
    puts "   2. Check vesting schedule on explorer:"
    puts "      https://amoy.polygonscan.com/address/#{VESTING_ADDRESS}"
    puts "   3. Wait if tokens are still vesting"
    puts "   4. Create vesting schedule first if it doesn't exist"
    raise "Failed to release tokens"
  end

  puts "\n" + "=" * 60
  puts "✨ Transfer hoàn tất!"
  puts "=" * 60
  puts ""
  puts "✅ 100 DEVPN tokens đã được transfer thành công!"
  puts ""
  puts "📋 Transfer Details:"
  puts "   From: Vesting Contract (#{VESTING_ADDRESS})"
  puts "   To:   #{target_address}"
  puts "   Amount: 100 DEVPN tokens"
  puts ""
  puts "💡 Tokens đã được transfer vào ví:"
  puts "   #{target_address}"
  puts ""
  puts "🔗 Check balance on explorer:"
  puts "   https://amoy.polygonscan.com/address/#{target_address}"
  puts "=" * 60

rescue => e
  puts "\n❌ Error: #{e.message}"
  puts e.backtrace.first(5).join("\n")
  exit 1
end

