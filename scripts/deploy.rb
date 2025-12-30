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

  def eth_get_transaction_by_hash(tx_hash)
    call_with_retry('eth_getTransactionByHash', [tx_hash])
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
    puts "💡 Solutions:"
    puts "   1. Wait a few seconds and try again"
    puts "   2. Upgrade to Tatum Paid plan: https://co.tatum.io/upgrade"
    puts "   3. Use a different RPC endpoint"
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
    log_debug_info(method, params) if should_debug?(method)

    request
  end

  def should_debug?(method)
    ['eth_sendRawTransaction', 'eth_estimateGas'].include?(method)
  end

  def log_debug_info(method, params)
    puts "🔍 Debug: Calling #{method}"
    if method == 'eth_sendRawTransaction' && params[0]
      puts "   Transaction length: #{(params[0].length - 2) / 2} bytes"
    end
  end

  def handle_http_response(response, method)
    check_http_status(response)
    result = parse_json_response(response.body)
    log_response_if_needed(result, response.body, method)
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

  def log_response_if_needed(result, body, method)
    return unless result['error'] || (result['result'].nil? && method == 'eth_sendRawTransaction')

    puts "🔍 Full RPC Response: #{body}"
    puts "⚠️  Warning: RPC returned nil result" if result['result'].nil?
  end

  def check_rpc_errors(result)
    return unless result['error']

    error_msg = "RPC Error: #{result['error']['message']} (Code: #{result['error']['code']})"
    error_msg += "\n   Data: #{result['error']['data']}" if result['error']['data']
    raise error_msg
  end
end

