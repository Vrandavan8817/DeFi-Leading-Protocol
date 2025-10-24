// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title DeFi Lending Protocol (Enhanced)
 * @dev Allows users to deposit assets, earn interest, borrow against collateral,
 * and claim interest. Includes admin controls and global interest tracking.
 */
contract DeFiLendingProtocol is ReentrancyGuard, Ownable {
    IERC20 public token;

    uint256 public constant COLLATERAL_FACTOR = 75; // 75%
    uint256 public constant LIQUIDATION_THRESHOLD = 85; // 85%
    uint256 public constant INTEREST_RATE_BASE = 5; // 5% APR
    bool public isPaused;

    struct UserAccount {
        uint256 deposited;
        uint256 borrowed;
        uint256 lastInterestCalcTime;
        uint256 interestEarned;
    }

    mapping(address => UserAccount) public accounts;

    uint256 public totalDeposits;
    uint256 public totalBorrows;
    uint256 public protocolInterest; // Unclaimed interest
    uint256 public lastGlobalInterestUpdate;

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event Borrow(address indexed user, uint256 amount);
    event Repay(address indexed user, uint256 amount);
    event Liquidate(address indexed liquidator, address indexed borrower, uint256 amount);
    event InterestClaimed(address indexed user, uint256 amount);
    event Paused();
    event Unpaused();

    modifier notPaused() {
        require(!isPaused, "Protocol is paused");
        _;
    }

    constructor(address _token) Ownable(msg.sender) {
        require(_token != address(0), "Invalid token address");
        token = IERC20(_token);
        lastGlobalInterestUpdate = block.timestamp;
    }

    function deposit(uint256 _amount) external nonReentrant notPaused {
        require(_amount > 0, "Amount must be greater than 0");
        _updateInterest(msg.sender);
        require(token.transferFrom(msg.sender, address(this), _amount), "Transfer failed");

        accounts[msg.sender].deposited += _amount;
        totalDeposits += _amount;

        emit Deposit(msg.sender, _amount);
    }

    function withdraw(uint256 _amount) external nonReentrant notPaused {
        require(_amount > 0, "Amount must be greater than 0");
        _updateInterest(msg.sender);

        UserAccount storage account = accounts[msg.sender];
        require(account.deposited >= _amount, "Insufficient balance");

        uint256 maxBorrowableAfterWithdraw = ((account.deposited - _amount) * COLLATERAL_FACTOR) / 100;
        require(account.borrowed <= maxBorrowableAfterWithdraw, "Withdraw would breach collateral ratio");

        account.deposited -= _amount;
        totalDeposits -= _amount;

        require(token.transfer(msg.sender, _amount), "Transfer failed");

        emit Withdraw(msg.sender, _amount);
    }

    function borrow(uint256 _amount) external nonReentrant notPaused {
        require(_amount > 0, "Amount must be greater than 0");
        _updateInterest(msg.sender);

        UserAccount storage account = accounts[msg.sender];
        uint256 maxBorrowable = (account.deposited * COLLATERAL_FACTOR) / 100;
        require(account.borrowed + _amount <= maxBorrowable, "Insufficient collateral");

        account.borrowed += _amount;
        totalBorrows += _amount;

        require(token.transfer(msg.sender, _amount), "Transfer failed");

        emit Borrow(msg.sender, _amount);
    }

    function repay(uint256 _amount) external nonReentrant notPaused {
        require(_amount > 0, "Amount must be greater than 0");
        _updateInterest(msg.sender);

        UserAccount storage account = accounts[msg.sender];
        require(account.borrowed > 0, "No outstanding loans");

        uint256 repayAmount = _amount > account.borrowed ? account.borrowed : _amount;
        require(token.transferFrom(msg.sender, address(this), repayAmount), "Transfer failed");

        // Distribute interest proportionally to depositors
        uint256 interestShare = (repayAmount * totalDeposits) / (totalDeposits + totalBorrows);
        protocolInterest += interestShare;

        account.borrowed -= repayAmount;
        totalBorrows -= repayAmount;

        emit Repay(msg.sender, repayAmount);
    }

    function claimInterest() external nonReentrant {
        UserAccount storage account = accounts[msg.sender];
        require(account.interestEarned > 0, "No interest to claim");

        uint256 amount = account.interestEarned;
        account.interestEarned = 0;

        require(token.transfer(msg.sender, amount), "Transfer failed");
        emit InterestClaimed(msg.sender, amount);
    }

    function accrueInterestGlobal() external {
        for (uint256 i = 0; i < 10; i++) {
            // Placeholder: in real scenario, use an iterable mapping or external indexer
            // to loop over all depositors. Solidity does not support looping through mappings.
            break;
        }

        lastGlobalInterestUpdate = block.timestamp;
    }

    function liquidate(address _borrower) external nonReentrant notPaused {
        uint256 healthFactor = getHealthFactor(_borrower);
        require(healthFactor < LIQUIDATION_THRESHOLD, "Health factor is sufficient");

        UserAccount storage account = accounts[_borrower];
        uint256 repayAmount = account.borrowed;

        require(token.transferFrom(msg.sender, address(this), repayAmount), "Repay transfer failed");

        account.borrowed = 0;
        totalBorrows -= repayAmount;

        uint256 seizedCollateral = account.deposited;
        account.deposited = 0;
        totalDeposits -= seizedCollateral;

        require(token.transfer(msg.sender, seizedCollateral), "Collateral transfer failed");

        emit Liquidate(msg.sender, _borrower, repayAmount);
    }

    function getAccountSummary(address _user) external view returns (
        uint256 deposited,
        uint256 borrowed,
        uint256 interestEarned,
        uint256 healthFactor
    ) {
        UserAccount storage account = accounts[_user];
        deposited = account.deposited;
        borrowed = account.borrowed;
        interestEarned = account.interestEarned;
        healthFactor = getHealthFactor(_user);
    }

    function getHealthFactor(address _user) public view returns (uint256) {
        UserAccount storage account = accounts[_user];
        if (account.borrowed == 0) return type(uint256).max;
        return (account.deposited * 100) / account.borrowed;
    }

    function _updateInterest(address _user) internal {
        UserAccount storage account = accounts[_user];

        if (account.borrowed > 0) {
            uint256 timeElapsed = block.timestamp - account.lastInterestCalcTime;
            if (timeElapsed > 0) {
                uint256 interest = (account.borrowed * INTEREST_RATE_BASE * timeElapsed) / (100 * 365 days);
                account.borrowed += interest;
                totalBorrows += interest;
            }
        }

        // Optional: simulate some interest gain for depositors
        if (account.deposited > 0 && protocolInterest > 0) {
            uint256 share = (account.deposited * protocolInterest) / totalDeposits;
            account.interestEarned += share;
            protocolInterest -= share;
        }

        account.lastInterestCalcTime = block.timestamp;
    }

    // Admin-only emergency controls
    function pause() external onlyOwner {
        isPaused = true;
        emit Paused();
    }

    function unpause() external onlyOwner {
        isPaused = false;
        emit Unpaused();
    }
}
// START
Updated on 2025-10-24
// END
