// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {LPToken} from "../tokens/LPToken.sol";

contract ConstantProductAMM is ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant MINIMUM_LIQUIDITY = 1000;

    address public token0;
    address public token1;
    uint112 private reserve0;
    uint112 private reserve1;
    uint32 private blockTimestampLast;
    address public lpToken;
    uint256 public totalFeeAccrued;
    uint256 public price0CumulativeLast;
    uint256 public price1CumulativeLast;

    event LiquidityAdded(address indexed provider, uint256 amount0, uint256 amount1, uint256 liquidity);
    event LiquidityRemoved(address indexed provider, uint256 amount0, uint256 amount1, uint256 liquidity);
    event Swap(
        address indexed sender, address indexed tokenIn, uint256 amountIn, uint256 amountOut, address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);

    constructor(address token0_, address token1_) {
        require(token0_ != token1_, "Identical tokens");
        require(token0_ != address(0) && token1_ != address(0), "Zero token");

        token0 = token0_;
        token1 = token1_;
        lpToken = address(new LPToken(address(this), "DeFi Super App LP", "DSLP"));
    }

    function addLiquidity(uint256 amount0, uint256 amount1, uint256 minLp)
        external
        nonReentrant
        returns (uint256 liquidity)
    {
        require(amount0 > 0 && amount1 > 0, "Zero amount");
        (uint112 reserve0_, uint112 reserve1_,) = getReserves();

        IERC20(token0).safeTransferFrom(msg.sender, address(this), amount0);
        IERC20(token1).safeTransferFrom(msg.sender, address(this), amount1);

        uint256 supply = IERC20(lpToken).totalSupply();
        if (supply == 0) {
            liquidity = Math.sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY;
            require(liquidity > 0, "Insufficient liquidity");
            LPToken(lpToken).mint(address(0xdead), MINIMUM_LIQUIDITY);
        } else {
            liquidity = Math.min((amount0 * supply) / reserve0_, (amount1 * supply) / reserve1_);
        }

        require(liquidity >= minLp, "Insufficient LP");

        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));
        _update(balance0, balance1);

        LPToken(lpToken).mint(msg.sender, liquidity);

        emit LiquidityAdded(msg.sender, amount0, amount1, liquidity);
    }

    function removeLiquidity(uint256 lpAmount, uint256 min0, uint256 min1)
        external
        nonReentrant
        returns (uint256 amount0, uint256 amount1)
    {
        require(lpAmount > 0, "Zero LP");
        (uint112 reserve0_, uint112 reserve1_,) = getReserves();

        uint256 supply = IERC20(lpToken).totalSupply();
        amount0 = (lpAmount * reserve0_) / supply;
        amount1 = (lpAmount * reserve1_) / supply;
        require(amount0 >= min0 && amount1 >= min1, "Insufficient output");

        LPToken(lpToken).burn(msg.sender, lpAmount);

        uint256 balance0 = IERC20(token0).balanceOf(address(this)) - amount0;
        uint256 balance1 = IERC20(token1).balanceOf(address(this)) - amount1;
        _update(balance0, balance1);

        IERC20(token0).safeTransfer(msg.sender, amount0);
        IERC20(token1).safeTransfer(msg.sender, amount1);

        emit LiquidityRemoved(msg.sender, amount0, amount1, lpAmount);
    }

    function swap(address tokenIn, uint256 amountIn, uint256 minAmountOut, address to)
        external
        nonReentrant
        returns (uint256 amountOut)
    {
        require(to != address(0), "Zero recipient");
        require(amountIn > 0, "Zero amount");
        require(tokenIn == token0 || tokenIn == token1, "Invalid token");

        bool zeroForOne = tokenIn == token0;
        address tokenOut = zeroForOne ? token1 : token0;
        (uint112 reserve0_, uint112 reserve1_,) = getReserves();
        uint256 reserveIn = zeroForOne ? reserve0_ : reserve1_;
        uint256 reserveOut = zeroForOne ? reserve1_ : reserve0_;

        amountOut = getAmountOutAssembly(reserveIn, reserveOut, amountIn);
        require(amountOut >= minAmountOut, "Insufficient output");
        require(amountOut < reserveOut, "Insufficient liquidity");

        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);

        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));
        if (zeroForOne) {
            balance1 -= amountOut;
        } else {
            balance0 -= amountOut;
        }

        totalFeeAccrued += amountIn - ((amountIn * 997) / 1000);
        _update(balance0, balance1);

        IERC20(tokenOut).safeTransfer(to, amountOut);

        emit Swap(msg.sender, tokenIn, amountIn, amountOut, to);
    }

    function getAmountOut(address tokenIn, uint256 amountIn) external view returns (uint256 amountOut) {
        require(tokenIn == token0 || tokenIn == token1, "Invalid token");
        (uint112 reserve0_, uint112 reserve1_,) = getReserves();

        if (tokenIn == token0) {
            return getAmountOutAssembly(reserve0_, reserve1_, amountIn);
        }

        return getAmountOutAssembly(reserve1_, reserve0_, amountIn);
    }

    function getAmountOutAssembly(uint256 rIn, uint256 rOut, uint256 aIn) public pure returns (uint256 aOut) {
        require(rIn > 0 && rOut > 0, "No liquidity");
        assembly {
            let aInWithFee := mul(aIn, 997)
            let numerator := mul(aInWithFee, rOut)
            let denominator := add(mul(rIn, 1000), aInWithFee)
            aOut := div(numerator, denominator)
        }
    }

    function getAmountOutSolidity(uint256 rIn, uint256 rOut, uint256 aIn) public pure returns (uint256 aOut) {
        require(rIn > 0 && rOut > 0, "No liquidity");
        uint256 aInWithFee = aIn * 997;
        return (aInWithFee * rOut) / ((rIn * 1000) + aInWithFee);
    }

    function getReserves() public view returns (uint112 reserve0_, uint112 reserve1_, uint32 blockTimestampLast_) {
        reserve0_ = reserve0;
        reserve1_ = reserve1;
        blockTimestampLast_ = blockTimestampLast;
    }

    function _update(uint256 bal0, uint256 bal1) internal {
        require(bal0 <= type(uint112).max && bal1 <= type(uint112).max, "Overflow");

        uint32 blockTimestamp = uint32(block.timestamp);
        uint32 timeElapsed = blockTimestamp - blockTimestampLast;
        if (timeElapsed > 0 && reserve0 != 0 && reserve1 != 0) {
            price0CumulativeLast += (uint256(reserve1) * 1e18 * timeElapsed) / reserve0;
            price1CumulativeLast += (uint256(reserve0) * 1e18 * timeElapsed) / reserve1;
        }

        reserve0 = SafeCast.toUint112(bal0);
        reserve1 = SafeCast.toUint112(bal1);
        blockTimestampLast = blockTimestamp;

        emit Sync(reserve0, reserve1);
    }
}
