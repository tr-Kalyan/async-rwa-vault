// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {DeployVault} from "../script/DeployVault.s.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AsyncSettlementRWAVault} from "../src/AsyncSettlementRWAVault.sol";
import {MockUSDC} from "./mocks/MockUSDC.sol";

contract AsyncVaultTest is Test {
    AsyncSettlementRWAVault vault;
    IERC20 usdc;
    HelperConfig helperConfig;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address eve = makeAddr("eve");

    uint256 constant INITIAL_SUPPLY = 10_000 * 1e6; // 10k USDC (6 decimals)
    uint256 constant DELAY = 48 hours;

    event RedemptionRequested(
        uint256 indexed requestId,
        address indexed owner,
        address indexed receiver,
        uint256 shares,
        uint256 expectedAssets,
        uint256 claimableAt
    );

    event RedemptionClaimed(uint256 indexed requestId, address indexed receiver, uint256 assets);

    // function setUp() public {
    //     // Deploy mock USDC
    //     usdc = new MockUSDC();

    //     // Deploy vault with mock USDC
    //     vault = new AsyncSettlementRWAVault(
    //         IERC20(address(usdc)),
    //         "Async RWA USDC Vault",
    //         "arUSDC"
    //     );

    //     // Mint initial USDC to users
    //     usdc.mint(alice, INITIAL_SUPPLY);
    //     usdc.mint(bob, INITIAL_SUPPLY);

    //     // Label for nicer traces
    //     vm.label(address(usdc), "USDC");
    //     vm.label(address(vault), "Vault");
    //     vm.label(alice, "Alice");
    //     vm.label(bob, "Bob");
    // }

    function setUp() public {
        DeployVault deployer = new DeployVault();
        (vault, helperConfig) = deployer.run();

        // Now extract the correct USDC from config
        (address usdcAddress,) = helperConfig.activeNetworkConfig();
        usdc = IERC20(usdcAddress);

        if (block.chainid == 31337) {
            // local anvil
        // Mock has mint function
            MockUSDC mock = MockUSDC(usdcAddress);
            mock.mint(alice, 10000 * 1e6);
            mock.mint(bob, 10000 * 1e6);
        } else {
            // Fork: real token
            deal(address(usdc), alice, 10000 * 1e6);
            deal(address(usdc), bob, 10000 * 1e6);
        }
    }

    /* ================ HAPPY PATH ================ */

    function test_DepositAndRequestRedeemAndClaim() public {
        uint256 depositAmount = 1000 * 1e6;

        vm.startPrank(alice);
        usdc.approve(address(vault), depositAmount);
        uint256 shares = vault.deposit(depositAmount, alice);
        vm.stopPrank();

        uint256 expectedAssets = vault.previewRedeem(shares);

        // Expect Event
        vm.expectEmit(true, true, true, true);
        emit RedemptionRequested(1, alice, alice, shares, expectedAssets, block.timestamp + DELAY);

        vm.prank(alice);
        uint256 requestId = vault.requestRedeem(shares, alice, alice, expectedAssets);

        // CHECKS
        assertEq(requestId, 1);
        assertEq(vault.totalSupply(), 0);

        // totalAssets() should be 0 because we subtracted pending assets!
        assertEq(vault.totalAssets(), 0);

        // Helper check
        assertEq(vault.totalPendingAssets(), expectedAssets);

        // Warp and Claim
        vm.warp(block.timestamp + DELAY + 1);

        vm.expectEmit(true, true, false, true);
        emit RedemptionClaimed(requestId, alice, expectedAssets);

        vm.prank(alice);
        vault.claimRedeem(requestId);

        assertEq(usdc.balanceOf(alice), 10_000 * 1e6); // Back to start
        assertEq(vault.totalPendingAssets(), 0);
    }

    /* ================ PRICE STABILITY TEST ================ */

    function test_PriceStabilityDuringPendingRedemption() public {
        // Alice 1000, Bob 500
        vm.startPrank(alice);
        usdc.approve(address(vault), 1000 * 1e6);
        vault.deposit(1000 * 1e6, alice);
        vm.stopPrank();

        vm.startPrank(bob);
        usdc.approve(address(vault), 500 * 1e6);
        vault.deposit(500 * 1e6, bob);
        vm.stopPrank();

        uint256 aliceShares = vault.balanceOf(alice);
        uint256 priceBefore = vault.convertToAssets(1 ether);
        uint256 expectedAssets = vault.convertToAssets(aliceShares);

        // Alice requests exit
        vm.startPrank(alice);
        vault.requestRedeem(aliceShares, alice, alice, expectedAssets);
        vm.stopPrank();

        uint256 priceAfter = vault.convertToAssets(1 ether);

        // PRICE CHECK
        // With the fix, Assets = 500, Shares = 500. Price = 1.0.
        // Without the fix, Assets = 1500, Shares = 500. Price = 3.0.
        assertEq(priceBefore, priceAfter, "Price spiked! Accounting error.");
    }

    function test_DepositYieldIncreasesSharePrice() public {
        // Alice deposits
        vm.startPrank(alice);
        usdc.approve(address(vault), 1000 * 1e6);
        uint256 aliceShares = vault.deposit(1000 * 1e6, alice);
        vm.stopPrank();

        uint256 aliceValueBefore = vault.convertToAssets(aliceShares);
        assertEq(aliceValueBefore, 1000 * 1e6);

        // Mint tokens to Admin
        address admin = vault.owner();
        deal(address(usdc), admin, 50 * 1e6);

        // Admin deposits yield
        vm.startPrank(admin);
        usdc.approve(address(vault), 50 * 1e6);
        vault.depositYield(50 * 1e6);
        vm.stopPrank();

        // Assets = 1000 (Alice) + 50 (Yield) = 1050 USDC
        // Shares = 1000 (Alice)
        // Price = 1050 / 1000 = 1.05 USDC per Share
        uint256 aliceValueAfter = vault.convertToAssets(aliceShares);
        uint256 expected = 1050 * 1e6;
        assertApproxEqAbs(aliceValueAfter, expected, 1, "Dust from rounding");

        assertEq(vault.totalSupply(), aliceShares);
        assertEq(vault.totalAssets(), 1050 * 1e6); // no new shares
    }

    function test_CancelRedeem_ProtectsYieldForOthers() public {
        // Alice deposits
        vm.startPrank(alice);
        usdc.approve(address(vault), 1000 * 1e6);
        vault.deposit(1000 * 1e6, alice);
        vm.stopPrank();

        // Bob deposits
        vm.startPrank(bob);
        usdc.approve(address(vault), 1000 * 1e6);
        vault.deposit(1000 * 1e6, bob);
        vm.stopPrank();

        // Alice requests exit
        vm.startPrank(alice);
        uint256 aliceShares = vault.balanceOf(alice);
        uint256 reqId = vault.requestRedeem(aliceShares, alice, alice, 0); // 0 minAssets for now
        vm.stopPrank();

        // Admin distributes Yield (e.g., 100 USDC)
        address admin = vault.owner();
        deal(address(usdc), admin, 100 * 1e6);

        vm.startPrank(admin);
        usdc.approve(address(vault), 100 * 1e6);
        vault.depositYield(100 * 1e6);
        vm.stopPrank();

        // Bob's Shares should now be worth ~1100 USDC.
        uint256 bobShareValue = vault.convertToAssets(vault.balanceOf(bob));
        assertApproxEqAbs(bobShareValue, 1100 * 1e6, 1e4); // Allow small rounding

        // Alice Cancels
        vm.startPrank(alice);
        vault.cancelRedeem(reqId);
        vm.stopPrank();

        // Alice re-deposited 1000 USDC.
        // At the NEW price (1.10), 1000 USDC buys fewer shares.
        uint256 aliceNewShares = vault.balanceOf(alice);

        assertLt(aliceNewShares, aliceShares, "Alice should have fewer shares due to price increase");

        uint256 aliceNewValue = vault.convertToAssets(aliceNewShares);
        assertApproxEqAbs(aliceNewValue, 1000 * 1e6, 1e4);
    }

    /* ================ EDGE CASES & REVERTS ================ */

    function test_RevertIf_ZeroShares() public {
        vm.expectRevert("Zero shares");
        vault.requestRedeem(0, alice, alice, 100);
    }

    function test_RevertIf_InsufficientAllowance() public {
        vm.startPrank(alice);
        usdc.approve(address(vault), 1000 * 1e6);
        vault.deposit(1000 * 1e6, alice);
        vm.stopPrank();

        uint256 aliceShares = vault.balanceOf(alice);
        // Eve tries to redeem Alice's shares without allowance
        vm.expectRevert(); // OZ: "ERC20: insufficient allowance"
        vm.startPrank(eve);
        vault.requestRedeem(aliceShares, alice, alice, aliceShares);
        vm.stopPrank();
    }

    function test_DoubleClaimReverts() public {
        // Setup: Alice deposits and requests
        vm.startPrank(alice);
        usdc.approve(address(vault), 1000 * 1e6);
        vault.deposit(1000 * 1e6, alice);
        uint256 shares = vault.balanceOf(alice);
        uint256 expectedAssets = vault.convertToAssets(shares);
        uint256 requestId = vault.requestRedeem(shares, alice, alice, expectedAssets);
        vm.stopPrank();

        vm.warp(block.timestamp + DELAY + 1);

        vm.prank(alice);
        vault.claimRedeem(requestId);

        // Second claim
        vm.expectRevert("Invalid request");
        vm.prank(alice);
        vault.claimRedeem(requestId);
    }

    function test_RevertIf_SlippageExceeded() public {
        // 1. Setup
        vm.startPrank(alice);
        usdc.approve(address(vault), 100 * 1e6);
        vault.deposit(100 * 1e6, alice);

        // 2. Alice expects 1:1 (100 USDC), but sets minAssets to 101 USDC
        // This simulates a scenario where she thought price was 1.01
        uint256 shares = vault.balanceOf(alice);
        uint256 impossibleMinAssets = 101 * 1e6;

        // 3. Expect Revert
        vm.expectRevert("Slippage: Return too low");
        vault.requestRedeem(shares, alice, alice, impossibleMinAssets);
        vm.stopPrank();
    }

    function test_DepositYieldDoesNotBenefitPendingRedemptions() public {
        // Alice deposit 1000 USDC
        vm.startPrank(alice);
        usdc.approve(address(vault), 1000 * 1e6);
        uint256 aliceShares = vault.deposit(1000 * 1e6, alice);
        vm.stopPrank();

        // Alice requests full redemption → snapshot taken
        vm.startPrank(alice);
        uint256 requestId = vault.requestRedeem(aliceShares, alice, alice, 0); // no minAssets
        vm.stopPrank();

        // Capture her locked amount
        (uint256 lockedAssets,) = vault.pendingRedeemRequest(requestId);
        assertEq(lockedAssets, 1000 * 1e6); // snapshotted at request time

        // During delay, admin deposits 50 USDC yield
        address admin = vault.owner();
        deal(address(usdc), admin, 50 * 1e6);

        vm.startPrank(admin);
        usdc.approve(address(vault), 50 * 1e6);
        vault.depositYield(50 * 1e6);
        vm.stopPrank();

        // Vault now has 1050 USDC, but pending = 1000 USDC locked
        assertEq(vault.totalAssets(), 50 * 1e6); // only remaining investable
        assertEq(vault.totalPendingAssets(), 1000 * 1e6);

        // Warp past delay → Alice claims
        vm.warp(block.timestamp + vault.settlementDelay() + 1);

        uint256 aliceBalanceBefore = usdc.balanceOf(alice);

        vm.prank(alice);
        vault.claimRedeem(requestId);

        uint256 aliceBalanceAfter = usdc.balanceOf(alice);

        // CRITICAL ASSERTION: She gets exactly the snapshot — NO extra yield
        assertEq(aliceBalanceAfter - aliceBalanceBefore, 1000 * 1e6);
        assertEq(aliceBalanceAfter - aliceBalanceBefore, lockedAssets);

        // Remaining 50 USDC stays in vault for future/other holders
        assertEq(vault.totalAssets(), 50 * 1e6);
        assertEq(vault.totalPendingAssets(), 0);
    }

    function test_SyncWithdrawDisabled() public {
        vm.expectRevert("Use requestRedeem for async withdrawal");
        vault.withdraw(100, alice, alice);
    }
}
