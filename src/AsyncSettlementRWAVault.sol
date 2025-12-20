// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;


import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
//import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract AsyncSettlementRWAVault is ERC4626, Ownable, ReentrancyGuard {

    using SafeERC20 for IERC20;

    /* ================ CONSTANTS & IMMUTABLES ================ */

    uint256 public constant MIN_DELAY = 24 hours; //(T+1)
    uint256 public constant MAX_DELAY = 7 days;

    // Track total assets locked in the queue  
    uint256 public totalPendingAssets;

    /* ================ CONFIGURABLE STATE ================ */

    uint256 public settlementDelay = 48 hours;

    /* ================ REDEMPTION QUEUE STATE ================ */
    uint256 private _nextRequestId = 1;

    struct RedemptionRequest {
        address owner;
        address receiver;
        uint256 shares;
        uint256 assetAtRequest; // The SNAPSHOT value
        uint256 claimableAt;
    }

    // requestId => RedemptionRequest
    mapping(uint256 => RedemptionRequest) public pendingRedemptions;

    /* ================ Events ================ */
    event SettlementDelayUpdated(uint256);

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

    /* ================ CONSTRUCTOR ================ */
    constructor(
        IERC20 asset_,
        string memory name_,
        string memory symbol_
    ) ERC4626(asset_) ERC20(name_,symbol_) Ownable(msg.sender){}

    

    /**
     * @dev Decimals Offset: 18 (Shares) - 6 (USDC) = 12.
     * OZ v5 handles decimals() automatically if we override this.
     */
    function _decimalsOffset() internal pure override returns (uint8) {
        return 12; // Max inflation protection for 6-decimal USDC
    }

    function setSettlementDelay(uint256 newDelay) external onlyOwner {
        require(newDelay >= MIN_DELAY && newDelay <= MAX_DELAY, "Delay out of bounds");
        
        settlementDelay = newDelay;

        emit SettlementDelayUpdated(newDelay);
    }

    /**
     * @dev AUDITOR FIX: Subtract locked assets from the "Investable" pool.
     * This prevents share price spikes when requests are queued.
     */
    function totalAssets() public view override returns (uint256) {
        return super.totalAssets() - totalPendingAssets;
    }

    function requestRedeem(
        uint256 shares,
        address receiver,
        address owner
    ) external returns (uint256 requestId){

        require(shares > 0, "Zero shares");
        require(receiver != address(0), "Zero receiver");
        require(owner != address(0), "Zero owner");


        // If the caller is NOT the owner, check if they have approval (allowance) to spend the owner's shares.
        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, shares);
        }

        // Calculate expected assets at this moment
        // Why snapshot convertToAssets(shares) ?
        // - Yield may accrue over time (via oracle or strategy)
        // - We freeze the redemption value at the request time -> fair, predictable
        uint256 expectedAssets = previewRedeem(shares);

        require(expectedAssets > 0, "Zero assets"); // Implicitly checks shares > 0 too

        // Burn shares immediately
        // This is critical: reduces totalSupply -> new depositors see correct price
        // Also removes owner from the future yield/risk
        _burn(owner, shares);


        totalPendingAssets += expectedAssets;

        // === Queue the request ===
        requestId = _nextRequestId++;

        pendingRedemptions[requestId] = RedemptionRequest({
            owner: owner,
            receiver: receiver,
            shares:shares,
            assetAtRequest: expectedAssets,
            claimableAt:block.timestamp + settlementDelay
        });

        // === Emit event for indexing ===
        emit RedemptionRequested(
            requestId,
            owner,
            receiver,
            shares,
            expectedAssets,
            block.timestamp + settlementDelay
        );
    }


    function claimRedeem(uint256 requestId) external nonReentrant {
        RedemptionRequest storage request = pendingRedemptions[requestId];

        require(request.owner != address(0), "Invalid request");
        require(block.timestamp >= request.claimableAt, "Not claimable yet");
        require(msg.sender == request.owner || msg.sender == request.receiver, "Not authorized");

        // Cache in memory BEFORE any delete/subtract
        address receiver = request.receiver;
        uint256 assetsToSend = request.assetAtRequest;


        // Delete request to prevent double-claim + refund gas
        totalPendingAssets -= request.assetAtRequest;
        delete pendingRedemptions[requestId];

        


        // Transfer underlying assets
        // Use SafeERC20 if underlying is not trusted - but USDC is fine
        IERC20(asset()).safeTransfer(receiver, assetsToSend);

        emit RedemptionClaimed(requestId, receiver, assetsToSend);

    }


    /* ================ View Functions ================ */
    function pendingRedeemRequest(uint256 requestId)
        external
        view
        returns (uint256 assets, uint256 claimableAt)
    {
        RedemptionRequest memory request = pendingRedemptions[requestId];

        // Return 0 if request doesn't exist or already claimed
        if (request.owner == address(0)){
            return (0,0);
        }

        return (request.assetAtRequest, request.claimableAt);
    }

    /* ================ OVERRIDES ================ */

    /**
     * @dev Strict Async Enforcer: Return 0 to indicate standard withdrawals are disabled.
     * Users MUST use requestRedeem() instead.
     */
    function maxWithdraw(address /*owner*/) public pure override returns (uint256) {
        return 0; 
    }

    function maxRedeem(address /*owner*/) public pure override returns (uint256) {
        return 0;
    }

    function withdraw(uint256, address, address) public pure override returns (uint256) {
        revert("Use requestRedeem for async withdrawal");
    }

    function redeem(uint256, address, address) public pure override returns (uint256) {
        revert("Use requestRedeem for async redemption");
    }
}