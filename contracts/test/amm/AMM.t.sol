// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Test} from "forge-std/Test.sol";
import {ConstantProductAMM} from "../../src/amm/ConstantProductAMM.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

contract AMMTest is Test {
    ConstantProductAMM private amm;
    MockERC20 private token0;
    MockERC20 private token1;

    address private user = address(0xA11CE);
    address private trader = address(0xB0B);

    function setUp() public {
        token0 = new MockERC20("Token A", "TKA");
        token1 = new MockERC20("Token B", "TKB");
        amm = new ConstantProductAMM(address(token0), address(token1));

        token0.mint(user, 10_000e18);
        token1.mint(user, 10_000e18);
        token0.mint(trader, 10_000e18);
        token1.mint(trader, 10_000e18);

        vm.startPrank(user);
        token0.approve(address(amm), type(uint256).max);
        token1.approve(address(amm), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(trader);
        token0.approve(address(amm), type(uint256).max);
        token1.approve(address(amm), type(uint256).max);
        vm.stopPrank();
    }

    function testAddLiquidity() public {
        uint256 liquidity = _addLiquidity(1000e18, 1000e18);
        (uint112 reserve0, uint112 reserve1,) = amm.getReserves();

        assertEq(reserve0, 1000e18);
        assertEq(reserve1, 1000e18);
        assertEq(liquidity, 1000e18 - amm.MINIMUM_LIQUIDITY());
        assertEq(IERC20(amm.lpToken()).balanceOf(user), liquidity);
    }

    function testRemoveLiquidity() public {
        uint256 liquidity = _addLiquidity(1000e18, 1000e18);
        uint256 removeAmount = liquidity / 2;

        vm.prank(user);
        (uint256 amount0, uint256 amount1) = amm.removeLiquidity(removeAmount, 1, 1);

        assertEq(amount0, removeAmount);
        assertEq(amount1, removeAmount);
        assertEq(IERC20(amm.lpToken()).balanceOf(user), liquidity - removeAmount);
    }

    function testSwap_zeroForOne() public {
        _addLiquidity(1000e18, 1000e18);
        uint256 kBefore = _k();
        uint256 expectedOut = amm.getAmountOut(address(token0), 10e18);

        vm.prank(trader);
        uint256 amountOut = amm.swap(address(token0), 10e18, expectedOut, trader);

        assertEq(amountOut, expectedOut);
        assertEq(token1.balanceOf(trader), 10_000e18 + expectedOut);
        assertGe(_k(), kBefore);
    }

    function testSwap_oneForZero() public {
        _addLiquidity(1000e18, 1000e18);
        uint256 expectedOut = amm.getAmountOut(address(token1), 10e18);

        vm.prank(trader);
        uint256 amountOut = amm.swap(address(token1), 10e18, expectedOut, trader);

        assertEq(amountOut, expectedOut);
        assertEq(token0.balanceOf(trader), 10_000e18 + expectedOut);
    }

    function testSwap_RevertSlippage() public {
        _addLiquidity(1000e18, 1000e18);
        uint256 expectedOut = amm.getAmountOut(address(token0), 10e18);

        vm.prank(trader);
        vm.expectRevert("Insufficient output");
        amm.swap(address(token0), 10e18, expectedOut + 1, trader);
    }

    function testFeeAccrual() public {
        _addLiquidity(1000e18, 1000e18);

        vm.prank(trader);
        amm.swap(address(token0), 10e18, 1, trader);

        assertEq(amm.totalFeeAccrued(), 0.03e18);
    }

    function testMinLiquidityLock() public {
        _addLiquidity(1000e18, 1000e18);

        assertEq(IERC20(amm.lpToken()).balanceOf(address(0xdead)), amm.MINIMUM_LIQUIDITY());
    }

    function testAmountOutAssemblyMatchesSolidity() public view {
        uint256 assemblyOut = amm.getAmountOutAssembly(1000e18, 1000e18, 10e18);
        uint256 solidityOut = amm.getAmountOutSolidity(1000e18, 1000e18, 10e18);

        assertEq(assemblyOut, solidityOut);
    }

    function testFuzz_Swap(uint96 amountIn) public {
        amountIn = uint96(bound(amountIn, 1e6, 100e18));
        _addLiquidity(1000e18, 1000e18);
        uint256 kBefore = _k();

        vm.prank(trader);
        amm.swap(address(token0), amountIn, 1, trader);

        assertGe(_k(), kBefore);
    }

    function testFuzz_AddRemoveLiquidity(uint96 amount0, uint96 amount1) public {
        amount0 = uint96(bound(amount0, 1e12, 1000e18));
        amount1 = uint96(bound(amount1, 1e12, 1000e18));

        uint256 liquidity = _addLiquidity(amount0, amount1);

        vm.prank(user);
        (uint256 returned0, uint256 returned1) = amm.removeLiquidity(liquidity / 2, 1, 1);

        assertGt(returned0, 0);
        assertGt(returned1, 0);
    }

    function testFuzz_LPMint(uint96 amount0, uint96 amount1, uint96 minLp) public {
        amount0 = uint96(bound(amount0, 1e12, 1000e18));
        amount1 = uint96(bound(amount1, 1e12, 1000e18));
        minLp = uint96(bound(minLp, 0, 1));

        uint256 liquidity = _addLiquidity(amount0, amount1);

        assertGt(liquidity, minLp);
    }

    function _addLiquidity(uint256 amount0, uint256 amount1) private returns (uint256 liquidity) {
        vm.prank(user);
        liquidity = amm.addLiquidity(amount0, amount1, 0);
    }

    function _k() private view returns (uint256) {
        (uint112 reserve0, uint112 reserve1,) = amm.getReserves();
        return uint256(reserve0) * reserve1;
    }
}

contract AMMInvariantTest is Test {
    ConstantProductAMM private amm;
    MockERC20 private token0;
    MockERC20 private token1;
    AMMSwapHandler private handler;
    uint256 private initialK;

    function setUp() public {
        token0 = new MockERC20("Token A", "TKA");
        token1 = new MockERC20("Token B", "TKB");
        amm = new ConstantProductAMM(address(token0), address(token1));

        token0.mint(address(this), 1000e18);
        token1.mint(address(this), 1000e18);
        token0.approve(address(amm), type(uint256).max);
        token1.approve(address(amm), type(uint256).max);
        amm.addLiquidity(1000e18, 1000e18, 0);

        initialK = _k();
        handler = new AMMSwapHandler(amm, token0, token1);
        targetContract(address(handler));
    }

    function invariant_kNeverDecreases() public view {
        assertGe(_k(), initialK);
    }

    function _k() private view returns (uint256) {
        (uint112 reserve0, uint112 reserve1,) = amm.getReserves();
        return uint256(reserve0) * reserve1;
    }
}

contract AMMSwapHandler is Test {
    ConstantProductAMM private immutable amm;
    MockERC20 private immutable token0;
    MockERC20 private immutable token1;

    constructor(ConstantProductAMM amm_, MockERC20 token0_, MockERC20 token1_) {
        amm = amm_;
        token0 = token0_;
        token1 = token1_;

        token0.mint(address(this), 1_000_000e18);
        token1.mint(address(this), 1_000_000e18);
        token0.approve(address(amm), type(uint256).max);
        token1.approve(address(amm), type(uint256).max);
    }

    function swap(uint96 rawAmount, bool zeroForOne) external {
        uint256 amountIn = bound(rawAmount, 1e6, 100e18);
        address tokenIn = zeroForOne ? address(token0) : address(token1);
        amm.swap(tokenIn, amountIn, 1, address(this));
    }
}
