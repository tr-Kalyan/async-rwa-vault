// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockUSDC is ERC20 {
    uint8 private _decimals;

    constructor() ERC20("Mock USDC", "mUSDC") {
        _decimals = 6;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    // Unlimited mint for testing — only in anvil/local
    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    // Optional: faucet function for quick testing
    function faucet(uint256 amount) external {
        mint(msg.sender, amount);
    }
}