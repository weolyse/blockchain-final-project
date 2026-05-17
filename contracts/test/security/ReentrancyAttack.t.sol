// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ConstantProductAMM} from "../../src/amm/ConstantProductAMM.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

contract ReentrantToken is ERC20 {
    ConstantProductAMM public pair;
    address public attacker;
    bool public armed;

    constructor() ERC20("Reentrant Token", "RNT") {}

    function configureAttack(ConstantProductAMM pair_, address attacker_) external {
        require(address(pair_) != address(0) && attacker_ != address(0), "Zero address");
        pair = pair_;
        attacker = attacker_;
    }

    function setArmed(bool armed_) external {
        armed = armed_;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function transferFrom(address from, address to, uint256 value) public override returns (bool) {
        if (armed && msg.sender == address(pair) && from == attacker) {
            armed = false;
            pair.swap(address(this), 1, 0, attacker);
        }

        return super.transferFrom(from, to, value);
    }
}

contract SwapReentrancyAttacker {
    ReentrantToken public immutable token;
    ConstantProductAMM public immutable pair;

    constructor(ReentrantToken token_, ConstantProductAMM pair_) {
        token = token_;
        pair = pair_;
    }

    function attack(uint256 amountIn) external {
        token.approve(address(pair), amountIn);
        token.setArmed(true);
        pair.swap(address(token), amountIn, 0, address(this));
    }
}

contract ReentrancyAttackTest is Test {
    ReentrantToken private token0;
    MockERC20 private token1;
    ConstantProductAMM private pair;
    SwapReentrancyAttacker private attacker;

    function setUp() public {
        token0 = new ReentrantToken();
        token1 = new MockERC20("Quote Token", "QTE");
        pair = new ConstantProductAMM(address(token0), address(token1));
        attacker = new SwapReentrancyAttacker(token0, pair);

        token0.configureAttack(pair, address(attacker));

        token0.mint(address(this), 100_000e18);
        token1.mint(address(this), 100_000e18);
        token0.approve(address(pair), type(uint256).max);
        token1.approve(address(pair), type(uint256).max);
        pair.addLiquidity(50_000e18, 50_000e18, 1);

        token0.mint(address(attacker), 10e18);
    }

    function testReentrantSwapFailsWithGuard() public {
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        attacker.attack(1e18);
    }
}
