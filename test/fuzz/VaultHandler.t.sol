// test/invariants/VaultHandler.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AsyncSettlementRWAVault} from "../../src/AsyncSettlementRWAVault.sol";

contract VaultHandler is Test {
    AsyncSettlementRWAVault public vault;
    IERC20 public usdc;
    address public admin;

    address[] public users;
    uint256[] public activeRequestIds; 

    uint256 public constant INITIAL_USER_BALANCE = 10_000 * 1e6;
    uint256 public constant MAX_YIELD = 500 * 1e6;

    constructor(AsyncSettlementRWAVault _vault, IERC20 _usdc) {
        vault = _vault;
        usdc = _usdc;
        admin = vault.owner();

        // Create 20 ghost users for better coverage
        for (uint256 i = 0; i < 20; i++) {
            address user = makeAddr(vm.toString(i));
            users.push(user);
            deal(address(usdc), user, INITIAL_USER_BALANCE);
        }
    }

    /* ================ USER ACTIONS ================ */

    function deposit(uint256 userId, uint256 amount) public {
        userId = bound(userId, 0, users.length - 1);
        address user = users[userId];

        // FIX: Check actual balance to prevent 'ERC20InsufficientBalance' reverts
        uint256 balance = usdc.balanceOf(user);
        if (balance < 1e6) return; // Skip if user is broke

        // Cap deposit to actual balance or 5000 (whichever is lower)
        uint256 maxDeposit = balance > 5000 * 1e6 ? 5000 * 1e6 : balance;
        amount = bound(amount, 1e6, maxDeposit);

        vm.startPrank(user);
        usdc.approve(address(vault), amount);
        vault.deposit(amount, user);
        vm.stopPrank();
    }

    function requestRedeem(uint256 userId, uint256 sharePercent, uint256 minAssetsOffset) public {
        userId = bound(userId, 0, users.length - 1);
        sharePercent = bound(sharePercent, 1, 100); 

        address user = users[userId];
        uint256 shares = vault.balanceOf(user);

        if (shares == 0) return;

        uint256 sharesToRedeem = (shares * sharePercent) / 100;
        if (sharesToRedeem == 0) return;

        uint256 expectedAssets = vault.previewRedeem(sharesToRedeem);
        
        // Slippage calc
        uint256 offset = bound(minAssetsOffset, 0, expectedAssets / 10);
        uint256 minAssets = expectedAssets - offset;

        vm.startPrank(user);
        uint256 requestId = vault.requestRedeem(sharesToRedeem, user, user, minAssets);
        activeRequestIds.push(requestId);
        vm.stopPrank();
    }

    function cancelRedeem(uint256 requestIndex) public {
        if (activeRequestIds.length == 0) return;

        requestIndex = bound(requestIndex, 0, activeRequestIds.length - 1);
        uint256 requestId = activeRequestIds[requestIndex];

        // FIX: Tuple unpacking (No struct)
        (address owner, , , , uint256 claimableAt) = vault.pendingRedemptions(requestId);

        if (owner == address(0)) {
            _removeRequestId(requestIndex);
            return;
        }

        // FIX: Respect your contract condition (Only cancel BEFORE claimableAt)
        if (block.timestamp >= claimableAt) {
            // It's too late to cancel, so we skip calling the function
            // (Calling it would revert, wasting a fuzz run)
            return; 
        }

        vm.prank(owner);
        vault.cancelRedeem(requestId);

        _removeRequestId(requestIndex);
    }

    function claimRedeem(uint256 requestIndex) public {
        if (activeRequestIds.length == 0) return;

        requestIndex = bound(requestIndex, 0, activeRequestIds.length - 1);
        uint256 requestId = activeRequestIds[requestIndex];

        (address owner, , , , uint256 claimableAt) = vault.pendingRedemptions(requestId);

        if (owner == address(0)) {
            _removeRequestId(requestIndex);
            return;
        }

        // Warp time if needed
        if (block.timestamp < claimableAt) {
            vm.warp(claimableAt + 1);
        }

        vm.prank(owner);
        try vault.claimRedeem(requestId) {
            _removeRequestId(requestIndex);
        } catch {
            // Failed (likely insufficient liquidity) - keep in list
        }
    }

    /* ================ ADMIN ACTIONS ================ */

    function depositYield(uint256 amount) public {
        amount = bound(amount, 1e6, MAX_YIELD);

        vm.startPrank(admin);
        deal(address(usdc), admin, amount);
        usdc.approve(address(vault), amount);
        vault.depositYield(amount);
        vm.stopPrank();
    }

    function rescindRedemption(uint256 requestIndex, string calldata reason) public {
        if (activeRequestIds.length == 0) return;

        requestIndex = bound(requestIndex, 0, activeRequestIds.length - 1);
        uint256 requestId = activeRequestIds[requestIndex];

        (address owner, , , ,) = vault.pendingRedemptions(requestId);
        if (owner == address(0)) {
            _removeRequestId(requestIndex);
            return;
        }

        vm.prank(admin);
        vault.rescindRedemption(requestId, reason);

        _removeRequestId(requestIndex);
    }

    /* ================ INTERNAL ================ */

    function _removeRequestId(uint256 index) internal {
        activeRequestIds[index] = activeRequestIds[activeRequestIds.length - 1];
        activeRequestIds.pop();
    }

    // Helper for invariants to get active requests
    function numActiveRequests() public view returns (uint256) {
        return activeRequestIds.length;
    }
}