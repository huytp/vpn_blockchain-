#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'eth'
require 'net/http'
require 'uri'
require 'digest/keccak'
require 'dotenv/load'

# Load environment variables
Dotenv.load

# ============================================================================
# TatumRPCClient - Handles RPC communication with rate limiting
# ============================================================================
class TatumRPCClient
  RATE_LIMIT_INTERVAL = 0.4 # 400ms between requests (3 req/s limit)
  MAX_RETRIES = 3
  BASE_RETRY_DELAY = 1.0

  def initialize(url, api_key)
    @url = URI(url)
    @api_key = api_key
    @last_request_time = 0
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

  def eth_gas_price
    call_with_retry('eth_gasPrice')
  end

  def eth_estimate_gas(transaction)
    call_with_retry('eth_estimateGas', [transaction])
  end

  def eth_call(to, data, block = 'latest')
    call_with_retry('eth_call', [{
      to: to,
      data: data
    }, block])
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
    return raise error unless rate_limit_error?(error)

    retries += 1
    return handle_max_retries_exceeded(max_retries) if retries > max_retries

    delay = calculate_retry_delay(retries)
    puts "⏳ Rate limit hit, waiting #{delay.round(1)}s before retry (#{retries}/#{max_retries})..."
    sleep(delay)

    call_with_retry(method, params, max_retries)
  end

  def rate_limit_error?(error)
    error.message.include?('429') || error.message.include?('Too Many Requests')
  end

  def calculate_retry_delay(retries)
    BASE_RETRY_DELAY * (2 ** (retries - 1)) + rand(0.5)
  end

  def handle_max_retries_exceeded(max_retries)
    puts "\n❌ Rate limit exceeded after #{max_retries} retries"
    raise "Rate limit exceeded"
  end

  def call_internal(method, params = [])
    wait_for_rate_limit

    http = Net::HTTP.new(@url.host, @url.port)
    http.use_ssl = @url.scheme == 'https'

    request = build_request(method, params)
    response = http.request(request)

    handle_http_response(response, method)
  end

  def build_request(method, params)
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
    request
  end

  def handle_http_response(response, method)
    check_http_status(response)
    result = parse_json_response(response.body)
    check_rpc_errors(result)
    result['result']
  end

  def check_http_status(response)
    return if response.code.to_i == 200

    error_body = response.body[0..500] rescue "Unable to read body"

    if response.code.to_i == 429
      raise build_rate_limit_error(response.body)
    end

    raise "HTTP Error: #{response.code} - #{response.message}\nBody: #{error_body}"
  end

  def build_rate_limit_error(body)
    parsed_body = begin
      JSON.parse(body)
    rescue
      {}
    end

    error_msg = "Rate Limit Exceeded (429)"
    error_msg += ": #{parsed_body['message']}" if parsed_body['message']
    error_msg
  end

  def parse_json_response(body)
    JSON.parse(body)
  rescue JSON::ParserError => e
    raise "Failed to parse JSON response: #{e.message}\nResponse body: #{body[0..500]}"
  end

  def check_rpc_errors(result)
    return unless result['error']

    error_msg = "RPC Error: #{result['error']['message']} (Code: #{result['error']['code']})"
    error_msg += "\n   Data: #{result['error']['data']}" if result['error']['data']
    raise error_msg
  end
end

# Configuration
CHAIN_ID = 80_002
TATUM_RPC_URL = ENV['TATUM_POLYGON_AMOY_URL'] || 'https://polygon-amoy.gateway.tatum.io/'
TATUM_API_KEY = ENV['TATUM_API_KEY']
TOKEN_ADDRESS = ENV['MY_WALLET_ADDRESS']

EXPLORER_BASE = 'https://amoy.polygonscan.com'
PRIVATE_KEY = ENV['PRIVATE_KEY']
# Amount to transfer: 200 DEVPN (with 18 decimals)
TRANSFER_AMOUNT = 200 * 10**18

def hex_to_int(hex_value)
  return 0 if hex_value.nil?
  hex_str = hex_value.to_s
  hex_str = hex_str.start_with?('0x') ? hex_str : "0x#{hex_str}"
  hex_str.to_i(16)
