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

    event RedemptionClaimed(
        uint256 indexed requestId,
        address indexed receiver,
        uint256 assets
    );

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
        (address usdcAddress, ) = helperConfig.activeNetworkConfig();
        usdc = IERC20(usdcAddress);

        // In local: mock was minted in HelperConfig broadcast
        // In fork: real USDC → need to fund users
        if (block.chainid != 31337) {  // not anvil
            // Fund via deal on fork
            deal(address(usdc), alice, 10000 * 1e6);
            deal(address(usdc), bob, 10000 * 1e6);
        }
        // On local anvil: mock already minted during HelperConfig broadcast? Wait — no.

        // Better: Always fund after deploy
        // Local: mock has mint()
        // Fork: use deal
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
        uint256 requestId = vault.requestRedeem(shares, alice, alice);

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

        // Alice requests exit
        vm.startPrank(alice);
        vault.requestRedeem(aliceShares, alice, alice);
        vm.stopPrank();

        uint256 priceAfter = vault.convertToAssets(1 ether);

        // PRICE CHECK
        // With the fix, Assets = 500, Shares = 500. Price = 1.0.
        // Without the fix, Assets = 1500, Shares = 500. Price = 3.0.
        assertEq(priceBefore, priceAfter, "Price spiked! Accounting error."); 
    }

    /* ================ EDGE CASES & REVERTS ================ */

    function test_RevertIf_ZeroShares() public {
        vm.expectRevert("Zero shares");
        vault.requestRedeem(0, alice, alice);
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
        vault.requestRedeem(aliceShares, alice, alice);
        vm.stopPrank();
    }

    function test_DoubleClaimReverts() public {
        // Setup: Alice deposits and requests
        vm.startPrank(alice);
        usdc.approve(address(vault), 1000 * 1e6);
        vault.deposit(1000 * 1e6, alice);
        uint256 shares = vault.balanceOf(alice);
        uint256 requestId = vault.requestRedeem(shares, alice, alice);
        vm.stopPrank();

        vm.warp(block.timestamp + DELAY + 1);

        vm.prank(alice);
        vault.claimRedeem(requestId);

        // Second claim
        vm.expectRevert("Invalid request");
        vm.prank(alice);
        vault.claimRedeem(requestId);
    }

    function test_SyncWithdrawDisabled() public {
        vm.expectRevert("Use requestRedeem for async withdrawal");
        vault.withdraw(100, alice, alice);
    }
}