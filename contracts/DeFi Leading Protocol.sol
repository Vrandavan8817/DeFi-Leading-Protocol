// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title DeFi Lending Protocol
 * @dev A simple DeFi lending protocol that allows users to deposit assets for interest
 * and borrow against collateral
 */
contract DeFiLendingProtocol is ReentrancyGuard, Ownable {
    // Token used for lending and borrowing
    IERC20 public token;
    
    // Constants for calculations
    uint256 public constant COLLATERAL_FACTOR = 75; // 75% LTV ratio
    uint256 public constant LIQUIDATION_THRESHOLD = 85; // 85% 
    uint256 public constant INTEREST_RATE_BASE = 5; // 5% base interest rate
    
    // User balances and loan information
    struct UserAccount {
        uint256 deposited;
        uint256 borrowed;
        uint256 lastInterestCalcTime;
    }
    
    mapping(address => UserAccount) public accounts;
    
    // Protocol statistics
    uint256 public totalDeposits;
    uint256 public totalBorrows;
    uint256 public lastGlobalInterestUpdate;
    
    // Events
    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event Borrow(address indexed user, uint256 amount);
    event Repay(address indexed user, uint256 amount);
    event Liquidate(address indexed liquidator, address indexed borrower, uint256 amount);
    
    /**
     * @dev Initialize the contract with the token address
     * @param _token The ERC20 token used for lending and borrowing
     */
    constructor(address _token) Ownable(msg.sender) {
        require(_token != address(0), "Invalid token address");
        token = IERC20(_token);
        lastGlobalInterestUpdate = block.timestamp;
    }
    
    /**
     * @dev Deposit tokens to earn interest
     * @param _amount The amount to deposit
     */
    function deposit(uint256 _amount) external nonReentrant {
        require(_amount > 0, "Amount must be greater than 0");
        
        // Update user's interest
        _updateInterest(msg.sender);
        
        // Transfer tokens from user to contract
        require(token.transferFrom(msg.sender, address(this), _amount), "Transfer failed");
        
        // Update user's deposit
        accounts[msg.sender].deposited += _amount;
        totalDeposits += _amount;
        
        emit Deposit(msg.sender, _amount);
    }
    
    /**
     * @dev Borrow tokens against deposited collateral
     * @param _amount The amount to borrow
     */
    function borrow(uint256 _amount) external nonReentrant {
        require(_amount > 0, "Amount must be greater than 0");
        
        // Update user's interest
        _updateInterest(msg.sender);
        
        UserAccount storage account = accounts[msg.sender];
        
        // Calculate maximum borrowable amount
        uint256 maxBorrowable = (account.deposited * COLLATERAL_FACTOR) / 100;
        require(account.borrowed + _amount <= maxBorrowable, "Insufficient collateral");
        
        // Update user's borrow amount
        account.borrowed += _amount;
        totalBorrows += _amount;
        
        // Transfer tokens to user
        require(token.transfer(msg.sender, _amount), "Transfer failed");
        
        emit Borrow(msg.sender, _amount);
    }
    
    /**
     * @dev Repay borrowed tokens
     * @param _amount The amount to repay
     */
    function repay(uint256 _amount) external nonReentrant {
        require(_amount > 0, "Amount must be greater than 0");
        
        // Update user's interest
        _updateInterest(msg.sender);
        
        UserAccount storage account = accounts[msg.sender];
        require(account.borrowed > 0, "No outstanding loans");
        
        // Cap repayment to outstanding debt
        uint256 repayAmount = _amount > account.borrowed ? account.borrowed : _amount;
        
        // Transfer tokens from user to contract
        require(token.transferFrom(msg.sender, address(this), repayAmount), "Transfer failed");
        
        // Update user's borrow amount
        account.borrowed -= repayAmount;
        totalBorrows -= repayAmount;
        
        emit Repay(msg.sender, repayAmount);
    }
    
    /**
     * @dev Update user's interest
     * @param _user The user address
     */
    function _updateInterest(address _user) internal {
        UserAccount storage account = accounts[_user];
        
        if (account.borrowed > 0) {
            uint256 timeElapsed = block.timestamp - account.lastInterestCalcTime;
            if (timeElapsed > 0) {
                // Simple interest calculation (in practice would be compound)
                uint256 interestRate = INTEREST_RATE_BASE;
                uint256 interest = (account.borrowed * interestRate * timeElapsed) / (100 * 365 days);
                account.borrowed += interest;
                totalBorrows += interest;
            }
        }
        
        account.lastInterestCalcTime = block.timestamp;
    }
    
    /**
     * @dev Get user's current health factor
     * @param _user The user address
     * @return The health factor (scaled by 100)
     */
    function getHealthFactor(address _user) public view returns (uint256) {
        UserAccount storage account = accounts[_user];
        if (account.borrowed == 0) return type(uint256).max; // No borrow, health is perfect
        
        return (account.deposited * 100) / account.borrowed;
    }
}
