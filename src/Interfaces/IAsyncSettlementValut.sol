// SPDX-License_Identifier: MIT
pragma solidity ^0.8.24;

import {IERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

// Extending ERC-4626 for standard functions + adding ERC-7540 stule async redeem
interface IAsyncSettlementVault is IERC4626 {

    /* ================ ERC-7540 ASYNC REDEEM EXTENSIONS ================ */

    /**
     * @notice Request redemption of shares. Burns shares immediately, queues claim.
     * @param shares Amount of valt shares to redeem
     * @param owner Owner of the shares (allows meta-tx)
     * @return requestId Unique ID for this pending redemption
    */
   function requestRedeem(uint256 shares, address owner) external returns(uint256 requestId);

    /**
     * @notice View how many assets a pending request will yield when claimable
     * @param requestId The pending request ID
     * @return assets Expected underlying assets (including accrued yeild at claim time)
     * @return claimableAt 
    */
   function pendingRedeemRequest(uint256 requestId) external view returns (uint256 assets, uint256 claimableAt);

    /**
     * @notice Claim a matured pending redemption
     * @dev Re-uses ERC-4626 redeem/withdraw semantics for claiming
     * @param requestId The request to claim
    */
   function claimRedeem(uint256 requestId) external;


   /* ================ CONFIG & EVENTS ================ */

    event RedemptionRequested(uint256 indexed requestId, address indexed owner, uint256 shares, uint256 expectedAssets);
    event RedemptionClaimed(uint256 indexed requestId, address indexed receiver, uint256 assets);
    event SettlementDelayUpdated(uint256 newDelay);
}
