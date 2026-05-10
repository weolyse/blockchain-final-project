// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface ILendingStrategy {
    function deposit(address asset, uint256 amount) external;
    function withdrawCollateral(address asset, uint256 amount) external;
    function positionOf(address user, address asset)
        external
        view
        returns (uint256 collateral, uint256 debt, uint256 debtWithInterest, uint256 lastAccrued);
}

contract YieldVault is ERC4626, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant BPS = 10_000;
    uint256 public constant PERFORMANCE_FEE_BPS = 10;

    ILendingStrategy public immutable lendingPool;
    address public treasury;
    uint256 public totalPerformanceFees;

    event TreasuryUpdated(address indexed treasury);
    event YieldReported(uint256 grossYield, uint256 fee, uint256 netYield);

    constructor(IERC20 asset_, ILendingStrategy lendingPool_, address treasury_, address owner_)
        ERC20("DeFi Super App Vault", "DSV")
        ERC4626(asset_)
        Ownable(owner_)
    {
        require(address(lendingPool_) != address(0), "Zero lending");
        require(treasury_ != address(0), "Zero treasury");

        lendingPool = lendingPool_;
        treasury = treasury_;
        IERC20(asset()).forceApprove(address(lendingPool), type(uint256).max);
    }

    function totalAssets() public view override returns (uint256) {
        (uint256 strategyAssets,,,) = lendingPool.positionOf(address(this), asset());
        return IERC20(asset()).balanceOf(address(this)) + strategyAssets;
    }

    function setTreasury(address treasury_) external onlyOwner {
        require(treasury_ != address(0), "Zero treasury");
        treasury = treasury_;
        emit TreasuryUpdated(treasury_);
    }

    function reportYield(uint256 yieldAmount) external onlyOwner nonReentrant {
        require(yieldAmount > 0, "Zero yield");

        IERC20(asset()).safeTransferFrom(msg.sender, address(this), yieldAmount);

        uint256 fee = (yieldAmount * PERFORMANCE_FEE_BPS) / BPS;
        uint256 netYield = yieldAmount - fee;
        totalPerformanceFees += fee;

        if (fee > 0) {
            IERC20(asset()).safeTransfer(treasury, fee);
        }

        lendingPool.deposit(asset(), netYield);

        emit YieldReported(yieldAmount, fee, netYield);
    }

    function deposit(uint256 assets, address receiver) public override nonReentrant returns (uint256) {
        return super.deposit(assets, receiver);
    }

    function mint(uint256 shares, address receiver) public override nonReentrant returns (uint256) {
        return super.mint(shares, receiver);
    }

    function withdraw(uint256 assets, address receiver, address owner) public override nonReentrant returns (uint256) {
        return super.withdraw(assets, receiver, owner);
    }

    function redeem(uint256 shares, address receiver, address owner) public override nonReentrant returns (uint256) {
        return super.redeem(shares, receiver, owner);
    }

    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal override {
        super._deposit(caller, receiver, assets, shares);
        lendingPool.deposit(asset(), assets);
    }

    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares)
        internal
        override
    {
        uint256 idleAssets = IERC20(asset()).balanceOf(address(this));
        if (idleAssets < assets) {
            lendingPool.withdrawCollateral(asset(), assets - idleAssets);
        }

        super._withdraw(caller, receiver, owner, assets, shares);
    }

    function _decimalsOffset() internal pure override returns (uint8) {
        return 6;
    }
}
