// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {MockUSDC} from "../test/mocks/MockUSDC.sol";

contract HelperConfig is Script {
    struct NetworkConfig {
        address usdc;
        uint8 decimals;
    }

    NetworkConfig public activeNetworkConfig;

    constructor() {
        if (block.chainid == 11155111) {
            activeNetworkConfig = getSepoliaEthConfig();
        } else if (block.chainid == 1) {
            activeNetworkConfig = getMainnetEthConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        }
    }

    function getSepoliaEthConfig() public pure returns (NetworkConfig memory) {
        return NetworkConfig({usdc: 0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8, decimals: 6});
    }

    function getMainnetEthConfig() public pure returns (NetworkConfig memory) {
        return NetworkConfig({usdc: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, decimals: 6});
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
        // If we already deployed a mock, return it (Singleton pattern)
        if (activeNetworkConfig.usdc != address(0)) {
            return activeNetworkConfig;
        }

        vm.startBroadcast();
        MockUSDC mockUsdc = new MockUSDC();

        vm.stopBroadcast();

        return NetworkConfig({usdc: address(mockUsdc), decimals: 6});
    }
}
