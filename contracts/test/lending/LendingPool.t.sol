// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Test} from "forge-std/Test.sol";
import {LendingPoolV1} from "../../src/lending/LendingPoolV1.sol";
import {LendingPoolV2} from "../../src/lending/LendingPoolV2.sol";
import {PositionNFT} from "../../src/tokens/PositionNFT.sol";
import {MockAggregator} from "../mocks/MockAggregator.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

contract LendingPoolTest is Test {
    LendingPoolV1 private pool;
    PositionNFT private positionNFT;
    MockERC20 private weth;
    MockERC20 private usdc;
    MockAggregator private wethFeed;
    MockAggregator private usdcFeed;

    address private borrower = address(0xB0B);
    address private lender = address(0xA11CE);
    address private liquidator = address(0x1);

    function setUp() public {
        weth = new MockERC20("Wrapped Ether", "WETH");
        usdc = new MockERC20("USD Coin", "USDC");
        wethFeed = new MockAggregator(8, 2_000e8);
        usdcFeed = new MockAggregator(8, 1e8);
        positionNFT = new PositionNFT(address(this));

        LendingPoolV1 implementation = new LendingPoolV1();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation), abi.encodeCall(LendingPoolV1.initialize, (address(this), address(positionNFT)))
        );
        pool = LendingPoolV1(address(proxy));

        positionNFT.grantRole(positionNFT.MINTER_ROLE(), address(pool));
        pool.setAssetConfig(address(weth), address(wethFeed), 7_500, true);
        pool.setAssetConfig(address(usdc), address(usdcFeed), 8_000, true);

        weth.mint(borrower, 100e18);
        usdc.mint(lender, 1_000_000e18);
        usdc.mint(liquidator, 1_000_000e18);

        vm.prank(borrower);
        weth.approve(address(pool), type(uint256).max);

        vm.prank(lender);
        usdc.approve(address(pool), type(uint256).max);

        vm.prank(liquidator);
        usdc.approve(address(pool), type(uint256).max);
    }

    function testInitializeSetsOwnerAndRates() public view {
        assertEq(pool.owner(), address(this));
        assertEq(address(pool.positionNFT()), address(positionNFT));
        assertEq(pool.baseRateBps(), 500);
        assertEq(pool.slopeRateBps(), 2_000);
    }

    function testOnlyOwnerCanSetAssetConfig() public {
        vm.prank(borrower);
        vm.expectRevert();
        pool.setAssetConfig(address(weth), address(wethFeed), 7_000, true);
    }

    function testDepositUpdatesCollateralAndTotals() public {
        _depositWeth(borrower, 10e18);

        (uint256 collateral, uint256 debt,,) = pool.positionOf(borrower, address(weth));
        assertEq(collateral, 10e18);
        assertEq(debt, 0);
        assertEq(pool.totalDeposits(address(weth)), 10e18);
    }

    function testDepositTransfersTokensToPool() public {
        _depositWeth(borrower, 5e18);

        assertEq(weth.balanceOf(address(pool)), 5e18);
        assertEq(weth.balanceOf(borrower), 95e18);
    }

    function testDepositRevertsForDisabledAsset() public {
        MockERC20 disabled = new MockERC20("Disabled", "NOPE");
        disabled.mint(borrower, 1e18);

        vm.startPrank(borrower);
        disabled.approve(address(pool), 1e18);
        vm.expectRevert("Asset disabled");
        pool.deposit(address(disabled), 1e18);
        vm.stopPrank();
    }

    function testBorrowMintsPositionNft() public {
        _seedUsdcLiquidity(100_000e18);
        _depositWeth(borrower, 10e18);

        vm.prank(borrower);
        pool.borrow(address(usdc), 5_000e18);

        uint256 tokenId = pool.positionTokenId(borrower);
        assertEq(tokenId, 1);
        assertEq(positionNFT.ownerOf(tokenId), borrower);
    }

    function testWithdrawCollateral() public {
        _depositWeth(borrower, 5e18);

        vm.prank(borrower);
        pool.withdrawCollateral(address(weth), 2e18);

        (uint256 collateral,,,) = pool.positionOf(borrower, address(weth));
        assertEq(collateral, 3e18);
        assertEq(weth.balanceOf(borrower), 97e18);
    }

    function testBorrowTransfersAssetToBorrower() public {
        _seedUsdcLiquidity(100_000e18);
        _depositWeth(borrower, 10e18);

        vm.prank(borrower);
        pool.borrow(address(usdc), 5_000e18);

        assertEq(usdc.balanceOf(borrower), 5_000e18);
    }

    function testBorrowRevertsWhenHealthFactorTooLow() public {
        _seedUsdcLiquidity(100_000e18);
        _depositWeth(borrower, 1e18);

        vm.prank(borrower);
        vm.expectRevert("Health factor too low");
        pool.borrow(address(usdc), 2_000e18);
    }

    function testHealthFactorMath() public {
        _seedUsdcLiquidity(100_000e18);
        _depositWeth(borrower, 10e18);

        vm.prank(borrower);
        pool.borrow(address(usdc), 5_000e18);

        assertEq(pool.healthFactor(borrower), 3e18);
    }

    function testHealthFactorWithoutDebtIsMax() public {
        _depositWeth(borrower, 1e18);

        assertEq(pool.healthFactor(borrower), type(uint256).max);
    }

    function testRepayReducesDebt() public {
        _openHealthyBorrow(5_000e18);

        vm.prank(borrower);
        usdc.approve(address(pool), type(uint256).max);
        usdc.mint(borrower, 1_000e18);

        vm.prank(borrower);
        uint256 repaid = pool.repay(address(usdc), 1_000e18);

        (,, uint256 debtWithInterest,) = pool.positionOf(borrower, address(usdc));
        assertEq(repaid, 1_000e18);
        assertEq(debtWithInterest, 4_000e18);
    }

    function testRepayCapsAtOutstandingDebt() public {
        _openHealthyBorrow(1_000e18);
        usdc.mint(borrower, 2_000e18);

        vm.prank(borrower);
        usdc.approve(address(pool), type(uint256).max);

        vm.prank(borrower);
        uint256 repaid = pool.repay(address(usdc), 2_000e18);

        (,, uint256 debtWithInterest,) = pool.positionOf(borrower, address(usdc));
        assertEq(repaid, 1_000e18);
        assertEq(debtWithInterest, 0);
    }

    function testFuzz_RepayInterest(uint96 principal, uint256 timeElapsed) public {
        principal = uint96(bound(principal, 1e18, 10_000e18));
        timeElapsed = bound(timeElapsed, 1, 730 days);

        _openHealthyBorrow(principal);
        vm.warp(block.timestamp + timeElapsed);

        (,, uint256 debtBefore,) = pool.positionOf(borrower, address(usdc));
        assertGe(debtBefore, principal);

        usdc.mint(borrower, debtBefore);

        vm.prank(borrower);
        usdc.approve(address(pool), type(uint256).max);

        vm.prank(borrower);
        uint256 repaid = pool.repay(address(usdc), debtBefore);

        (,, uint256 debtAfter,) = pool.positionOf(borrower, address(usdc));
        assertEq(repaid, debtBefore);
        assertEq(debtAfter, 0);
    }

    function testInterestAccruesLinearly() public {
        _openHealthyBorrow(5_000e18);
        vm.warp(block.timestamp + 365 days);

        (,, uint256 debtWithInterest,) = pool.positionOf(borrower, address(usdc));

        assertGt(debtWithInterest, 5_000e18);
    }

    function testCurrentInterestRateUsesUtilization() public {
        _seedUsdcLiquidity(100_000e18);
        assertEq(pool.currentInterestRateBps(address(usdc)), 500);

        _depositWeth(borrower, 10e18);
        vm.prank(borrower);
        pool.borrow(address(usdc), 10_000e18);

        assertEq(pool.currentInterestRateBps(address(usdc)), 700);
    }

    function testLiquidateRevertsWhenHealthy() public {
        _openHealthyBorrow(5_000e18);

        vm.prank(liquidator);
        vm.expectRevert("Position healthy");
        pool.liquidate(borrower, address(weth), 1_000e18);
    }

    function testLiquidateUnhealthyPosition() public {
        _openHealthyBorrow(10_000e18);
        wethFeed.setPrice(1_000e8);

        uint256 liquidatorWethBefore = weth.balanceOf(liquidator);

        vm.prank(liquidator);
        uint256 seized = pool.liquidate(borrower, address(weth), 1_000e18);

        assertEq(seized, 1.05e18);
        assertEq(weth.balanceOf(liquidator), liquidatorWethBefore + seized);

        (uint256 collateral,,,) = pool.positionOf(borrower, address(weth));
        assertEq(collateral, 10e18 - seized);
    }

    function testFuzz_HealthFactor(uint96 collateral, uint96 debt) public {
        collateral = uint96(bound(collateral, 1e18, 50e18));
        uint256 maxDebt = (uint256(collateral) * 2_000 * 7_500) / 10_000;
        debt = uint96(bound(debt, 1e18, maxDebt));

        _seedUsdcLiquidity(1_000_000e18);
        _depositWeth(borrower, collateral);

        vm.prank(borrower);
        pool.borrow(address(usdc), debt);

        assertGe(pool.healthFactor(borrower), 1e18);
    }

    function testUpgradeToV2PreservesStorage() public {
        _openHealthyBorrow(5_000e18);

        LendingPoolV2 v2Implementation = new LendingPoolV2();
        pool.upgradeToAndCall(address(v2Implementation), abi.encodeCall(LendingPoolV2.initializeV2, (25)));
        LendingPoolV2 upgraded = LendingPoolV2(address(pool));

        assertEq(upgraded.owner(), address(this));
        assertEq(upgraded.positionTokenId(borrower), 1);
        assertEq(upgraded.flashLoanFeeBps(), 25);
        assertEq(upgraded.version(), "2");
    }

    function _seedUsdcLiquidity(uint256 amount) private {
        vm.prank(lender);
        pool.deposit(address(usdc), amount);
    }

    function _depositWeth(address user, uint256 amount) private {
        vm.prank(user);
        pool.deposit(address(weth), amount);
    }

    function _openHealthyBorrow(uint256 amount) private {
        _seedUsdcLiquidity(100_000e18);
        _depositWeth(borrower, 10e18);

        vm.prank(borrower);
        pool.borrow(address(usdc), amount);
    }
}
