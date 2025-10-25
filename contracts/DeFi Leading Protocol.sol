75%
    uint256 public constant LIQUIDATION_THRESHOLD = 85; 5% APR
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
    uint256 public protocolInterest; Distribute interest proportionally to depositors
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
            to loop over all depositors. Solidity does not support looping through mappings.
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

        Admin-only emergency controls
    function pause() external onlyOwner {
        isPaused = true;
        emit Paused();
    }

    function unpause() external onlyOwner {
        isPaused = false;
        emit Unpaused();
    }
}
END
// 
update
// 