rescue => e
  puts "⚠️  Error converting hex to int: #{e.message}, value: #{hex_value.inspect}"
  0
end

def keccak256(data)
  Digest::Keccak.hexdigest(data, 256)
end

def encode_address(address)
  addr = address.to_s
  addr = addr[2..-1] if addr.start_with?('0x')
  addr.downcase.rjust(64, '0')
end

def encode_uint256(value)
  value.to_i.to_s(16).rjust(64, '0')
end

def get_token_balance(rpc, token_address, wallet_address)
  # Function: balanceOf(address)
  function_sig = "balanceOf(address)"
  hash = keccak256(function_sig)
  selector = "0x#{hash[0..7]}"

  encoded_addr = encode_address(wallet_address)
  function_data = "#{selector}#{encoded_addr}"

  result = rpc.eth_call(token_address, function_data)
  hex_to_int(result)
end

def transfer_tokens(rpc, from_key, to_address, amount)
  puts "\n" + "=" * 60
  puts "💸 Transferring DEVPN Tokens"
  puts "=" * 60
  puts "From: #{from_key.address}"
  puts "To: #{to_address}"
  puts "Amount: #{amount / 10**18} DEVPN"
  puts "=" * 60

  # Function selector: transfer(address,uint256)
  function_sig = "transfer(address,uint256)"
  hash = keccak256(function_sig)
  selector = "0x#{hash[0..7]}"

  # Encode parameters
  encoded_address = encode_address(to_address)
  encoded_amount = encode_uint256(amount)

  function_data = "#{selector}#{encoded_address}#{encoded_amount}"

  # Get transaction parameters
  puts "\n📝 Getting transaction parameters..."
  nonce_hex = rpc.eth_get_transaction_count(from_key.address.to_s)
  nonce = hex_to_int(nonce_hex)
  puts "   Nonce: #{nonce}"

  gas_price_hex = rpc.eth_gas_price
  gas_price = hex_to_int(gas_price_hex)
  gas_price = 30_000_000_000 if gas_price == 0
  puts "   Gas Price: #{gas_price} wei (#{gas_price / 1_000_000_000.0} gwei)"

  # Estimate gas
  puts "   Estimating gas..."
  begin
    gas_limit_hex = rpc.eth_estimate_gas({
      from: from_key.address.to_s,
      to: TOKEN_ADDRESS,
      data: function_data
    })
    gas_limit = hex_to_int(gas_limit_hex)
    gas_limit = (gas_limit * 1.2).to_i
    puts "   Estimated Gas Limit: #{gas_limit}"
  rescue => e
    puts "   ⚠️  Gas estimation failed: #{e.message}, using default"
    gas_limit = 100_000
  end

  # Check balance
  puts "\n💰 Checking balances..."
  from_balance = get_token_balance(rpc, TOKEN_ADDRESS, from_key.address.to_s)
  from_balance_formatted = from_balance.to_f / 10**18
  puts "   From balance: #{from_balance_formatted} DEVPN"

  if from_balance < amount
    raise "❌ Insufficient balance! Need #{amount / 10**18} DEVPN, but only have #{from_balance_formatted} DEVPN"
  end

  # Build transaction
  puts "\n📝 Building transaction..."
  transaction = Eth::Tx.new(
    chain_id: CHAIN_ID,
    nonce: nonce,
    gas_price: gas_price,
    gas_limit: gas_limit,
    to: TOKEN_ADDRESS,
    data: function_data[2..-1] # Remove 0x prefix
  )

  # Sign transaction
  puts "✍️  Signing transaction..."
  transaction.sign(from_key)
  signed_tx = transaction.hex
  signed_tx = "0x#{signed_tx}" unless signed_tx.start_with?('0x')

  # Send transaction
  puts "📤 Sending transaction..."
  tx_hash = rpc.eth_send_raw_transaction(signed_tx)
  puts "\n✅ Transaction sent!"
  puts "📋 Transaction Hash: #{tx_hash}"
  puts "🔗 View on explorer: #{EXPLORER_BASE}/tx/#{tx_hash}"

  # Wait for receipt
  puts "\n⏳ Waiting for confirmation..."
  receipt = wait_for_receipt(rpc, tx_hash, 120)

  if receipt && receipt['status'] == '0x1'
    puts "\n✅ Transfer successful!"
    puts "📊 Block: #{receipt['blockNumber']}"
    puts "⛽ Gas used: #{hex_to_int(receipt['gasUsed'])}"

    # Check final balances
    puts "\n💰 Final balances:"
    from_balance_after = get_token_balance(rpc, TOKEN_ADDRESS, from_key.address.to_s)
    to_balance_after = get_token_balance(rpc, TOKEN_ADDRESS, to_address)

    puts "   From: #{from_balance_after.to_f / 10**18} DEVPN"
    puts "   To: #{to_balance_after.to_f / 10**18} DEVPN"

    return { success: true, tx_hash: tx_hash, receipt: receipt }
  else
    puts "\n❌ Transfer failed!"
    if receipt
      puts "   Status: #{receipt['status']}"
    end
    return { success: false, tx_hash: tx_hash }
  end
