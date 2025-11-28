// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title DeFiLendingProtocol
 * @dev Minimal over‑collateralized ETH lending protocol with a single ERC20 debt asset (IOU-style)
 * @notice Users deposit ETH as collateral and borrow synthetic tokens up to a collateral ratio
 */
interface IERC20 {
    function mint(address to, uint256 amount) external;
    function burnFrom(address account, uint256 amount) external;
    function balanceOf(address account) external view returns (uint256);
}

contract DeFiLendingProtocol {
    address public owner;
    IERC20 public debtToken;          // synthetic debt token
    uint256 public collateralRatioBP; // e.g. 15000 = 150% collateral
    uint256 public liquidationRatioBP;// e.g. 12000 = 120% collateral

    // user => collateral in ETH (wei)
    mapping(address => uint256) public collateralOf;

    // user => debt (in debtToken units)
    mapping(address => uint256) public debtOf;

    event CollateralDeposited(address indexed user, uint256 amount);
    event CollateralWithdrawn(address indexed user, uint256 amount);
    event Borrowed(address indexed user, uint256 amount);
    event Repaid(address indexed user, uint256 amount);
    event Liquidated(address indexed user, address indexed liquidator, uint256 repaidDebt, uint256 collateralTaken);

    event ParamsUpdated(uint256 collateralRatioBP, uint256 liquidationRatioBP);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    constructor(
        address _debtToken,
        uint256 _collateralRatioBP,
        uint256 _liquidationRatioBP
    ) {
        require(_debtToken != address(0), "Zero debt token");
        require(_collateralRatioBP > _liquidationRatioBP, "Collateral ratio > liquidation");
        owner = msg.sender;
        debtToken = IERC20(_debtToken);
        collateralRatioBP = _collateralRatioBP;
        liquidationRatioBP = _liquidationRatioBP;
    }

    /**
     * @dev Deposit ETH as collateral
     */
    function depositCollateral() external payable {
        require(msg.value > 0, "Amount = 0");
        collateralOf[msg.sender] += msg.value;
        emit CollateralDeposited(msg.sender, msg.value);
    }

    /**
     * @dev Withdraw collateral if user remains safely collateralized
     */
    function withdrawCollateral(uint256 amount) external {
        require(amount > 0, "Amount = 0");
        uint256 current = collateralOf[msg.sender];
        require(current >= amount, "Insufficient collateral");

        uint256 newCollateral = current - amount;
        require(_isSafe(newCollateral, debtOf[msg.sender], collateralRatioBP), "Would be under‑collateralized");

        collateralOf[msg.sender] = newCollateral;

        (bool ok, ) = payable(msg.sender).call{value: amount}("");
        require(ok, "Transfer failed");

        emit CollateralWithdrawn(msg.sender, amount);
    }

    /**
     * @dev Borrow debt tokens against ETH collateral
     * @param amount Amount of debt tokens to mint
     */
    function borrow(uint256 amount) external {
        require(amount > 0, "Amount = 0");
        require(collateralOf[msg.sender] > 0, "No collateral");

        uint256 newDebt = debtOf[msg.sender] + amount;
        require(_isSafe(collateralOf[msg.sender], newDebt, collateralRatioBP), "Insufficient collateral");

        debtOf[msg.sender] = newDebt;
        debtToken.mint(msg.sender, amount);

        emit Borrowed(msg.sender, amount);
    }

    /**
     * @dev Repay debt and free up collateral headroom
     * @param amount Amount of debt tokens to burn
     */
    function repay(uint256 amount) external {
        require(amount > 0, "Amount = 0");
        uint256 currentDebt = debtOf[msg.sender];
        require(currentDebt >= amount, "Repay > debt");

        debtOf[msg.sender] = currentDebt - amount;
        debtToken.burnFrom(msg.sender, amount);

        emit Repaid(msg.sender, amount);
    }

    /**
     * @dev Anyone can liquidate an under‑collateralized position by repaying debt and seizing collateral
     * @param user User to liquidate
     * @param repayAmount Amount of debt to repay on behalf of user
     */
    function liquidate(address user, uint256 repayAmount) external {
        require(repayAmount > 0, "Amount = 0");
        uint256 userDebt = debtOf[user];
        require(userDebt >= repayAmount, "Too much repay");

        uint256 col = collateralOf[user];
        require(!_isSafe(col, userDebt, liquidationRatioBP), "Not liquidatable");

        // liquidator must hold enough debt tokens; they are burned
        debtToken.burnFrom(msg.sender, repayAmount);
        debtOf[user] = userDebt - repayAmount;

        // simple rule: liquidator gets collateral equal to repaidAmount (1:1) capped by user's collateral
        uint256 collateralToTake = repayAmount;
        if (collateralToTake > col) {
            collateralToTake = col;
        }

        collateralOf[user] = col - collateralToTake;

        (bool ok, ) = payable(msg.sender).call{value: collateralToTake}("");
        require(ok, "Collateral transfer failed");

        emit Liquidated(user, msg.sender, repayAmount, collateralToTake);
    }

    /**
     * @dev Check if position meets given collateral ratio
     */
    function _isSafe(
        uint256 collateral,
        uint256 debt,
        uint256 ratioBP
    ) internal pure returns (bool) {
        if (debt == 0) return true;
        // collateral * 10000 >= debt * ratioBP
        return collateral * 10000 >= debt * ratioBP;
    }

    /**
     * @dev Owner can update risk parameters
     */
    function updateParams(uint256 _collateralRatioBP, uint256 _liquidationRatioBP) external onlyOwner {
        require(_collateralRatioBP > _liquidationRatioBP, "Collateral ratio > liquidation");
        collateralRatioBP = _collateralRatioBP;
        liquidationRatioBP = _liquidationRatioBP;
        emit ParamsUpdated(_collateralRatioBP, _liquidationRatioBP);
    }

    /**
     * @dev View: total collateral held by protocol
     */
    function getTotalCollateral() external view returns (uint256) {
        return address(this).balance;
    }

    /**
     * @dev Transfer ownership
     */
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Zero address");
        address prev = owner;
        owner = newOwner;
        emit OwnershipTransferred(prev, newOwner);
    }
}
