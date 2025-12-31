// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title DEVPNToken
 * @dev DeVPN Token - ERC20 token with initial supply of 100,000,000 tokens
 */
contract DEVPNToken is ERC20 {
    /**
     * @dev Constructor that mints 100,000,000 tokens to the deployer
     * Initial supply: 100,000,000 DEVPN tokens (with 18 decimals)
     */
    constructor() ERC20("DeVPN Token", "DEVPN") {
        uint256 initialSupply = 100000000 * 10**decimals(); // 100,000,000 tokens
        _mint(msg.sender, initialSupply);
    }
}

