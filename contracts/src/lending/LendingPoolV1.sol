// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {PositionNFT} from "../tokens/PositionNFT.sol";

contract LendingPoolV1 is Initializable, UUPSUpgradeable, OwnableUpgradeable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant BPS = 10_000;
    uint256 public constant WAD = 1e18;
    uint256 public constant SECONDS_PER_YEAR = 365 days;

    struct Position {
        uint256 collateral;
        uint256 debt;
        uint256 lastAccrued;
    }

    struct AssetConfig {
        address feed;
        uint256 ltvBps;
        bool enabled;
    }

    PositionNFT public positionNFT;
    uint256 public baseRateBps;
    uint256 public slopeRateBps;
    uint256 public liquidationBonusBps;

    mapping(address asset => AssetConfig config) public assetConfigs;
    mapping(address asset => uint256 amount) public totalDeposits;
    mapping(address asset => uint256 amount) public totalBorrows;
    mapping(address user => address asset) public primaryDebtAsset;
    mapping(address user => uint256 tokenId) public positionTokenId;
    mapping(address user => mapping(address asset => Position position)) internal _positions;
    mapping(address user => mapping(address asset => bool tracked)) private _isUserAsset;
    mapping(address user => address[] assets) private _userAssets;

    event AssetConfigured(address indexed asset, address indexed feed, uint256 ltvBps, bool enabled);
    event Deposited(address indexed user, address indexed asset, uint256 amount);
    event Borrowed(address indexed user, address indexed asset, uint256 amount, uint256 tokenId);
    event Repaid(address indexed user, address indexed asset, uint256 amount);
    event Liquidated(
        address indexed liquidator,
        address indexed borrower,
        address indexed collateralAsset,
        address debtAsset,
        uint256 debtRepaid,
        uint256 collateralSeized
    );

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address owner_, address positionNFT_) public initializer {
        require(positionNFT_ != address(0), "Zero NFT");
        __Ownable_init(owner_);

        positionNFT = PositionNFT(positionNFT_);
        baseRateBps = 500;
        slopeRateBps = 2_000;
        liquidationBonusBps = 500;
    }

    function setAssetConfig(address asset, address feed, uint256 ltvBps, bool enabled) external onlyOwner {
        require(asset != address(0) && feed != address(0), "Zero address");
        require(ltvBps <= BPS, "Invalid LTV");

        assetConfigs[asset] = AssetConfig({feed: feed, ltvBps: ltvBps, enabled: enabled});

        emit AssetConfigured(asset, feed, ltvBps, enabled);
    }

    function deposit(address asset, uint256 amount) external nonReentrant {
        _requireEnabled(asset);
        require(amount > 0, "Zero amount");

        _trackAsset(msg.sender, asset);
        _positions[msg.sender][asset].collateral += amount;
        totalDeposits[asset] += amount;

        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);

        emit Deposited(msg.sender, asset, amount);
    }

    function borrow(address asset, uint256 amount) external nonReentrant {
        _requireEnabled(asset);
        require(amount > 0, "Zero amount");
        require(IERC20(asset).balanceOf(address(this)) >= amount, "Insufficient liquidity");

        _trackAsset(msg.sender, asset);
        _accrue(msg.sender, asset);

        Position storage position = _positions[msg.sender][asset];
        position.debt += amount;
        position.lastAccrued = block.timestamp;
        totalBorrows[asset] += amount;

        if (primaryDebtAsset[msg.sender] == address(0)) {
            primaryDebtAsset[msg.sender] = asset;
        }

        require(healthFactor(msg.sender) >= WAD, "Health factor too low");

        uint256 tokenId = positionTokenId[msg.sender];
        if (tokenId == 0) {
            tokenId = positionNFT.mint(msg.sender);
            positionTokenId[msg.sender] = tokenId;
        }

        IERC20(asset).safeTransfer(msg.sender, amount);

        emit Borrowed(msg.sender, asset, amount, tokenId);
    }

    function repay(address asset, uint256 amount) external nonReentrant returns (uint256 repaid) {
        _requireEnabled(asset);
        require(amount > 0, "Zero amount");

        uint256 debt = _accrue(msg.sender, asset);
        require(debt > 0, "No debt");

        repaid = Math.min(amount, debt);
        _positions[msg.sender][asset].debt = debt - repaid;
        totalBorrows[asset] -= repaid;

        IERC20(asset).safeTransferFrom(msg.sender, address(this), repaid);

        emit Repaid(msg.sender, asset, repaid);
    }

    function liquidate(address borrower, address collateralAsset, uint256 debtAmount)
        external
        nonReentrant
        returns (uint256 collateralSeized)
    {
        _requireEnabled(collateralAsset);
        require(healthFactor(borrower) < WAD, "Position healthy");
        require(debtAmount > 0, "Zero amount");

        address debtAsset = primaryDebtAsset[borrower];
        require(debtAsset != address(0), "No debt asset");

        uint256 debt = _accrue(borrower, debtAsset);
        uint256 repaid = Math.min(debtAmount, debt);
        uint256 repayValue = _assetValue(debtAsset, repaid);
        uint256 seizeValue = (repayValue * (BPS + liquidationBonusBps)) / BPS;

        collateralSeized = _amountFromValue(collateralAsset, seizeValue);
        collateralSeized = Math.min(collateralSeized, _positions[borrower][collateralAsset].collateral);
        require(collateralSeized > 0, "No collateral");

        _positions[borrower][debtAsset].debt = debt - repaid;
        _positions[borrower][collateralAsset].collateral -= collateralSeized;
        totalBorrows[debtAsset] -= repaid;
        totalDeposits[collateralAsset] -= collateralSeized;

        IERC20(debtAsset).safeTransferFrom(msg.sender, address(this), repaid);
        IERC20(collateralAsset).safeTransfer(msg.sender, collateralSeized);

        emit Liquidated(msg.sender, borrower, collateralAsset, debtAsset, repaid, collateralSeized);
    }

    function healthFactor(address user) public view returns (uint256) {
        (uint256 collateralPowerValue, uint256 debtValue) = accountLiquidity(user);
        if (debtValue == 0) {
            return type(uint256).max;
        }

        return (collateralPowerValue * WAD) / debtValue;
    }

    function accountLiquidity(address user) public view returns (uint256 collateralPowerValue, uint256 debtValue) {
        address[] memory assets = _userAssets[user];

        for (uint256 i = 0; i < assets.length; i++) {
            address asset = assets[i];
            AssetConfig memory config = assetConfigs[asset];
            Position storage position = _positions[user][asset];

            uint256 collateralValue = _assetValue(asset, position.collateral);
            collateralPowerValue += (collateralValue * config.ltvBps) / BPS;
            debtValue += _assetValue(asset, _debtWithInterest(user, asset));
        }
    }

    function positionOf(address user, address asset)
        external
        view
        returns (uint256 collateral, uint256 debt, uint256 debtWithInterest, uint256 lastAccrued)
    {
        Position storage position = _positions[user][asset];
        collateral = position.collateral;
        debt = position.debt;
        debtWithInterest = _debtWithInterest(user, asset);
        lastAccrued = position.lastAccrued;
    }

    function currentInterestRateBps(address asset) public view returns (uint256) {
        if (totalDeposits[asset] == 0) {
            return baseRateBps;
        }

        uint256 utilization = Math.min((totalBorrows[asset] * WAD) / totalDeposits[asset], WAD);
        return baseRateBps + ((utilization * slopeRateBps) / WAD);
    }

    function getUserAssets(address user) external view returns (address[] memory) {
        return _userAssets[user];
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    function _requireEnabled(address asset) internal view {
        require(assetConfigs[asset].enabled, "Asset disabled");
    }

    function _trackAsset(address user, address asset) internal {
        if (!_isUserAsset[user][asset]) {
            _isUserAsset[user][asset] = true;
            _userAssets[user].push(asset);
        }
    }

    function _accrue(address user, address asset) internal returns (uint256 debtWithInterest) {
        Position storage position = _positions[user][asset];
        debtWithInterest = _debtWithInterest(user, asset);

        if (debtWithInterest > position.debt) {
            totalBorrows[asset] += debtWithInterest - position.debt;
            position.debt = debtWithInterest;
        }

        position.lastAccrued = block.timestamp;
    }

    function _debtWithInterest(address user, address asset) internal view returns (uint256) {
        Position storage position = _positions[user][asset];
        if (position.debt == 0) {
            return 0;
        }

        uint256 elapsed = block.timestamp - position.lastAccrued;
        uint256 interest = (position.debt * currentInterestRateBps(asset) * elapsed) / (BPS * SECONDS_PER_YEAR);
        return position.debt + interest;
    }

    function _assetValue(address asset, uint256 amount) internal view returns (uint256) {
        if (amount == 0) {
            return 0;
        }

        AssetConfig memory config = assetConfigs[asset];
        (, int256 answer,, uint256 updatedAt,) = AggregatorV3Interface(config.feed).latestRoundData();
        require(answer > 0, "Invalid price");
        require(updatedAt != 0, "Stale price");

        return (amount * SafeCast.toUint256(answer)) / (10 ** AggregatorV3Interface(config.feed).decimals());
    }

    function _amountFromValue(address asset, uint256 value) internal view returns (uint256) {
        if (value == 0) {
            return 0;
        }

        AssetConfig memory config = assetConfigs[asset];
        (, int256 answer,, uint256 updatedAt,) = AggregatorV3Interface(config.feed).latestRoundData();
        require(answer > 0, "Invalid price");
        require(updatedAt != 0, "Stale price");

        return (value * (10 ** AggregatorV3Interface(config.feed).decimals())) / SafeCast.toUint256(answer);
    }
}
