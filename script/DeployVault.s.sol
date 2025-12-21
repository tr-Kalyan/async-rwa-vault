// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {AsyncSettlementRWAVault} from "../src/AsyncSettlementRWAVault.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DeployVault is Script {
    function run() external returns (AsyncSettlementRWAVault, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();

        (address usdcAddress,) = helperConfig.activeNetworkConfig();

        vm.startBroadcast();

        AsyncSettlementRWAVault vault = new AsyncSettlementRWAVault(IERC20(usdcAddress), "Async RWA Vault", "arUSDC");

        vm.stopBroadcast();

        return (vault, helperConfig);
    }
}
