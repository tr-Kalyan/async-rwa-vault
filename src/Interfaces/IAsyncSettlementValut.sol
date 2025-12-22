// SPDX-License_Identifier: MIT
pragma solidity ^0.8.24;

import {IERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

// Extending ERC-4626 for standard functions + adding ERC-7540 stule async redeem
interface IAsyncSettlementVault is IERC4626 {
    /* ================ ASYNC REDEEM EXTENSIONS ================ */

    /**
     * @notice Request asynchronous redemption
     * @dev Request redemption of shares. Burns shares immediately, queues claim.
     * @param shares Amount of valt shares to redeem
     * @param receiver Recipient of assets on claim
     * @param owner Owner of the shares (allows meta-tx)
     * @param minAssets Minimum acceptable assets (slippage protection)
     * @return requestId Unique ID for this pending redemption
    */
    function requestRedeem(
        uint256 shares,
        address receiver,
        address owner,
        uint256 minAssets
    ) external returns (uint256 requestId);
    
    /**
     * @notice Cancel a pending redemption request
     * @dev Only callable before claimableAt, re-mints shares at current price
     * @param requestId The pending request to cancel
    */
    function cancelRedeem(uint256 requestId) external;


    /**
     * @notice View pending redemption details
     * @param requestId The request ID
     * @return assets Snapshotted assets owed
     * @return claimableAt Timestamp when claimable
    */
    function pendingRedeemRequest(uint256 requestId) external view returns (uint256 assets, uint256 claimableAt);

    /**
     * @notice Claim matured redemption
     * @param requestId The request to claim
    */
    function claimRedeem(uint256 requestId) external;

    /* ================ EVENTS ================ */

    event RedemptionRequested(
        uint256 indexed requestId,
        address indexed owner,
        address indexed receiver,
        uint256 shares,
        uint256 expectedAssets,
        uint256 claimableAt
    );

    event RedemptionCancelled(
        uint256 indexed requestId,
        address indexed owner,
        uint256 assetsReturned,
        uint256 sharesMinted
    );

    event RedemptionClaimed(
        uint256 indexed requestId,
        address indexed receiver,
        uint256 assets
    );

    event YieldDistributed(uint256 amount, uint256 newSharePrice);

    event SettlementDelayUpdated(uint256 newDelay);
}
