// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
 * ┃                                                                       ┃
 * ┃                            🧱  3 B L O C K S  🧱                      ┃
 * ┃                                                                       ┃
 * ┃                      P E C U N I T Y   T O K E N                      ┃
 * ┃                                                                       ┃
 * ┃     Hyperbolic Bonding Curve Token Sale with Vesting Mechanism        ┃
 * ┃                                                                       ┃
 * ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
 *
 * @title TokenLaunchpad
 * @notice Launchpad contract with hyperbolic bonding curve pricing and vesting mechanism
 *
 * Features:
 * - Hyperbolic price curve: price = startPrice + (endPrice - startPrice) × supply / (scale + supply)
 * - Start price: 0.022 USD (2.2 cents)
 * - End price (asymptote): 0.044 USD (4.4 cents)
 * - Total tokens for sale: 2,500,000 tokens
 * - Payment in USDC (6 decimals)
 * - Users pay average price between start and end of purchase
 * - 25% immediate claim after sale ends
 * - 75% vested monthly over 12 months
 */
contract TokenLaunchpad is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ┏━━━━━━━━━━━━━━━━━━━━━━━━┓
    // ┃       Constants        ┃
    // ┗━━━━━━━━━━━━━━━━━━━━━━━━┛

    uint256 public constant MONTH_IN_SECONDS = 30 days;
    uint256 public constant PRICE_PRECISION = 1e6; // USDC has 6 decimals
    uint256 public constant TOKEN_DECIMALS = 1e18; // ERC20 standard 18 decimals

    // ┏━━━━━━━━━━━━━━━━━━━━━━━━┓
    // ┃         Structs        ┃
    // ┗━━━━━━━━━━━━━━━━━━━━━━━━┛

    struct Purchase {
        uint256 totalTokens;
        uint256 claimed;
        uint256 lastClaimTime;
    }

    struct VestingParameter {
        uint256 immediateReleasePercent;
        uint256 vestingDuration;
    }

    struct TokenLaunchpadParameter {
        uint256 startTime;
        uint256 endTime;
        uint256 maxTokenForSale;
        uint256 tokenSold;
        uint256 minPrice;
        uint256 maxPrice;
        uint256 scaleFactor;
    }

    // ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
    // ┃         State Vars        ┃
    // ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

    IERC20 public saleToken;
    IERC20 public paymentToken;

    TokenLaunchpadParameter public launchpadParams;
    VestingParameter public vestingParams;

    mapping(address account => Purchase purchaseInfo) public purchases;

    // ┏━━━━━━━━━━━━━━━━━━━━━━━┓
    // ┃         Events        ┃
    // ┗━━━━━━━━━━━━━━━━━━━━━━━┛

    event SaleInitialized(TokenLaunchpadParameter params);
    event TokensPurchased(
        address indexed buyer,
        uint256 tokenAmount,
        uint256 startPrice,
        uint256 endPrice,
        uint256 averagePrice,
        uint256 usdcAmount
    );
    event TokensClaimed(address indexed buyer, uint256 amount);
    event TokensDeposited(uint256 amount);

    // ┏━━━━━━━━━━━━━━━━━━━━━━┓
    // ┃        Errors        ┃
    // ┗━━━━━━━━━━━━━━━━━━━━━━┛

    error SaleNotActive();
    error SaleAlreadyActive();
    error SaleNotEnded();
    error InsufficientTokens();
    error InvalidAmount();
    error NoTokensToClaim();
    error SaleNotInitialized();

    // ┏━━━━━━━━━━━━━━━━━━━━━━━━┓
    // ┃     Constructor        ┃
    // ┗━━━━━━━━━━━━━━━━━━━━━━━━┛

    constructor(
        address _saleToken,
        address _paymentToken,
        uint256 _minPrice,
        uint256 _maxPrice,
        uint256 _scaleFactor,
        uint256 _immediateReleasePercent,
        uint256 _vestingDuration
    ) Ownable(msg.sender) {
        require(_saleToken != address(0), "Invalid sale token");
        require(_paymentToken != address(0), "Invalid payment token");
        require(_minPrice > 0, "Invalid min price");
        require(_maxPrice > _minPrice, "Invalid max price");
        require(_scaleFactor > 0, "Invalid scale factor");
        require(
            _immediateReleasePercent <= 100,
            "Invalid immediate release percent"
        );
        require(
            _vestingDuration > 0,
            "Vesting duration must be greater than 0"
        );

        saleToken = IERC20(_saleToken);
        paymentToken = IERC20(_paymentToken);

        launchpadParams = TokenLaunchpadParameter({
            startTime: 0,
            endTime: 0,
            maxTokenForSale: 0,
            tokenSold: 0,
            minPrice: _minPrice,
            maxPrice: _maxPrice,
            scaleFactor: _scaleFactor
        });

        vestingParams = VestingParameter({
            immediateReleasePercent: _immediateReleasePercent,
            vestingDuration: _vestingDuration
        });
    }

    // ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
    // ┃     Admin Functions        ┃
    // ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

    function initializeSale(
        uint256 startTime,
        uint256 endTime,
        uint256 maxTokensForSale
    ) external onlyOwner {
        require(maxTokensForSale > 0, "Amount must be greater than 0");
        saleToken.safeTransferFrom(msg.sender, address(this), maxTokensForSale);

        require(startTime > block.timestamp, "Sale must start in the future");
        require(endTime > startTime, "End time must be after start time");

        launchpadParams.startTime = startTime;
        launchpadParams.endTime = endTime;
        launchpadParams.maxTokenForSale = maxTokensForSale;

        emit SaleInitialized(launchpadParams);
    }

    /**
     * @dev Withdraw USDC collected from sales (only owner)
     */
    function withdrawPaymentTokens() external onlyOwner {
        uint256 balance = paymentToken.balanceOf(address(this));
        require(balance > 0, "No USDC to withdraw");
        paymentToken.safeTransfer(owner(), balance);
    }

    /**
     * @dev Withdraw unsold tokens after sale ends (only owner)
     */
    function withdrawUnsoldTokens() external onlyOwner {
        require(block.timestamp > launchpadParams.endTime, "Sale not ended");
        uint256 unsold = launchpadParams.maxTokenForSale -
            launchpadParams.tokenSold;
        require(unsold > 0, "No unsold tokens");
        saleToken.safeTransfer(owner(), unsold);
    }

    // ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
    // ┃     Public Functions       ┃
    // ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

    /**
     * @dev Purchase tokens with USDC
     * Uses hyperbolic bonding curve for pricing
     * User pays average price between start and end of purchase
     *
     * @param tokenAmount Amount of tokens to purchase (in wei, 18 decimals)
     */
    function buyTokens(uint256 tokenAmount) external nonReentrant {
        require(
            block.timestamp >= launchpadParams.startTime &&
                block.timestamp <= launchpadParams.endTime,
            "Sale not active"
        );
        require(launchpadParams.startTime != 0, "Sale not initialized");
        require(tokenAmount > 0, "Amount must be > 0");
        require(
            launchpadParams.tokenSold + tokenAmount <=
                launchpadParams.maxTokenForSale,
            "Insufficient tokens available"
        );

        // Calculate cost using hyperbolic curve and average price
        (
            uint256 startPrice,
            uint256 endPrice,
            uint256 averagePrice,
            uint256 paymentTokenAmount
        ) = calculatePurchaseCost(tokenAmount);

        require(paymentTokenAmount > 0, "Invalid purchase amount");

        // Transfer USDC from buyer to contract
        paymentToken.safeTransferFrom(
            msg.sender,
            address(this),
            paymentTokenAmount
        );

        // Update state
        launchpadParams.tokenSold += tokenAmount;
        purchases[msg.sender].totalTokens += tokenAmount;

        emit TokensPurchased(
            msg.sender,
            tokenAmount,
            startPrice,
            endPrice,
            averagePrice,
            paymentTokenAmount
        );
    }

    /**
     * @dev Claim available tokens
     * First call claims 25% immediately, subsequent calls claim vested tokens
     */
    function claimTokens() external nonReentrant {
        require(
            block.timestamp > launchpadParams.endTime,
            "Sale not ended yet"
        );

        uint256 claimable = getClaimableAmount(msg.sender);
        require(claimable > 0, "No tokens to claim");

        purchases[msg.sender].claimed += claimable;
        purchases[msg.sender].lastClaimTime = block.timestamp;

        saleToken.safeTransfer(msg.sender, claimable);

        emit TokensClaimed(msg.sender, claimable);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // View Functions
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @dev Calculate current token price using hyperbolic bonding curve
     * Formula: price = minPrice + (maxPrice - minPrice) × supply / (scale + supply)
     *
     * @param currentSupply Current number of tokens sold
     * @return price Price per token in USDC (6 decimals)
     */
    function getCurrentPrice(
        uint256 currentSupply
    ) public view returns (uint256) {
        // Ensure supply doesn't exceed max
        if (currentSupply >= launchpadParams.maxTokenForSale) {
            return launchpadParams.maxPrice;
        }

        uint256 priceRange = launchpadParams.maxPrice -
            launchpadParams.minPrice;
        uint256 denominator = launchpadParams.scaleFactor + currentSupply;

        // price = minPrice + priceRange × supply / (scale + supply)
        uint256 price = launchpadParams.minPrice +
            (priceRange * currentSupply) /
            denominator;

        return price;
    }

    /**
     * @dev Calculate cost for buying tokens using average price method
     * Returns the start price, end price, average price, and total cost in USDC
     *
     * @param amount Amount of tokens to buy (in wei, 18 decimals)
     * @return startPrice Price at start of purchase (USDC 6 decimals)
     * @return endPrice Price at end of purchase (USDC 6 decimals)
     * @return averagePrice Average price for this purchase (USDC 6 decimals)
     * @return totalCost Total cost in USDC (6 decimals)
     */
    function calculatePurchaseCost(
        uint256 amount
    )
        public
        view
        returns (
            uint256 startPrice,
            uint256 endPrice,
            uint256 averagePrice,
            uint256 totalCost
        )
    {
        require(amount > 0, "Amount must be > 0");
        require(
            launchpadParams.tokenSold + amount <=
                launchpadParams.maxTokenForSale,
            "Insufficient tokens"
        );

        // Get price at start and end of this purchase
        startPrice = getCurrentPrice(launchpadParams.tokenSold);
        endPrice = getCurrentPrice(launchpadParams.tokenSold + amount);

        // Calculate average price
        averagePrice = (startPrice + endPrice) / 2;

        // Calculate total cost
        // amount (18 decimals) × averagePrice (6 decimals) / 1e18 = cost (6 decimals)
        totalCost = (amount * averagePrice) / TOKEN_DECIMALS;

        return (startPrice, endPrice, averagePrice, totalCost);
    }

    /**
     * @dev Calculate claimable tokens for a user
     * Includes immediate release (25%) and vested amount
     *
     * @param user Address of the user
     * @return claimable Amount of tokens that can be claimed
     */
    function getClaimableAmount(address user) public view returns (uint256) {
        Purchase memory purchase = purchases[user];

        if (purchase.totalTokens == 0) return 0;
        if (block.timestamp <= launchpadParams.endTime) return 0;

        // Calculate immediate release amount
        uint256 immediateAmount = (purchase.totalTokens *
            vestingParams.immediateReleasePercent) / 100;

        // Calculate vested amount
        uint256 vestingAmount = purchase.totalTokens - immediateAmount;
        uint256 timeElapsed = block.timestamp - launchpadParams.endTime;
        uint256 monthsElapsed = timeElapsed / MONTH_IN_SECONDS;

        // Cap at vesting duration
        if (monthsElapsed > vestingParams.vestingDuration) {
            monthsElapsed = vestingParams.vestingDuration;
        }

        uint256 vestedAmount = (vestingAmount * monthsElapsed) /
            vestingParams.vestingDuration;
        uint256 totalClaimable = immediateAmount + vestedAmount;

        // Subtract already claimed
        uint256 claimable = totalClaimable > purchase.claimed
            ? totalClaimable - purchase.claimed
            : 0;

        return claimable;
    }

    /**
     * @dev Get purchase information for a user
     */
    function getPurchaseInfo(
        address user
    )
        external
        view
        returns (
            uint256 totalTokens,
            uint256 claimed,
            uint256 claimable,
            uint256 lastClaimTime
        )
    {
        Purchase memory purchase = purchases[user];
        return (
            purchase.totalTokens,
            purchase.claimed,
            getClaimableAmount(user),
            purchase.lastClaimTime
        );
    }

    /**
     * @dev Get current sale parameters
     */
    function getSaleParameters()
        external
        view
        returns (TokenLaunchpadParameter memory)
    {
        return launchpadParams;
    }

    function getVestingParameter()
        external
        view
        returns (VestingParameter memory)
    {
        return vestingParams;
    }

    /**
     * @dev Get remaining tokens available for sale
     */
    function getRemainingTokens() external view returns (uint256) {
        return launchpadParams.maxTokenForSale - launchpadParams.tokenSold;
    }

    /**
     * @dev Check if sale is currently active
     */
    function isSaleActive() external view returns (bool) {
        return
            block.timestamp >= launchpadParams.startTime &&
            block.timestamp <= launchpadParams.endTime;
    }
}