# ============================================================================
# ContractDeployer - Handles contract deployment
# ============================================================================
class ContractDeployer
  DEFAULT_GAS_LIMIT = 3_000_000
  DEFAULT_GAS_PRICE = 30_000_000_000 # 30 gwei
  WEI_TO_MATIC = 1_000_000_000_000_000_000.0
  MIN_BALANCE_WARNING_MULTIPLIER = 1.2

  def initialize(rpc_client, private_key, chain_id)
    @rpc = rpc_client
    @private_key = private_key
    @chain_id = chain_id
    @key = Eth::Key.new(priv: private_key)
  end

  def deploy_with_constructor(bytecode, abi, constructor_params = [])
    full_bytecode = prepare_bytecode_with_constructor(bytecode, abi, constructor_params)
    deploy(full_bytecode, abi)
  end

  def deploy(bytecode, abi = nil)
    print_deployment_header

    balance_info = check_balance
    nonce = get_nonce
    gas_price = get_gas_price
    gas_limit = estimate_gas_limit(bytecode)
    validate_balance_for_gas(balance_info, gas_price, gas_limit)

    transaction = build_transaction(bytecode, nonce, gas_price, gas_limit)
    signed_tx = sign_transaction(transaction)
    tx_hash = send_transaction(signed_tx)
    receipt = wait_for_receipt(tx_hash)

    process_deployment_result(receipt, tx_hash)
  end

  private

  def prepare_bytecode_with_constructor(bytecode, abi, constructor_params)
    constructor_data = ''
    if constructor_params.any? && abi
      constructor_data = ContractHelper.encode_constructor_params(abi, constructor_params)
    end

    bytecode_clean = bytecode.to_s
    bytecode_clean = bytecode_clean[2..-1] if bytecode_clean.start_with?('0x')
    full_bytecode = bytecode_clean + constructor_data
    full_bytecode = "0x#{full_bytecode}" unless full_bytecode.start_with?('0x')

    full_bytecode
  end

  def print_deployment_header
    puts "=" * 60
    puts "🚀 Deploying Contract"
    puts "=" * 60
    puts "Network: Polygon Amoy Testnet"
    puts "Chain ID: #{@chain_id}"
    puts "Deployer Address: #{@key.address}"
    puts "=" * 60
  end

  def check_balance
    balance_hex = @rpc.eth_get_balance(@key.address)
    balance_wei = hex_to_int(balance_hex)
    balance_matic = balance_wei / WEI_TO_MATIC

    puts "\n💰 Balance: #{balance_matic} MATIC"
    { wei: balance_wei, matic: balance_matic }
  end

  def get_nonce
    nonce_hex = @rpc.eth_get_transaction_count(@key.address)
    nonce = hex_to_int(nonce_hex)
    puts "📝 Nonce: #{nonce}"
    nonce
  end

  def get_gas_price
    gas_price_hex = @rpc.eth_gas_price
    gas_price = hex_to_int(gas_price_hex)

    if gas_price == 0
      puts "⚠️  Could not get gas price, using default: 30 gwei"
      gas_price = DEFAULT_GAS_PRICE
    end

    puts "⛽ Gas Price: #{gas_price} wei (#{gas_price / 1_000_000_000.0} gwei)"
    gas_price
  end

  def estimate_gas_limit(bytecode)
    transaction_data = {
      from: @key.address,
      data: bytecode
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

  def validate_balance_for_gas(balance_info, gas_price, gas_limit)
    estimated_gas_cost = gas_price * gas_limit
    estimated_gas_cost_matic = estimated_gas_cost / WEI_TO_MATIC

    puts "💸 Estimated gas cost: #{estimated_gas_cost_matic.round(4)} MATIC"

    if balance_info[:wei] < estimated_gas_cost
      raise_insufficient_balance_error(balance_info, estimated_gas_cost_matic, estimated_gas_cost)
    elsif balance_info[:wei] < estimated_gas_cost * MIN_BALANCE_WARNING_MULTIPLIER
      puts "⚠️  Warning: Balance may be too low (recommended: #{(estimated_gas_cost * MIN_BALANCE_WARNING_MULTIPLIER) / WEI_TO_MATIC} MATIC)"
    end
  end

  def raise_insufficient_balance_error(balance_info, estimated_cost, estimated_cost_wei)
    shortage = (estimated_cost_wei - balance_info[:wei]) / WEI_TO_MATIC
    puts "\n❌ ERROR: Insufficient balance!"
    puts "   Balance: #{balance_info[:matic]} MATIC"
    puts "   Required: ~#{estimated_cost.round(4)} MATIC"
    puts "   Shortage: #{shortage} MATIC"
    puts "\n💡 Get more MATIC from: https://faucet.polygon.technology/"
    raise "Insufficient balance for deployment"
  end

  def build_transaction(bytecode, nonce, gas_price, gas_limit)
    bytecode_clean = bytecode.to_s
    bytecode_clean = bytecode_clean[2..-1] if bytecode_clean.start_with?('0x')

    puts "\n📝 Creating transaction..."
    puts "   Chain ID: #{@chain_id}"
    puts "   Nonce: #{nonce}"
    puts "   Gas Price: #{gas_price} wei"
    puts "   Gas Limit: #{gas_limit}"
    puts "   Bytecode length: #{bytecode_clean.length / 2} bytes"

    Eth::Tx.new(
      chain_id: @chain_id,
      nonce: nonce,
      gas_price: gas_price,
      gas_limit: gas_limit,
      data: bytecode_clean
    )
  end

  def sign_transaction(transaction)
    puts "✍️  Signing transaction..."
    transaction.sign(@key)

    signed_tx = transaction.hex
    signed_tx = "0x#{signed_tx}" unless signed_tx.start_with?('0x')

    validate_signed_transaction(signed_tx)
    signed_tx
  end

  def validate_signed_transaction(signed_tx)
    unless signed_tx && signed_tx.start_with?('0x') && signed_tx.length > 2
      raise "Invalid signed transaction format: #{signed_tx.inspect}"
    end
  end

  def send_transaction(signed_tx)
    puts "📤 Sending transaction to Tatum RPC..."
    puts "🔍 Transaction length: #{(signed_tx.length - 2) / 2} bytes"

    begin
      tx_hash = @rpc.eth_send_raw_transaction(signed_tx)
      validate_transaction_hash(tx_hash)
      normalize_transaction_hash(tx_hash)
    rescue => e
      handle_transaction_send_error(e)
    end
  end

  def validate_transaction_hash(tx_hash)
    if tx_hash.nil? || tx_hash.to_s.strip.empty?
      puts "\n❌ Transaction hash is empty!"
      print_transaction_hash_troubleshooting
      raise "Transaction hash is empty. Transaction may have been rejected by the network."
    end
  end

  def print_transaction_hash_troubleshooting
    puts "   This usually means:"
    puts "   1. Transaction was rejected by the network"
    puts "   2. Insufficient balance (0.1 MATIC may not be enough)"
    puts "   3. Gas price too low"
    puts "   4. Invalid transaction format"
    puts "\n💡 Try:"
    puts "   - Get more MATIC from faucet: https://faucet.polygon.technology/"
    puts "   - Check balance is at least 0.2 MATIC"
  end

  def normalize_transaction_hash(tx_hash)
    tx_hash = tx_hash.to_s.strip
    tx_hash = "0x#{tx_hash}" unless tx_hash.start_with?('0x')

    unless tx_hash.length == 66
      puts "⚠️  Warning: Transaction hash length is #{tx_hash.length}, expected 66"
      puts "   Hash: #{tx_hash}"
    end

    puts "\n✅ Transaction sent!"
    puts "📋 Transaction Hash: #{tx_hash}"
    puts "🔗 View on explorer: https://amoy.polygonscan.com/tx/#{tx_hash}"
    puts "\n⏳ Waiting for confirmation..."

    tx_hash
  end

  def handle_transaction_send_error(error)
    puts "\n❌ RPC Error when sending transaction:"
    puts "   #{error.message}"
    puts "\n💡 Possible issues:"
    puts "   - Insufficient balance (need ~0.15 MATIC for deployment)"
    puts "   - Invalid transaction format"
    puts "   - Network connectivity issues"
    puts "   - Tatum API key issues"
    raise
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
        log_receipt_error(e, attempts) unless e.message.include?('not found')
      end

      print "."
      sleep delay
      attempts += 1
    end

    handle_receipt_timeout(tx_hash, max_attempts, delay)
  end

  def log_receipt_error(error, attempts)
    return unless attempts % 5 == 0

    puts "\n⚠️  Error checking receipt: #{error.message}"
  end

  def handle_receipt_timeout(tx_hash, max_attempts, delay)
    puts "\n⚠️  Timeout waiting for receipt (waited #{max_attempts * delay} seconds)"
    puts "   Transaction may still be pending. Check manually:"
    puts "   https://amoy.polygonscan.com/tx/#{tx_hash}"
    nil
  end

  def process_deployment_result(receipt, tx_hash)
    return handle_no_receipt(tx_hash) if receipt.nil?

    status_int = hex_to_int(receipt['status'])

    if status_int == 1
      handle_successful_deployment(receipt, tx_hash)
    else
      handle_failed_deployment(receipt, tx_hash, status_int)
    end
  end

  def handle_no_receipt(tx_hash)
    puts "\n⚠️  Could not get transaction receipt"
    puts "   Transaction hash: #{tx_hash}"
    puts "   Check manually at: https://amoy.polygonscan.com/tx/#{tx_hash}"
    nil
  end

  def handle_successful_deployment(receipt, tx_hash)
    contract_address = receipt['contractAddress']
    gas_used = hex_to_int(receipt['gasUsed'])

    unless contract_address
      puts "\n⚠️  Contract address not found in receipt"
      puts "   Transaction hash: #{tx_hash}"
      return nil
    end

    puts "\n🎉 Contract deployed successfully!"
    puts "📍 Contract Address: #{contract_address}"
    puts "📋 Transaction Hash: #{tx_hash}"
    puts "⛽ Gas Used: #{gas_used}"
    puts "🔗 View contract: https://amoy.polygonscan.com/address/#{contract_address}"

    {
      address: contract_address,
      tx_hash: tx_hash,
      receipt: receipt
    }
  end

  def handle_failed_deployment(receipt, tx_hash, status_int)
    puts "\n❌ Transaction failed!"
    puts "   Status: #{receipt['status']} (#{status_int == 0 ? 'Failed' : 'Unknown'})"
    puts "   Transaction hash: #{tx_hash}"
    puts "   Check details at: https://amoy.polygonscan.com/tx/#{tx_hash}"

    log_transaction_details(tx_hash)
    nil
  end

  def log_transaction_details(tx_hash)
    begin
      tx = @rpc.eth_get_transaction_by_hash(tx_hash)
      return unless tx && tx['gas']

      puts "   Gas limit: #{hex_to_int(tx['gas'])}"
      puts "   Gas price: #{hex_to_int(tx['gasPrice'])}"
    rescue => e
      # Ignore errors when getting transaction details
    end
  end

  def hex_to_int(hex_value)
    return 0 if hex_value.nil?

    hex_str = hex_value.to_s
    hex_str = hex_str.start_with?('0x') ? hex_str : "0x#{hex_str}"
    hex_str.to_i(16)
  rescue => e
    puts "⚠️  Error converting hex to int: #{e.message}, value: #{hex_value.inspect}"
    0
  end
end

# ============================================================================
# ContractHelper - Utility functions for contract operations
# ============================================================================
module ContractHelper
  def self.load_artifact(contract_name)
    artifact_path = File.join(
      __dir__, '..', 'artifacts', 'contracts',
      "#{contract_name}.sol", "#{contract_name}.json"
    )

    unless File.exist?(artifact_path)
      puts "\n❌ Contract artifact not found!"
      puts "   Expected path: #{artifact_path}"
      puts "\n💡 Please compile contracts first:"
      puts "   cd blockchain"
      puts "   npm install"
      puts "   npx hardhat compile"
      puts "\n   Or if using a different build system, ensure artifacts are in:"
      puts "   blockchain/artifacts/contracts/#{contract_name}.sol/#{contract_name}.json"
      raise "Contract artifact not found at: #{artifact_path}"
    end

    artifact = JSON.parse(File.read(artifact_path))

    unless artifact['bytecode'] && artifact['abi']
      raise "Invalid artifact format: missing bytecode or ABI"
    end

    {
      bytecode: artifact['bytecode'],
      abi: artifact['abi']
    }
  end

  def self.encode_constructor_params(abi, params)
    constructor = abi.find { |item| item['type'] == 'constructor' }
    return '' unless constructor && params.any?

    # Simplified: only supports address parameters
    # In production, use full ABI encoding library
    encoded = ''
    params.each do |param|
      next unless param.to_s.start_with?('0x')

      # Address parameter - remove 0x and pad to 64 chars (32 bytes)
      addr = param.to_s[2..-1].downcase
      encoded += '0' * (64 - addr.length) + addr
    end

    encoded
  end
end

# ============================================================================
# DeploymentManager - Manages the full deployment process
# ============================================================================
class DeploymentManager
  DEPLOYMENT_DELAY = 2 # seconds between deployments

  CONTRACTS_TO_DEPLOY = [
    { name: 'DEVPNToken', key: :DEVPN_TOKEN, constructor_params: [] },
    { name: 'NodeRegistry', key: :NODE_REGISTRY, constructor_params: [] },
    { name: 'Reward', key: :REWARD, constructor_params: [:token_address] },
    { name: 'Vesting', key: :VESTING, constructor_params: [:token_address] }
  ].freeze

  def initialize(rpc_client, deployer)
    @rpc = rpc_client
    @deployer = deployer
    @deployments = {}
  end

  def deploy_all
    print_deployment_header

    CONTRACTS_TO_DEPLOY.each_with_index do |contract_config, index|
      deploy_contract(contract_config, index + 1, CONTRACTS_TO_DEPLOY.length)
      sleep(DEPLOYMENT_DELAY) unless index == CONTRACTS_TO_DEPLOY.length - 1
    end

    save_deployments
    print_deployment_summary
  end

  private

  def print_deployment_header
    puts "\n" + "=" * 60
    puts "📦 Bắt đầu deploy tất cả contracts"
    puts "=" * 60
  end

  def deploy_contract(contract_config, current, total)
    puts "\n[#{current}/#{total}] Deploying #{contract_config[:name]}..."

    artifact = ContractHelper.load_artifact(contract_config[:name])
    constructor_params = build_constructor_params(contract_config[:constructor_params])

    result = if constructor_params.empty?
               @deployer.deploy(artifact[:bytecode], artifact[:abi])
             else
               @deployer.deploy_with_constructor(
                 artifact[:bytecode],
                 artifact[:abi],
                 constructor_params
               )
             end

    raise "Failed to deploy #{contract_config[:name]}" unless result

    @deployments[contract_config[:key]] = result
    puts "✅ #{contract_config[:name]} deployed: #{result[:address]}"
  end

  def build_constructor_params(param_types)
    return [] if param_types.empty?

    param_types.map do |type|
      case type
      when :token_address
        @deployments[:DEVPN_TOKEN][:address]
      else
        raise "Unknown constructor parameter type: #{type}"
      end
    end
  end

  def save_deployments
    DeploymentHelper.save_to_env(@deployments)
  end

  def print_deployment_summary
    puts "\n" + "=" * 60
    puts "✨ Tất cả contracts đã được deploy thành công!"
    puts "=" * 60
    puts "\n📋 Deployment Summary:"
    @deployments.each do |name, info|
      puts "   #{name}: #{info[:address]}"
    end
    print_next_steps
  end

  def print_next_steps
    return unless @deployments[:REWARD] && @deployments[:VESTING]

    puts "\n💡 Next steps:"
    puts "   1. Set Reward contract in DEVPNToken: setRewardContract(#{@deployments[:REWARD][:address]})"
    puts "   2. Initialize distribution in DEVPNToken: initializeDistribution("
    puts "      #{@deployments[:VESTING][:address]}"
    puts "    )"
    puts "=" * 60
  end
end

# ============================================================================
# DeploymentHelper - Utility functions for deployment operations
# ============================================================================
module DeploymentHelper
  def self.save_to_env(deployments)
    env_file = File.join(__dir__, '..', '.env')
    env_content = File.exist?(env_file) ? File.read(env_file) : ''

    deployments.each do |name, info|
      var_name = "#{name.upcase}_ADDRESS"
      if env_content.include?("#{var_name}=")
        env_content.gsub!(/#{var_name}=.*/, "#{var_name}=#{info[:address]}")
      else
        env_content += "\n#{var_name}=#{info[:address]}\n"
      end
    end

    File.write(env_file, env_content)
    puts "\n💾 Saved all contract addresses to .env file"
  end
end

# ============================================================================
# Main execution
# ============================================================================
def validate_environment
  raise "TATUM_API_KEY không được tìm thấy trong .env file" unless TATUM_API_KEY
  raise "PRIVATE_KEY không được tìm thấy trong .env file" unless PRIVATE_KEY
end

def check_artifacts_directory
  artifacts_dir = File.join(__dir__, '..', 'artifacts', 'contracts')

  unless Dir.exist?(artifacts_dir)
    puts "\n⚠️  Artifacts directory not found: #{artifacts_dir}"
    puts "\n💡 Please compile contracts first:"
    puts "   cd blockchain"
    puts "   npm install  # (if not already installed)"
    puts "   npx hardhat compile"
    puts "\n   This will create the artifacts directory with compiled contracts."
    raise "Artifacts directory not found. Please compile contracts first."
  end

  # Check if any artifacts exist
  artifact_files = Dir.glob(File.join(artifacts_dir, '**', '*.json'))
  if artifact_files.empty?
    puts "\n⚠️  No artifact files found in: #{artifacts_dir}"
    puts "\n💡 Please compile contracts first:"
    puts "   npx hardhat compile"
    raise "No artifact files found. Please compile contracts first."
  end

  puts "✅ Found #{artifact_files.length} artifact file(s)"
end

def print_header
  puts "=" * 60
  puts "🚀 DEVPNToken Deployment Script"
  puts "=" * 60
  puts "📡 Using Tatum RPC Gateway"
  puts "⚠️  Note: Free plan has 3 requests/second limit"
  puts "   Script will automatically handle rate limiting"
  puts "=" * 60
  puts ""
end

def verify_chain_id(rpc)
  chain_id_hex = rpc.eth_chain_id
  chain_id = chain_id_hex.to_s.to_i(16)
  puts "\n🔗 Connected to chain ID: #{chain_id}"

  if chain_id != POLYGON_AMOY_CHAIN_ID
    puts "⚠️  Warning: Chain ID không khớp với Polygon Amoy (#{POLYGON_AMOY_CHAIN_ID})"
  end

  chain_id
end

# Main execution
begin
  print_header
  validate_environment
  check_artifacts_directory

  rpc = TatumRPCClient.new(TATUM_RPC_URL, TATUM_API_KEY)
  chain_id = verify_chain_id(rpc)
  deployer = ContractDeployer.new(rpc, PRIVATE_KEY, chain_id)

  manager = DeploymentManager.new(rpc, deployer)
  manager.deploy_all

rescue => e
  puts "\n❌ Error: #{e.message}"
  puts e.backtrace.first(5).join("\n")
  exit 1
end
