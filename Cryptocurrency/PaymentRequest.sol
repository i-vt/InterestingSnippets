// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title PaymentRequest
 * @notice Send a payment request to a specific wallet for a fixed ETH amount.
 *         The payer calls pay() to fulfill it. The requester can cancel at any time.
 *
 * USAGE
 * -----
 * 1. Deploy this contract, passing in:
 *      _payer   — the wallet address you're requesting money from
 *      _amount  — the ETH amount in wei (e.g. 0.002 ETH = 2000000000000000)
 *      _memo    — a note like "Dinner reimbursement"
 *
 * 2. Share the deployed contract address with the payer.
 *
 * 3. The payer calls pay() with msg.value == amount.
 *    The ETH is immediately forwarded to you (the requester).
 *
 * NOTE ON $5.40 → ETH CONVERSION
 * --------------------------------
 * ETH's price changes constantly. Before deploying, check the current
 * ETH/USD price and calculate:
 *
 *   ethAmount = 5.40 / <ETH_price_in_USD>
 *
 * Then convert to wei:  weiAmount = ethAmount * 1e18
 *
 * Example (if ETH = $2,700):
 *   ethAmount = 5.40 / 2700 = 0.002 ETH
 *   weiAmount = 0.002 * 1e18 = 2000000000000000
 *
 * For automatic USD→ETH conversion using a live price feed,
 * see PaymentRequestWithOracle.sol.
 */
contract PaymentRequest {

    // ── State ─────────────────────────────────────────────────────────────

    address public immutable requester;   // person who deployed (you)
    address public immutable payer;       // wallet being asked to pay
    uint256 public immutable amount;      // required payment in wei
    string  public           memo;        // human-readable note

    enum Status { Pending, Paid, Cancelled }
    Status public status;

    // ── Events ────────────────────────────────────────────────────────────

    event RequestCreated(address indexed requester, address indexed payer, uint256 amount, string memo);
    event RequestPaid(address indexed payer, uint256 amount);
    event RequestCancelled(address indexed requester);

    // ── Errors ────────────────────────────────────────────────────────────

    error OnlyPayer();
    error OnlyRequester();
    error WrongAmount(uint256 sent, uint256 required);
    error RequestNotPending();

    // ── Constructor ───────────────────────────────────────────────────────

    constructor(address _payer, uint256 _amount, string memory _memo) {
        require(_payer != address(0), "Invalid payer address");
        require(_amount > 0,          "Amount must be > 0");

        requester = msg.sender;
        payer     = _payer;
        amount    = _amount;
        memo      = _memo;
        status    = Status.Pending;

        emit RequestCreated(msg.sender, _payer, _amount, _memo);
    }

    // ── Core logic ────────────────────────────────────────────────────────

    /**
     * @notice Pay the request. Must be called by the designated payer
     *         with exactly the requested ETH amount attached.
     */
    function pay() external payable {
        if (msg.sender != payer)   revert OnlyPayer();
        if (status != Status.Pending) revert RequestNotPending();
        if (msg.value != amount)   revert WrongAmount(msg.value, amount);

        status = Status.Paid;
        emit RequestPaid(msg.sender, msg.value);

        // Forward ETH directly to the requester
        (bool ok, ) = requester.call{value: msg.value}("");
        require(ok, "ETH transfer failed");
    }

    /**
     * @notice Cancel the request. Only the requester can do this.
     */
    function cancel() external {
        if (msg.sender != requester) revert OnlyRequester();
        if (status != Status.Pending) revert RequestNotPending();

        status = Status.Cancelled;
        emit RequestCancelled(msg.sender);
    }

    // ── View helpers ──────────────────────────────────────────────────────

    /**
     * @notice Returns a summary of the request state.
     */
    function summary() external view returns (
        address _requester,
        address _payer,
        uint256 _amount,
        string  memory _memo,
        Status  _status
    ) {
        return (requester, payer, amount, memo, status);
    }
}
