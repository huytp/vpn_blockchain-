// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title DEVPN Token
 * @dev ERC20 token với total supply 1 tỷ tokens
 * Distribution:
 * - Node rewards: 90% (900M) - mint theo traffic
 * - Core team: 10% (100M) - vesting 4 năm, cliff 12 tháng
 */
contract DEVPNToken is ERC20, Ownable {
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 * 10**18; // 1 tỷ tokens

    // Distribution pools
    uint256 public constant NODE_REWARDS_POOL = 900_000_000 * 10**18; // 90%
    uint256 public constant CORE_TEAM_POOL = 100_000_000 * 10**18; // 10%

    // Track minted amounts
    uint256 public nodeRewardsMinted = 0;
    uint256 public coreTeamMinted = 0;

    // Authorized minters
    mapping(address => bool) public rewardMinters; // For node rewards

    // Contracts
    address public rewardContract;
    address public vestingContract;

    event RewardMinterAdded(address indexed minter);
    event RewardMinterRemoved(address indexed minter);

    constructor() ERC20("DeVPN Token", "DEVPN") Ownable(msg.sender) {
        // Don't mint tokens in constructor
        // Tokens will be distributed via:
        // - Node rewards: minted on-demand via mintNodeReward()
        // - Core team: transferred to vesting contract after deployment
    }

    /**
     * @dev Initialize distribution (called after deployment)
     * Transfers tokens to vesting contract for core team
     */
    function initializeDistribution(
        address _vestingContract
    ) external onlyOwner {
        require(coreTeamMinted == 0, "Already initialized");

        // Transfer to Vesting (for core team)
        _mint(_vestingContract, CORE_TEAM_POOL);
        coreTeamMinted = CORE_TEAM_POOL;
    }

    /**
     * @dev Mint tokens for node rewards (only from Reward contract)
     * @param to Address to receive tokens
     * @param amount Amount to mint
     */
    function mintNodeReward(address to, uint256 amount) external {
        require(rewardMinters[msg.sender], "Not authorized to mint rewards");
        require(
            nodeRewardsMinted + amount <= NODE_REWARDS_POOL,
            "Node rewards pool exhausted"
        );

        nodeRewardsMinted += amount;
        _mint(to, amount);
    }

    /**
     * @dev Set Reward contract address
     */
    function setRewardContract(address _rewardContract) external onlyOwner {
        rewardContract = _rewardContract;
        rewardMinters[_rewardContract] = true;
        emit RewardMinterAdded(_rewardContract);
    }

    /**
     * @dev Add/remove reward minter
     */
    function setRewardMinter(address minter, bool authorized) external onlyOwner {
        rewardMinters[minter] = authorized;
        if (authorized) {
            emit RewardMinterAdded(minter);
        } else {
            emit RewardMinterRemoved(minter);
        }
    }

    /**
     * @dev Set Vesting contract
     */
    function setVestingContract(address _vestingContract) external onlyOwner {
        vestingContract = _vestingContract;
    }

    /**
     * @dev Get remaining node rewards pool
     */
    function getRemainingNodeRewards() external view returns (uint256) {
        return NODE_REWARDS_POOL - nodeRewardsMinted;
    }

    /**
     * @dev Get distribution status
     */
    function getDistributionStatus() external view returns (
        uint256 _nodeRewardsMinted,
        uint256 _coreTeamMinted
    ) {
        return (
            nodeRewardsMinted,
            coreTeamMinted
        );
    }
}