rescue => e
  puts "\n❌ Error: #{e.message}"
  puts e.backtrace.first(5)
  { success: false, error: e.message }
end

def wait_for_receipt(rpc, tx_hash, max_wait = 120)
  start_time = Time.now
  while Time.now - start_time < max_wait
    sleep 2
    receipt = rpc.eth_get_transaction_receipt(tx_hash)
    return receipt if receipt && receipt['blockNumber']
  end
  puts "⚠️  Transaction receipt not found after #{max_wait}s"
  nil
end

# Main execution
begin
  puts "=" * 60
  puts "🚀 DEVPN Token Transfer Script"
  puts "=" * 60
  puts "📡 Network: Polygon Amoy Testnet"
  puts "=" * 60

  # Validate environment
  unless TATUM_API_KEY
    raise "❌ TATUM_API_KEY not found in .env file"
  end

  unless TOKEN_ADDRESS
    raise "❌ MY_WALLET_ADDRESS not found in .env file"
  end

  unless PRIVATE_KEY
    raise "❌ PRIVATE_KEY not found in .env file (needed for sender wallet)"
  end

  # Get recipient address
  recipient_address = ENV['WALLET_ADDRESS']

  # Try to load from wallet.json if not in .env
  unless recipient_address
    wallet_file = File.join(__dir__, '..', 'wallet.json')
    if File.exist?(wallet_file)
      wallet_data = JSON.parse(File.read(wallet_file))
      recipient_address = wallet_data['address']
      puts "✅ Loaded recipient address from wallet.json"
    end
  end

  unless recipient_address
    raise "❌ WALLET_ADDRESS not found. Please run 'ruby scripts/create_wallet.rb' first or set WALLET_ADDRESS in .env"
  end

  puts "\n📋 Configuration:"
  puts "   Token Address: #{TOKEN_ADDRESS}"
  puts "   Recipient Address: #{recipient_address}"
  puts "   Amount: #{TRANSFER_AMOUNT / 10**18} DEVPN"

  # Initialize RPC client
  rpc = TatumRPCClient.new(TATUM_RPC_URL, TATUM_API_KEY)

  # Initialize sender key
  private_key = PRIVATE_KEY.to_s
  private_key = private_key[2..-1] if private_key.start_with?('0x')
  sender_key = Eth::Key.new(priv: private_key)

  puts "\n📝 Sender Address: #{sender_key.address}"

  # Transfer tokens
  result = transfer_tokens(rpc, sender_key, recipient_address, TRANSFER_AMOUNT)

  if result[:success]
    puts "\n" + "=" * 60
    puts "✨ Transfer completed successfully!"
    puts "=" * 60
    puts "\n💡 Transaction details saved above"
  else
    puts "\n" + "=" * 60
    puts "❌ Transfer failed!"
    puts "=" * 60
    exit 1
  end

rescue => e
  puts "\n❌ Error: #{e.message}"
  puts e.backtrace.first(5)
  exit 1
end

