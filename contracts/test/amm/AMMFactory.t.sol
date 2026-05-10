// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {AMMFactory} from "../../src/amm/AMMFactory.sol";
import {ConstantProductAMM} from "../../src/amm/ConstantProductAMM.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

contract AMMFactoryTest is Test {
    AMMFactory private factory;
    MockERC20 private tokenA;
    MockERC20 private tokenB;
    MockERC20 private tokenC;

    function setUp() public {
        factory = new AMMFactory();
        tokenA = new MockERC20("Token A", "TKA");
        tokenB = new MockERC20("Token B", "TKB");
        tokenC = new MockERC20("Token C", "TKC");
    }

    function testCreatePair() public {
        address pair = factory.createPair(address(tokenA), address(tokenB));

        assertTrue(pair != address(0));
        assertEq(factory.getPair(address(tokenA), address(tokenB)), pair);
        assertEq(factory.getPair(address(tokenB), address(tokenA)), pair);
        assertEq(factory.allPairsLength(), 1);
    }

    function testCreatePairSortsTokens() public {
        address pair = factory.createPair(address(tokenB), address(tokenA));
        (address token0, address token1,) = _sort(address(tokenA), address(tokenB));

        assertEq(ConstantProductAMM(pair).token0(), token0);
        assertEq(ConstantProductAMM(pair).token1(), token1);
    }

    function testCreatePair2() public {
        bytes32 salt = keccak256("pair-salt");
        address pair = factory.createPair2(address(tokenA), address(tokenC), salt);

        assertTrue(pair != address(0));
        assertEq(factory.getPair(address(tokenA), address(tokenC)), pair);
        assertEq(factory.allPairsLength(), 1);
    }

    function testCreatePairRevertsDuplicate() public {
        factory.createPair(address(tokenA), address(tokenB));

        vm.expectRevert("Pair exists");
        factory.createPair(address(tokenA), address(tokenB));
    }

    function testCreatePair2RevertsDuplicateReverseOrder() public {
        factory.createPair2(address(tokenA), address(tokenB), keccak256("first"));

        vm.expectRevert("Pair exists");
        factory.createPair2(address(tokenB), address(tokenA), keccak256("second"));
    }

    function testCreatePairRevertsIdenticalTokens() public {
        vm.expectRevert("Identical tokens");
        factory.createPair(address(tokenA), address(tokenA));
    }

    function testCreatePairRevertsZeroToken() public {
        vm.expectRevert("Zero token");
        factory.createPair(address(0), address(tokenA));
    }

    function _sort(address a, address b) private pure returns (address token0, address token1, bool flipped) {
        flipped = b < a;
        (token0, token1) = a < b ? (a, b) : (b, a);
    }
}
