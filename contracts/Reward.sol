// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "./DEVPNToken.sol";

/**
 * @title Reward
 * @dev Quản lý reward distribution sử dụng Merkle tree
 * Mints tokens từ node rewards pool (90% of total supply)
 */
contract Reward {
    DEVPNToken public token;

    mapping(uint => bytes32) public epochRoots;
    mapping(uint => mapping(address => bool)) public claimed;

    uint public currentEpoch;

    address public owner;

    event EpochCommitted(uint indexed epoch, bytes32 merkleRoot);
    event RewardClaimed(address indexed recipient, uint epoch, uint amount);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    constructor(address _tokenAddress) {
        token = DEVPNToken(_tokenAddress);
        owner = msg.sender;
    }

    /**
     * @dev Commit merkle root cho epoch
     * @param epoch Epoch number
     * @param merkleRoot Merkle root của reward tree
     */
    function commitEpoch(
        uint epoch,
        bytes32 merkleRoot
    ) external {
        require(epoch > currentEpoch, "Invalid epoch");
        epochRoots[epoch] = merkleRoot;
        currentEpoch = epoch;

        emit EpochCommitted(epoch, merkleRoot);
    }

    /**
     * @dev Claim reward với merkle proof
     * @param epoch Epoch number
     * @param amount Số lượng token được claim
     * @param proof Merkle proof
     */
    function claimReward(
        uint epoch,
        uint amount,
        bytes32[] calldata proof
    ) external {
        require(epochRoots[epoch] != bytes32(0), "Epoch not committed");
        require(!claimed[epoch][msg.sender], "Already claimed");
        require(verifyProof(epoch, msg.sender, amount, proof), "Invalid proof");

        claimed[epoch][msg.sender] = true;

        // Mint from node rewards pool
        token.mintNodeReward(msg.sender, amount);

        emit RewardClaimed(msg.sender, epoch, amount);
    }

    /**
     * @dev Transfer ownership
     */
    function transferOwnership(address newOwner) external onlyOwner {
        owner = newOwner;
    }

    /**
     * @dev Verify merkle proof
     */
    function verifyProof(
        uint epoch,
        address recipient,
        uint amount,
        bytes32[] calldata proof
    ) internal view returns (bool) {
        bytes32 leaf = keccak256(abi.encodePacked(recipient, amount));
        bytes32 root = epochRoots[epoch];

        bytes32 computedHash = leaf;
        for (uint i = 0; i < proof.length; i++) {
            if (computedHash < proof[i]) {
                computedHash = keccak256(abi.encodePacked(computedHash, proof[i]));
            } else {
                computedHash = keccak256(abi.encodePacked(proof[i], computedHash));
            }
        }

        return computedHash == root;
    }

    /**
     * @dev Get remaining node rewards pool
     */
    function getRemainingNodeRewards() external view returns (uint256) {
        return token.getRemainingNodeRewards();
    }
}

