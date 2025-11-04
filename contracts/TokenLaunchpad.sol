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
 * @dev Key features:
 *      - Hyperbolic price curve:
 *            price(s) = minPrice + (maxPrice - minPrice) * s / (scale + s)
 *      - Users pay the *average* price between `s` and `s + amount` for their purchase.
 *      - Basic vesting: immediate percent released, remainder vested linearly in monthly steps.
 *      - Uses OpenZeppelin `SafeERC20`, `Ownable`, and `ReentrancyGuard`.
 *
 *      NOTE: This contract contains no pause, blacklist, or oracle. Owner controls key params
 *      and can withdraw collected payment tokens and unsold sale tokens after the sale ends.
 */
contract TokenLaunchpad is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ┏━━━━━━━━━━━━━━━━━━━━━━━━┓
    // ┃       Constants        ┃
    // ┗━━━━━━━━━━━━━━━━━━━━━━━━┛

    /// @notice Number of seconds considered one month for vesting math (30 days)
    uint256 public constant MONTH_IN_SECONDS = 30 days;

    /// @notice price / payment token precision (USDC = 18 decimals)
    uint256 public constant PRICE_PRECISION = 1e18;

    /// @notice sale token decimals (token is expected to be 18 decimals)
    uint256 public constant TOKEN_DECIMALS = 1e18;

    // ┏━━━━━━━━━━━━━━━━━━━━━━━━┓
    // ┃         Structs        ┃
    // ┗━━━━━━━━━━━━━━━━━━━━━━━━┛

    /**
     * @notice Stores per-account purchase & claim state
     * @param totalTokens Total tokens purchased (18 decimals)
     * @param claimed Total tokens already claimed (18 decimals)
     * @param lastClaimTime Timestamp of the last claim (seconds)
     */
    struct Purchase {
        uint256 totalTokens;
        uint256 claimed;
        uint256 lastClaimTime;
    }

    /**
     * @notice Vesting configuration
     * @param immediateReleasePercent Percentage (0-100) released immediately after sale end
     * @param vestingDuration Vesting duration in months for the remaining tokens
     */
    struct VestingParameter {
        uint256 immediateReleasePercent;
        uint256 vestingDuration;
    }

    /**
     * @notice Core launchpad parameters
     * @param startTime Sale start timestamp (seconds)
     * @param endTime Sale end timestamp (seconds)
     * @param maxTokenForSale Maximum tokens available for sale (18 decimals)
     * @param tokenSold Number of tokens sold so far (18 decimals)
     * @param minPrice Minimum price / floor (in payment token decimals, e.g. USDC 6 decimals)
     * @param maxPrice Asymptotic maximum price (in payment token decimals)
     * @param scaleFactor Scale factor `k` used in hyperbolic formula (18-decimal tokens)
     */
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

    /// @notice Token being sold (PECUNITY)
    IERC20 public saleToken;

    /// @notice Payment token (expected USDC-like with 6 decimals)
    IERC20 public paymentToken;

    /// @notice Launch parameters (see TokenLaunchpadParameter)
    TokenLaunchpadParameter public launchpadParams;

    /// @notice Vesting parameters
    VestingParameter public vestingParams;

    /// @notice Mapping of buyer => purchase info
    mapping(address account => Purchase purchaseInfo) public purchases;

    // ┏━━━━━━━━━━━━━━━━━━━━━━━┓
    // ┃         Events        ┃
    // ┗━━━━━━━━━━━━━━━━━━━━━━━┛

    /**
     * @notice Emitted when sale is initialized and tokens are deposited
     * @param params The `TokenLaunchpadParameter` struct after initialization
     */
    event SaleInitialized(TokenLaunchpadParameter params);

    /**
     * @notice Emitted when a buyer purchases tokens
     * @param buyer Address of purchaser
     * @param tokenAmount Number of tokens purchased (18 decimals)
     * @param startPrice Token price at start of the purchase (payment token decimals)
     * @param endPrice Token price at end of the purchase (payment token decimals)
     * @param averagePrice Average token price used for this purchase (payment token decimals)
     * @param usdcAmount Payment amount transferred (payment token decimals)
     */
    event TokensPurchased(
        address indexed buyer,
        uint256 tokenAmount,
        uint256 startPrice,
        uint256 endPrice,
        uint256 averagePrice,
        uint256 usdcAmount
    );

    /**
     * @notice Emitted when a buyer claims tokens
     * @param buyer Address claiming tokens
     * @param amount Amount of tokens claimed (18 decimals)
     */
    event TokensClaimed(address indexed buyer, uint256 amount);

    /**
     * @notice Emitted when sale tokens are deposited by owner during initialization
     * @param amount Amount deposited (18 decimals)
     */
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

    /**
     * @notice Construct the launchpad
     * @param _saleToken Address of the token being sold (must be ERC20)
     * @param _paymentToken Address of the payment token (USDC-like ERC20)
     * @param _minPrice Minimum price per token (payment token decimals)
     * @param _maxPrice Asymptotic maximum price per token (payment token decimals)
     * @param _scaleFactor Scale parameter `k` used by the bonding curve
     * @param _immediateReleasePercent Percent released immediately after sale (0-100)
     * @param _vestingDuration Vesting duration in months for the remaining tokens
     */
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

    /**
     * @notice Initialize the sale period and deposit `maxTokensForSale` to the contract.
     * @dev Owner must `approve` the contract to transfer `maxTokensForSale` before calling.
     * @param startTime Sale start timestamp (seconds)
     * @param endTime Sale end timestamp (seconds)
     * @param maxTokensForSale Amount of sale tokens to deposit for sale (18 decimals)
     */
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
     * @notice Withdraw collected payment tokens (USDC) to owner.
     * @dev Only callable by owner.
     */
    function withdrawPaymentTokens() external onlyOwner {
        uint256 balance = paymentToken.balanceOf(address(this));
        require(balance > 0, "No USDC to withdraw");
        paymentToken.safeTransfer(owner(), balance);
    }

    /**
     * @notice Withdraw any unsold sale tokens after the sale ends.
     * @dev Only callable by owner after `endTime`.
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
     * @notice Buy `tokenAmount` of sale tokens by paying with `paymentToken`.
     * @dev The buyer pays the average price between current supply and supply + tokenAmount.
     *      This function does not refund excess `paymentToken` — the exact calculated cost must be provided.
     * @param tokenAmount Number of sale tokens to purchase (18 decimals)
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
     * @notice Claim available vested tokens after sale end.
     * @dev First claim releases `vestingParams.immediateReleasePercent` of totalTokens.
     *      Remaining tokens vest monthly over `vestingParams.vestingDuration` months.
     *      The function uses `getClaimableAmount` to determine claimable tokens.
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

    // ┏━━━━━━━━━━━━━━━━━━━━━━━━┓
    // ┃     View Functions     ┃
    // ┗━━━━━━━━━━━━━━━━━━━━━━━━┛

    /**
     * @notice Calculate current token price using hyperbolic bonding curve.
     * @dev price = minPrice + (maxPrice - minPrice) * currentSupply / (scale + currentSupply)
     * @param currentSupply Current number of tokens sold (18 decimals)
     * @return price Price per token in payment token decimals (e.g. USDC 6 decimals)
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
     * @notice Calculate cost for buying `amount` tokens using average-price method.
     * @dev Returns (startPrice, endPrice, averagePrice, totalCost)
     * @param amount Amount of tokens to buy (18 decimals)
     * @return startPrice Price at start of purchase (payment token decimals)
     * @return endPrice Price at end of purchase (payment token decimals)
     * @return averagePrice Average price used for calculation (payment token decimals)
     * @return totalCost Total cost in payment token units (e.g. USDC 6 decimals)
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
        // amount (18 decimals) × averagePrice (18 decimals) / 1e18 = cost (18 decimals)
        totalCost = (amount * averagePrice) / TOKEN_DECIMALS;

        return (startPrice, endPrice, averagePrice, totalCost);
    }

    /**
     * @notice Calculate claimable tokens for a given `user` at current time.
     * @param user Address of purchaser
     * @return claimable Amount of tokens that can be claimed right now (18 decimals)
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
     * @notice Get purchase information for a user.
     * @param user Address to query
     * @return totalTokens Total purchased tokens (18 decimals)
     * @return claimed Already claimed tokens (18 decimals)
     * @return claimable Tokens currently claimable (18 decimals)
     * @return lastClaimTime Timestamp of last claim
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
     * @notice Get current sale parameters.
     * @return TokenLaunchpadParameter struct representing sale configuration and state.
     */
    function getSaleParameters()
        external
        view
        returns (TokenLaunchpadParameter memory)
    {
        return launchpadParams;
    }

    /**
     * @notice Get vesting parameters.
     * @return VestingParameter struct representing vesting configuration.
     */
    function getVestingParameter()
        external
        view
        returns (VestingParameter memory)
    {
        return vestingParams;
    }

    /**
     * @notice Get remaining tokens available for sale.
     * @return Number of tokens still available (18 decimals)
     */
    function getRemainingTokens() external view returns (uint256) {
        return launchpadParams.maxTokenForSale - launchpadParams.tokenSold;
    }

    /**
     * @notice Check if sale is currently active.
     * @return True if now is between startTime and endTime (inclusive).
     */
    function isSaleActive() external view returns (bool) {
        return
            block.timestamp >= launchpadParams.startTime &&
            block.timestamp <= launchpadParams.endTime;
    }
}
