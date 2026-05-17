// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {GovToken} from "../../src/tokens/GovToken.sol";

contract UnguardedMintToken is ERC20 {
    constructor() ERC20("Unguarded Mint", "UGM") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract AccessControlAttackTest is Test {
    address private admin = address(0xA11CE);
    address private attacker = address(0xBAD);

    function testUnguardedMintSucceedsForAttacker() public {
        UnguardedMintToken token = new UnguardedMintToken();

        vm.prank(attacker);
        token.mint(attacker, 1_000e18);

        assertEq(token.balanceOf(attacker), 1_000e18);
    }

    function testGovTokenMintRevertsForAttacker() public {
        GovToken token = new GovToken(admin);

        vm.prank(attacker);
        vm.expectRevert();
        token.mint(attacker, 1_000e18);

        assertEq(token.balanceOf(attacker), 0);
    }
}
