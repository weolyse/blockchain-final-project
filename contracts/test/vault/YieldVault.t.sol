// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Test} from "forge-std/Test.sol";
import {LendingPoolV1} from "../../src/lending/LendingPoolV1.sol";
import {PositionNFT} from "../../src/tokens/PositionNFT.sol";
import {ILendingStrategy, YieldVault} from "../../src/vault/YieldVault.sol";
import {MockAggregator} from "../mocks/MockAggregator.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

contract YieldVaultTest is Test {
    LendingPoolV1 private pool;
    PositionNFT private positionNFT;
    YieldVault private vault;
    MockERC20 private asset;
    MockAggregator private feed;

    address private owner = address(this);
    address private treasury = address(0xA11CE);
    address private user = address(0xB0B);
    address private receiver = address(0xCAFE);

    function setUp() public {
        asset = new MockERC20("USD Coin", "USDC");
        feed = new MockAggregator(8, 1e8);
        positionNFT = new PositionNFT(owner);

        LendingPoolV1 implementation = new LendingPoolV1();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation), abi.encodeCall(LendingPoolV1.initialize, (owner, address(positionNFT)))
        );
        pool = LendingPoolV1(address(proxy));
        pool.setAssetConfig(address(asset), address(feed), 8_000, true);

        vault = new YieldVault(asset, ILendingStrategy(address(pool)), treasury, owner);

        asset.mint(user, 1_000_000e18);
        asset.mint(owner, 1_000_000e18);

        vm.startPrank(user);
        asset.approve(address(vault), type(uint256).max);
        vm.stopPrank();
    }

    function testMetadataAndConstructorState() public view {
        assertEq(vault.name(), "DeFi Super App Vault");
        assertEq(vault.symbol(), "DSV");
        assertEq(vault.asset(), address(asset));
        assertEq(address(vault.lendingPool()), address(pool));
        assertEq(vault.treasury(), treasury);
    }

    function testDepositMintsSharesAndForwardsAssets() public {
        vm.prank(user);
        uint256 shares = vault.deposit(100e18, user);

        (uint256 strategyAssets,,,) = pool.positionOf(address(vault), address(asset));
        assertEq(strategyAssets, 100e18);
        assertEq(asset.balanceOf(address(vault)), 0);
        assertEq(vault.balanceOf(user), shares);
        assertEq(vault.totalAssets(), 100e18);
    }

    function testMintMintsExactShares() public {
        uint256 expectedAssets = vault.previewMint(100e18);

        vm.prank(user);
        uint256 assets = vault.mint(100e18, user);

        assertEq(assets, expectedAssets);
        assertEq(vault.balanceOf(user), 100e18);
    }

    function testWithdrawPullsAssetsFromLendingPool() public {
        vm.prank(user);
        vault.deposit(100e18, user);

        uint256 expectedShares = vault.previewWithdraw(40e18);

        vm.prank(user);
        uint256 sharesBurned = vault.withdraw(40e18, receiver, user);

        assertEq(asset.balanceOf(receiver), 40e18);
        assertEq(sharesBurned, expectedShares);
        assertEq(vault.totalAssets(), 60e18);
    }

    function testRedeemPullsAssetsFromLendingPool() public {
        vm.prank(user);
        vault.deposit(100e18, user);

        uint256 sharesToRedeem = vault.balanceOf(user) / 4;
        uint256 expectedAssets = vault.previewRedeem(sharesToRedeem);

        vm.prank(user);
        uint256 assetsRedeemed = vault.redeem(sharesToRedeem, receiver, user);

        assertEq(assetsRedeemed, expectedAssets);
        assertEq(asset.balanceOf(receiver), expectedAssets);
    }

    function testReportYieldTakesPerformanceFee() public {
        asset.approve(address(vault), type(uint256).max);

        vault.reportYield(100e18);

        assertEq(asset.balanceOf(treasury), 0.1e18);
        assertEq(vault.totalPerformanceFees(), 0.1e18);
        assertEq(vault.totalAssets(), 99.9e18);
    }

    function testReportYieldOnlyOwner() public {
        vm.prank(user);
        vm.expectRevert();
        vault.reportYield(1e18);
    }

    function testSetTreasury() public {
        address newTreasury = address(0xD00D);

        vault.setTreasury(newTreasury);

        assertEq(vault.treasury(), newTreasury);
    }

    function testSetTreasuryOnlyOwner() public {
        vm.prank(user);
        vm.expectRevert();
        vault.setTreasury(address(0xD00D));
    }

    function testRoundingPreviewInvariants() public {
        vm.prank(user);
        vault.deposit(100e18, user);

        uint256 previewDeposit = vault.previewDeposit(10e18);
        vm.prank(user);
        uint256 depositShares = vault.deposit(10e18, user);
        assertLe(previewDeposit, depositShares);

        uint256 previewMint = vault.previewMint(5e18);
        vm.prank(user);
        uint256 mintAssets = vault.mint(5e18, user);
        assertGe(previewMint, mintAssets);

        uint256 previewWithdraw = vault.previewWithdraw(1e18);
        vm.prank(user);
        uint256 withdrawShares = vault.withdraw(1e18, user, user);
        assertLe(previewWithdraw, withdrawShares);

        uint256 previewRedeem = vault.previewRedeem(1e18);
        vm.prank(user);
        uint256 redeemAssets = vault.redeem(1e18, user, user);
        assertGe(previewRedeem, redeemAssets);
    }

    function testFuzz_VaultDepositWithdraw(uint96 assets) public {
        assets = uint96(bound(assets, 1e6, 100_000e18));

        uint256 previewDeposit = vault.previewDeposit(assets);
        vm.prank(user);
        uint256 shares = vault.deposit(assets, user);
        assertLe(previewDeposit, shares);

        uint256 previewWithdraw = vault.previewWithdraw(assets);
        vm.prank(user);
        uint256 burned = vault.withdraw(assets, user, user);
        assertLe(previewWithdraw, burned);

        assertEq(vault.balanceOf(user), 0);
    }

    function testFuzz_VaultInflationAttack(uint96 frontrun) public {
        frontrun = uint96(bound(frontrun, 1, 100e18));

        address attacker = address(0xBAD);
        asset.mint(attacker, 1);
        vm.startPrank(attacker);
        asset.approve(address(vault), 1);
        vault.deposit(1, attacker);
        vm.stopPrank();

        asset.mint(address(vault), frontrun);

        vm.prank(user);
        uint256 victimShares = vault.deposit(1_000e18, user);

        assertGt(victimShares, 0);
    }
}
