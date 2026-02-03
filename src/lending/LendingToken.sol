// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ILendingToken} from "../interfaces/ILendingToken.sol";
import {IComptroller} from "../interfaces/IComptroller.sol";
import {IInterestRateModel} from "../interfaces/IInterestRateModel.sol";
import {LendingTokenStorage} from "./LendingTokenStorage.sol";
import {WadRayMath} from "../libraries/WadRayMath.sol";
import {Errors} from "../libraries/Errors.sol";

/**
 * @title LendingToken
 * @notice UUPS upgradeable receipt token for lending pool deposits (Compound-style cToken)
 * @dev Uses ERC-7201 namespaced storage
 */
contract LendingToken is Initializable, UUPSUpgradeable, ERC20Upgradeable, OwnableUpgradeable, ILendingToken {
    using SafeERC20 for IERC20;
    using WadRayMath for uint256;
    using LendingTokenStorage for LendingTokenStorage.Layout;

    /// @notice Emitted when interest is accrued
    event AccrueInterest(
        uint256 cashPrior,
        uint256 interestAccumulated,
        uint256 borrowIndex,
        uint256 totalBorrows
    );

    /// @notice Emitted when tokens are minted
    event Mint(address indexed minter, uint256 mintAmount, uint256 mintTokens);

    /// @notice Emitted when tokens are redeemed
    event Redeem(address indexed redeemer, uint256 redeemAmount, uint256 redeemTokens);

    /// @notice Emitted when underlying is borrowed
    event Borrow(address indexed borrower, uint256 borrowAmount, uint256 accountBorrows, uint256 totalBorrows);

    /// @notice Emitted when a borrow is repaid
    event RepayBorrow(
        address indexed payer,
        address indexed borrower,
        uint256 repayAmount,
        uint256 accountBorrows,
        uint256 totalBorrows
    );

    /// @notice Emitted when a liquidation occurs
    event LiquidateBorrow(
        address indexed liquidator,
        address indexed borrower,
        uint256 repayAmount,
        address indexed cTokenCollateral,
        uint256 seizeTokens
    );

    /// @notice Emitted when reserves are updated
    event ReservesUpdated(uint256 newReserves);

    /// @notice Emitted when reserve factor is updated
    event NewReserveFactor(uint256 oldReserveFactor, uint256 newReserveFactor);

    /// @notice Emitted when interest rate model is updated
    event NewInterestRateModel(address oldModel, address newModel);

    modifier onlyComptroller() {
        if (msg.sender != LendingTokenStorage.layout().comptroller) {
            revert Errors.Unauthorized();
        }
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the lending token
     * @param underlying_ The underlying asset address
     * @param comptroller_ The comptroller address
     * @param interestRateModel_ The interest rate model address
     * @param initialExchangeRateMantissa_ Initial exchange rate (scaled by 1e18)
     * @param name_ Token name
     * @param symbol_ Token symbol
     * @param owner_ Owner address
     */
    function initialize(
        address underlying_,
        address comptroller_,
        address interestRateModel_,
        uint256 initialExchangeRateMantissa_,
        string memory name_,
        string memory symbol_,
        address owner_
    ) external initializer {
        if (underlying_ == address(0)) revert Errors.ZeroAddress();
        if (comptroller_ == address(0)) revert Errors.ZeroAddress();
        if (interestRateModel_ == address(0)) revert Errors.ZeroAddress();
        if (owner_ == address(0)) revert Errors.ZeroAddress();
        if (initialExchangeRateMantissa_ == 0) revert Errors.ZeroAmount();

        __ERC20_init(name_, symbol_);
        __Ownable_init(owner_);

        LendingTokenStorage.Layout storage $ = LendingTokenStorage.layout();
        $.version = 1;
        $.underlying = underlying_;
        $.comptroller = comptroller_;
        $.interestRateModel = interestRateModel_;
        $.initialExchangeRateMantissa = initialExchangeRateMantissa_;
        $.accrualBlockTimestamp = block.timestamp;
        $.borrowIndex = WadRayMath.WAD;
        $.reserveFactorMantissa = 0.1e18; // 10% default reserve factor
    }

    /**
     * @inheritdoc ILendingToken
     */
    function underlying() external view returns (address) {
        return LendingTokenStorage.layout().underlying;
    }

    /**
     * @inheritdoc ILendingToken
     */
    function comptroller() external view returns (address) {
        return LendingTokenStorage.layout().comptroller;
    }

    /**
     * @inheritdoc ILendingToken
     */
    function interestRateModel() external view returns (address) {
        return LendingTokenStorage.layout().interestRateModel;
    }

    /**
     * @inheritdoc ILendingToken
     */
    function reserveFactorMantissa() external view returns (uint256) {
        return LendingTokenStorage.layout().reserveFactorMantissa;
    }

    /**
     * @inheritdoc ILendingToken
     */
    function accrualBlockTimestamp() external view returns (uint256) {
        return LendingTokenStorage.layout().accrualBlockTimestamp;
    }

    /**
     * @inheritdoc ILendingToken
     */
    function borrowIndex() external view returns (uint256) {
        return LendingTokenStorage.layout().borrowIndex;
    }

    /**
     * @inheritdoc ILendingToken
     */
    function totalBorrows() external view returns (uint256) {
        return LendingTokenStorage.layout().totalBorrows;
    }

    /**
     * @inheritdoc ILendingToken
     */
    function totalReserves() external view returns (uint256) {
        return LendingTokenStorage.layout().totalReserves;
    }

    /**
     * @inheritdoc ILendingToken
     */
    function getCash() public view returns (uint256) {
        return IERC20(LendingTokenStorage.layout().underlying).balanceOf(address(this));
    }

    /**
     * @inheritdoc ILendingToken
     */
    function exchangeRateStored() public view returns (uint256) {
        LendingTokenStorage.Layout storage $ = LendingTokenStorage.layout();
        uint256 _totalSupply = totalSupply();

        if (_totalSupply == 0) {
            return $.initialExchangeRateMantissa;
        }

        // exchangeRate = (totalCash + totalBorrows - totalReserves) / totalSupply
        uint256 totalCash = getCash();
        uint256 cashPlusBorrowsMinusReserves = totalCash + $.totalBorrows - $.totalReserves;
        return cashPlusBorrowsMinusReserves.wadDiv(_totalSupply);
    }

    /**
     * @inheritdoc ILendingToken
     */
    function exchangeRate() public returns (uint256) {
        accrueInterest();
        return exchangeRateStored();
    }

    /**
     * @inheritdoc ILendingToken
     */
    function accrueInterest() public {
        LendingTokenStorage.Layout storage $ = LendingTokenStorage.layout();

        uint256 currentTimestamp = block.timestamp;
        uint256 accrualTimestampPrior = $.accrualBlockTimestamp;

        if (currentTimestamp == accrualTimestampPrior) {
            return;
        }

        uint256 cashPrior = getCash();
        uint256 borrowsPrior = $.totalBorrows;
        uint256 reservesPrior = $.totalReserves;
        uint256 borrowIndexPrior = $.borrowIndex;

        // Calculate borrow rate
        uint256 borrowRatePerSecond = IInterestRateModel($.interestRateModel).getBorrowRate(
            cashPrior,
            borrowsPrior,
            reservesPrior
        );

        // Calculate time elapsed
        uint256 timeElapsed = currentTimestamp - accrualTimestampPrior;

        // Calculate interest accumulated
        uint256 simpleInterestFactor = borrowRatePerSecond * timeElapsed;
        uint256 interestAccumulated = simpleInterestFactor.wadMul(borrowsPrior);

        // Update state
        $.totalBorrows = borrowsPrior + interestAccumulated;
        $.totalReserves = reservesPrior + interestAccumulated.wadMul($.reserveFactorMantissa);
        $.borrowIndex = borrowIndexPrior + simpleInterestFactor.wadMul(borrowIndexPrior);
        $.accrualBlockTimestamp = currentTimestamp;

        emit AccrueInterest(cashPrior, interestAccumulated, $.borrowIndex, $.totalBorrows);
    }

    /**
     * @inheritdoc ILendingToken
     */
    function mint(uint256 mintAmount) external returns (uint256) {
        _requireNotPaused();

        LendingTokenStorage.Layout storage $ = LendingTokenStorage.layout();
        accrueInterest();
        IComptroller($.comptroller).mintAllowed(address(this), msg.sender, mintAmount);

        // Calculate exchange rate BEFORE transfer to prevent donation attacks
        uint256 exchangeRateMantissa = exchangeRateStored();
        uint256 mintTokens = mintAmount.wadDiv(exchangeRateMantissa);

        // Transfer underlying from sender
        IERC20($.underlying).safeTransferFrom(msg.sender, address(this), mintAmount);

        // Mint cTokens to recipient
        _mint(msg.sender, mintTokens);

        emit Mint(msg.sender, mintAmount, mintTokens);
        return mintTokens;
    }

    /**
     * @inheritdoc ILendingToken
     */
    function mint(address payer, address onBehalfOf, uint256 mintAmount)
        external
        onlyComptroller
        returns (uint256)
    {
        _requireNotPaused();
        if (payer == address(0) || onBehalfOf == address(0)) revert Errors.ZeroAddress();

        LendingTokenStorage.Layout storage $ = LendingTokenStorage.layout();
        accrueInterest();
        IComptroller($.comptroller).mintAllowed(address(this), onBehalfOf, mintAmount);

        // Calculate exchange rate BEFORE transfer to prevent donation attacks
        uint256 exchangeRateMantissa = exchangeRateStored();
        uint256 mintTokens = mintAmount.wadDiv(exchangeRateMantissa);

        // Transfer underlying from payer
        IERC20($.underlying).safeTransferFrom(payer, address(this), mintAmount);

        // Mint cTokens to recipient
        _mint(onBehalfOf, mintTokens);

        emit Mint(payer, mintAmount, mintTokens);
        return mintTokens;
    }

    /**
     * @inheritdoc ILendingToken
     */
    function redeem(uint256 redeemTokens) external returns (uint256) {
        _requireNotPaused();

        accrueInterest();
        IComptroller(LendingTokenStorage.layout().comptroller).redeemAllowed(
            address(this),
            msg.sender,
            redeemTokens
        );

        // Calculate underlying amount
        uint256 exchangeRateMantissa = exchangeRateStored();
        uint256 redeemAmount = redeemTokens.wadMul(exchangeRateMantissa);

        // Check liquidity
        if (redeemAmount > getCash()) revert Errors.InsufficientLiquidity();

        // Burn cTokens from sender
        _burn(msg.sender, redeemTokens);

        // Transfer underlying to recipient
        IERC20(LendingTokenStorage.layout().underlying).safeTransfer(msg.sender, redeemAmount);

        emit Redeem(msg.sender, redeemAmount, redeemTokens);
        return redeemAmount;
    }

    /**
     * @inheritdoc ILendingToken
     */
    function redeem(address from, address to, uint256 redeemTokens)
        external
        onlyComptroller
        returns (uint256)
    {
        _requireNotPaused();
        if (from == address(0) || to == address(0)) revert Errors.ZeroAddress();

        accrueInterest();
        IComptroller(LendingTokenStorage.layout().comptroller).redeemAllowed(
            address(this),
            from,
            redeemTokens
        );

        // Calculate underlying amount
        uint256 exchangeRateMantissa = exchangeRateStored();
        uint256 redeemAmount = redeemTokens.wadMul(exchangeRateMantissa);

        // Check liquidity
        if (redeemAmount > getCash()) revert Errors.InsufficientLiquidity();

        // Burn cTokens from sender
        _burn(from, redeemTokens);

        // Transfer underlying to recipient
        IERC20(LendingTokenStorage.layout().underlying).safeTransfer(to, redeemAmount);

        emit Redeem(from, redeemAmount, redeemTokens);
        return redeemAmount;
    }

    /**
     * @inheritdoc ILendingToken
     */
    function redeemUnderlying(uint256 redeemAmount) external returns (uint256) {
        _requireNotPaused();

        accrueInterest();

        // Calculate tokens to burn
        uint256 exchangeRateMantissa = exchangeRateStored();
        uint256 redeemTokens = redeemAmount.wadDiv(exchangeRateMantissa);

        IComptroller(LendingTokenStorage.layout().comptroller).redeemAllowed(
            address(this),
            msg.sender,
            redeemTokens
        );

        // Check liquidity
        if (redeemAmount > getCash()) revert Errors.InsufficientLiquidity();

        // Burn cTokens from sender
        _burn(msg.sender, redeemTokens);

        // Transfer underlying to recipient
        IERC20(LendingTokenStorage.layout().underlying).safeTransfer(msg.sender, redeemAmount);

        emit Redeem(msg.sender, redeemAmount, redeemTokens);
        return redeemTokens;
    }

    /**
     * @inheritdoc ILendingToken
     */
    function borrow(uint256 borrowAmount) external {
        _requireNotPaused();

        LendingTokenStorage.Layout storage $ = LendingTokenStorage.layout();
        accrueInterest();
        IComptroller($.comptroller).borrowAllowed(address(this), msg.sender, borrowAmount);

        // Check liquidity
        if (borrowAmount > getCash()) revert Errors.InsufficientLiquidity();

        // Get current borrow balance
        uint256 accountBorrowsPrev = _borrowBalanceStoredInternal(msg.sender);
        uint256 accountBorrowsNew = accountBorrowsPrev + borrowAmount;
        uint256 totalBorrowsNew = $.totalBorrows + borrowAmount;

        // Update account borrows
        $.accountBorrows[msg.sender].principal = accountBorrowsNew;
        $.accountBorrows[msg.sender].interestIndex = $.borrowIndex;
        $.totalBorrows = totalBorrowsNew;

        // Transfer underlying to borrower
        IERC20($.underlying).safeTransfer(msg.sender, borrowAmount);

        emit Borrow(msg.sender, borrowAmount, accountBorrowsNew, totalBorrowsNew);
    }

    /**
     * @inheritdoc ILendingToken
     */
    function borrow(address borrower, uint256 borrowAmount) external onlyComptroller {
        _requireNotPaused();
        if (borrower == address(0)) revert Errors.ZeroAddress();

        LendingTokenStorage.Layout storage $ = LendingTokenStorage.layout();
        accrueInterest();
        IComptroller($.comptroller).borrowAllowed(address(this), borrower, borrowAmount);

        // Check liquidity
        if (borrowAmount > getCash()) revert Errors.InsufficientLiquidity();

        // Get current borrow balance
        uint256 accountBorrowsPrev = _borrowBalanceStoredInternal(borrower);
        uint256 accountBorrowsNew = accountBorrowsPrev + borrowAmount;
        uint256 totalBorrowsNew = $.totalBorrows + borrowAmount;

        // Update account borrows
        $.accountBorrows[borrower].principal = accountBorrowsNew;
        $.accountBorrows[borrower].interestIndex = $.borrowIndex;
        $.totalBorrows = totalBorrowsNew;

        // Transfer underlying to borrower
        IERC20($.underlying).safeTransfer(borrower, borrowAmount);

        emit Borrow(borrower, borrowAmount, accountBorrowsNew, totalBorrowsNew);
    }

    /**
     * @inheritdoc ILendingToken
     */
    function repayBorrow(uint256 repayAmount) external returns (uint256) {
        _requireNotPaused();

        IComptroller(LendingTokenStorage.layout().comptroller).repayBorrowAllowed(
            address(this),
            msg.sender,
            msg.sender,
            repayAmount
        );

        accrueInterest();
        return _repayBorrowFresh(msg.sender, msg.sender, repayAmount);
    }

    /**
     * @inheritdoc ILendingToken
     */
    function repayBorrow(address payer, address borrower, uint256 repayAmount)
        external
        onlyComptroller
        returns (uint256)
    {
        _requireNotPaused();
        if (payer == address(0) || borrower == address(0)) revert Errors.ZeroAddress();

        IComptroller(LendingTokenStorage.layout().comptroller).repayBorrowAllowed(
            address(this),
            payer,
            borrower,
            repayAmount
        );

        accrueInterest();
        return _repayBorrowFresh(payer, borrower, repayAmount);
    }

    /**
     * @inheritdoc ILendingToken
     */
    function repayBorrowBehalf(address borrower, uint256 repayAmount) external returns (uint256) {
        _requireNotPaused();

        IComptroller(LendingTokenStorage.layout().comptroller).repayBorrowAllowed(
            address(this),
            msg.sender,
            borrower,
            repayAmount
        );

        accrueInterest();
        return _repayBorrowFresh(msg.sender, borrower, repayAmount);
    }

    /**
     * @inheritdoc ILendingToken
     */
    function liquidateBorrow(address borrower, uint256 repayAmount, address cTokenCollateral)
        external
        returns (uint256 seizeTokens)
    {
        _requireNotPaused();

        if (borrower == msg.sender) revert Errors.SelfLiquidation();

        LendingTokenStorage.Layout storage $ = LendingTokenStorage.layout();
        IComptroller comptroller_ = IComptroller($.comptroller);

        accrueInterest();
        ILendingToken(cTokenCollateral).accrueInterest();

        comptroller_.liquidateBorrowAllowed(
            address(this),
            cTokenCollateral,
            msg.sender,
            borrower,
            repayAmount
        );

        uint256 actualRepayAmount = _repayBorrowFresh(msg.sender, borrower, repayAmount);
        seizeTokens = comptroller_.liquidateCalculateSeizeTokens(address(this), cTokenCollateral, actualRepayAmount);

        ILendingToken(cTokenCollateral).seize(msg.sender, borrower, seizeTokens);

        emit LiquidateBorrow(msg.sender, borrower, actualRepayAmount, cTokenCollateral, seizeTokens);
    }

    /**
     * @inheritdoc ILendingToken
     */
    function borrowBalanceStored(address account) external view returns (uint256) {
        return _borrowBalanceStoredInternal(account);
    }

    /**
     * @inheritdoc ILendingToken
     */
    function borrowBalanceCurrent(address account) external returns (uint256) {
        accrueInterest();
        return _borrowBalanceStoredInternal(account);
    }

    /**
     * @inheritdoc ILendingToken
     */
    function totalBorrowsCurrent() external returns (uint256) {
        accrueInterest();
        return LendingTokenStorage.layout().totalBorrows;
    }

    /**
     * @inheritdoc ILendingToken
     */
    function seize(address liquidator, address borrower, uint256 seizeTokens) external {
        _requireNotPaused();

        IComptroller(LendingTokenStorage.layout().comptroller).seizeAllowed(
            address(this),
            msg.sender,
            liquidator,
            borrower,
            seizeTokens
        );

        // Transfer cTokens from borrower to liquidator
        _transfer(borrower, liquidator, seizeTokens);
    }

    /**
     * @inheritdoc ILendingToken
     */
    function setReserveFactor(uint256 newReserveFactorMantissa) external onlyOwner {
        accrueInterest();

        if (newReserveFactorMantissa > WadRayMath.WAD) revert Errors.InvalidReserveFactor();

        LendingTokenStorage.Layout storage $ = LendingTokenStorage.layout();
        uint256 oldReserveFactor = $.reserveFactorMantissa;
        $.reserveFactorMantissa = newReserveFactorMantissa;

        emit NewReserveFactor(oldReserveFactor, newReserveFactorMantissa);
    }

    /**
     * @inheritdoc ILendingToken
     */
    function setInterestRateModel(address newInterestRateModel) external onlyOwner {
        if (newInterestRateModel == address(0)) revert Errors.InvalidInterestRateModel();

        accrueInterest();

        LendingTokenStorage.Layout storage $ = LendingTokenStorage.layout();
        address oldModel = $.interestRateModel;
        $.interestRateModel = newInterestRateModel;

        emit NewInterestRateModel(oldModel, newInterestRateModel);
    }

    /**
     * @notice Returns the contract version
     */
    function version() external view returns (uint256) {
        return LendingTokenStorage.layout().version;
    }

    /**
     * @notice Internal function to get stored borrow balance
     */
    function _borrowBalanceStoredInternal(address account) internal view returns (uint256) {
        LendingTokenStorage.Layout storage $ = LendingTokenStorage.layout();
        LendingTokenStorage.BorrowSnapshot storage borrowSnapshot = $.accountBorrows[account];

        if (borrowSnapshot.principal == 0) {
            return 0;
        }

        // Calculate: principal * borrowIndex / borrowSnapshot.interestIndex
        return borrowSnapshot.principal.wadMul($.borrowIndex).wadDiv(borrowSnapshot.interestIndex);
    }

    function _repayBorrowFresh(address payer, address borrower, uint256 repayAmount) internal returns (uint256) {
        LendingTokenStorage.Layout storage $ = LendingTokenStorage.layout();

        // Get current borrow balance
        uint256 accountBorrowsPrev = _borrowBalanceStoredInternal(borrower);

        // Calculate actual repay amount
        uint256 actualRepayAmount;
        if (repayAmount == type(uint256).max) {
            actualRepayAmount = accountBorrowsPrev;
        } else {
            actualRepayAmount = repayAmount > accountBorrowsPrev ? accountBorrowsPrev : repayAmount;
        }

        // Transfer underlying from payer
        IERC20($.underlying).safeTransferFrom(payer, address(this), actualRepayAmount);

        // Update account borrows
        uint256 accountBorrowsNew = accountBorrowsPrev - actualRepayAmount;
        uint256 totalBorrowsNew = $.totalBorrows - actualRepayAmount;

        $.accountBorrows[borrower].principal = accountBorrowsNew;
        $.accountBorrows[borrower].interestIndex = $.borrowIndex;
        $.totalBorrows = totalBorrowsNew;

        emit RepayBorrow(payer, borrower, actualRepayAmount, accountBorrowsNew, totalBorrowsNew);
        return actualRepayAmount;
    }

    function _requireNotPaused() internal view {
        if (IComptroller(LendingTokenStorage.layout().comptroller).paused()) {
            revert Errors.Paused();
        }
    }

    /**
     * @notice Authorizes an upgrade
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {
        if (newImplementation == address(0)) revert Errors.InvalidImplementation();
        LendingTokenStorage.layout().version++;
    }
}
