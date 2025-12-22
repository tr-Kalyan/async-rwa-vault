// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {AsyncSettlementRWAVault} from "../../src/AsyncSettlementRWAVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {VaultHandler} from "./VaultHandler.t.sol";
import {MockUSDC} from "../mocks/MockUSDC.sol";

contract VaultInvariants is Test {
    AsyncSettlementRWAVault vault;
    IERC20 usdc;
    VaultHandler handler;

    function setUp() public {
        usdc = IERC20(address(new MockUSDC()));
        vault = new AsyncSettlementRWAVault(usdc, "Async RWA Vault", "arUSDC");
        handler = new VaultHandler(vault, usdc);

        targetContract(address(handler));
    }

    /* ================ CORE INVARIANTS ================ */

    /// @notice The Vault's math must always balance.
    /// Total Cash = (Invested/Free Assets) + (Locked Pending Payables)
    function invariant_solvency() public view {
        uint256 totalCash = usdc.balanceOf(address(vault));
        uint256 accounting = vault.totalAssets() + vault.totalPendingAssets();

        assertEq(totalCash, accounting, "Solvency broken: Cash != Assets + Liabilities");
    }

    /// @notice We should never promise to pay more than we physically hold
    /// (Note: This assumes funds are not invested off-chain during this test)
    function invariant_solvency_liquidity() public view {
        assertLe(vault.totalPendingAssets(), usdc.balanceOf(address(vault)), "Insolvent: Liabilities exceed Cash");
    }
}
