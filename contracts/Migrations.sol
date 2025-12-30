// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title Migrations
 * @dev Tracks migration status for Truffle/Hardhat
 */
contract Migrations {
    address public owner;
    uint256 public lastCompletedMigration;

    modifier restricted() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    function setCompleted(uint256 completed) external restricted {
        lastCompletedMigration = completed;
    }

    function upgrade(address newAddress) external restricted {
        Migrations upgraded = Migrations(newAddress);
        upgraded.setCompleted(lastCompletedMigration);
    }
}

