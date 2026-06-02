// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title PaymentRequestWithOracle
 * @notice Like PaymentRequest.sol, but uses a Chainlink ETH/USD price feed
 *         so the payer sends the exact ETH equivalent of $5.40 at payment time.
 *
 * DEPLOYMENT
 * ----------
 * Constructor args:
 *   _payer        — wallet address to request from
 *   _usdCents     — amount in US cents (e.g. 540 = $5.40)
 *   _memo         — note shown with the request
 *   _priceFeed    — Chainlink ETH/USD feed address for your network:
 *                     Ethereum mainnet : 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419
 *                     Sepolia testnet  : 0x694AA1769357215DE4FAC081bf1f309aDC325306
 *                     Arbitrum One     : 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612
 *                     Polygon mainnet  : 0xF9680D99D6C9589e2a93a78A04A279e509205945
 *
 * HOW IT WORKS
 * ------------
 * When pay() is called, the contract:
 *   1. Reads the live ETH/USD price from Chainlink.
 *   2. Computes the exact wei required: (usdCents * 1e18) / (price * 100)
 *   3. Accepts msg.value within a ±1% tolerance to handle price movement
 *      between the time the payer signs and the tx lands.
 *   4. Forwards all sent ETH to the requester (any overpayment goes too).
 *
 * DEPENDENCIES
 * ------------
 * Requires: @chainlink/contracts
 * Install:  npm install @chainlink/contracts
 * Or use the interface directly (AggregatorV3Interface is copied inline below
 * so this file compiles without npm).
 */

interface AggregatorV3Interface {
    function latestRoundData()
        external
        view
        returns (
            uint80  roundId,
            int256  answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80  answeredInRound
        );

    function decimals() external view returns (uint8);
}

contract PaymentRequestWithOracle {

    // ── State ─────────────────────────────────────────────────────────────

    address public immutable requester;
    address public immutable payer;
    uint256 public immutable usdCents;      // e.g. 540 = $5.40
    string  public           memo;
    AggregatorV3Interface public immutable priceFeed;

    /// Maximum age of price data accepted (1 hour). Prevents stale oracle use.
    uint256 public constant MAX_PRICE_AGE = 3600;

    /// Allowed overpayment tolerance: 100 = 1%, 200 = 2%
    uint256 public constant TOLERANCE_BPS = 100;

    enum Status { Pending, Paid, Cancelled }
    Status public status;

    // ── Events ────────────────────────────────────────────────────────────

    event RequestCreated(address indexed requester, address indexed payer, uint256 usdCents, string memo);
    event RequestPaid(address indexed payer, uint256 ethSent, uint256 usdCents);
    event RequestCancelled(address indexed requester);

    // ── Errors ────────────────────────────────────────────────────────────

    error OnlyPayer();
    error OnlyRequester();
    error RequestNotPending();
    error InsufficientPayment(uint256 sent, uint256 minRequired);
    error StaleOraclePrice(uint256 updatedAt, uint256 currentTime);
    error InvalidOraclePrice();

    // ── Constructor ───────────────────────────────────────────────────────

    constructor(
        address _payer,
        uint256 _usdCents,
        string memory _memo,
        address _priceFeed
    ) {
        require(_payer     != address(0), "Invalid payer");
        require(_priceFeed != address(0), "Invalid price feed");
        require(_usdCents  >  0,          "Amount must be > 0");

        requester  = msg.sender;
        payer      = _payer;
        usdCents   = _usdCents;
        memo       = _memo;
        priceFeed  = AggregatorV3Interface(_priceFeed);
        status     = Status.Pending;

        emit RequestCreated(msg.sender, _payer, _usdCents, _memo);
    }

    // ── Core logic ────────────────────────────────────────────────────────

    /**
     * @notice Pay the request. The payer sends ETH; the contract checks that
     *         it covers the USD amount using a live Chainlink price feed.
     *         Any overpayment (within tolerance) is forwarded to the requester.
     */
    function pay() external payable {
        if (msg.sender != payer)      revert OnlyPayer();
        if (status != Status.Pending) revert RequestNotPending();

        uint256 required = requiredWei();

        // Allow up to TOLERANCE_BPS basis points under (price moved since signing)
        uint256 minAccepted = required * (10000 - TOLERANCE_BPS) / 10000;
        if (msg.value < minAccepted) revert InsufficientPayment(msg.value, minAccepted);

        status = Status.Paid;
        emit RequestPaid(msg.sender, msg.value, usdCents);

        (bool ok, ) = requester.call{value: msg.value}("");
        require(ok, "ETH transfer failed");
    }

    /**
     * @notice Cancel the request. Only callable by the requester.
     */
    function cancel() external {
        if (msg.sender != requester)  revert OnlyRequester();
        if (status != Status.Pending) revert RequestNotPending();

        status = Status.Cancelled;
        emit RequestCancelled(msg.sender);
    }

    // ── View helpers ──────────────────────────────────────────────────────

    /**
     * @notice How much ETH (in wei) is needed to pay right now?
     */
    function requiredWei() public view returns (uint256) {
        (, int256 price, , uint256 updatedAt, ) = priceFeed.latestRoundData();

        if (price <= 0) revert InvalidOraclePrice();
        if (block.timestamp - updatedAt > MAX_PRICE_AGE)
            revert StaleOraclePrice(updatedAt, block.timestamp);

        uint8 decimals = priceFeed.decimals(); // typically 8 for ETH/USD
        // Convert: (usdCents / 100) / (price / 10^decimals) * 1e18
        // = (usdCents * 1e18 * 10^decimals) / (100 * price)
        return (usdCents * 1e18 * (10 ** decimals)) / (100 * uint256(price));
    }

    /**
     * @notice Returns USD amount as a string like "5.40"
     */
    function usdAmount() external view returns (string memory) {
        uint256 dollars = usdCents / 100;
        uint256 cents   = usdCents % 100;
        return string(abi.encodePacked(
            _uint2str(dollars), ".",
            cents < 10 ? "0" : "",
            _uint2str(cents)
        ));
    }

    function summary() external view returns (
        address _requester,
        address _payer,
        uint256 _usdCents,
        string  memory _memo,
        Status  _status,
        uint256 _requiredWeiNow
    ) {
        uint256 wei_ = status == Status.Pending ? requiredWei() : 0;
        return (requester, payer, usdCents, memo, status, wei_);
    }

    // ── Internal ──────────────────────────────────────────────────────────

    function _uint2str(uint256 n) internal pure returns (string memory) {
        if (n == 0) return "0";
        uint256 temp = n;
        uint256 digits;
        while (temp != 0) { digits++; temp /= 10; }
        bytes memory buf = new bytes(digits);
        while (n != 0) {
            digits--;
            buf[digits] = bytes1(uint8(48 + n % 10));
            n /= 10;
        }
        return string(buf);
    }
}
