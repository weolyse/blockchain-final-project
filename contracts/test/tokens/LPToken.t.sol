// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {LPToken} from "../../src/tokens/LPToken.sol";

contract LPTokenTest is Test {
    LPToken private token;

    address private admin = address(0xA11CE);
    address private amm = address(0xBEEF);
    address private user = address(0xCAFE);
    address private receiver = address(0xD00D);

    function setUp() public {
        token = new LPToken(admin, "DeFi LP", "DLP");
        bytes32 ammRole = token.AMM_ROLE();

        vm.prank(admin);
        token.grantRole(ammRole, amm);
    }

    function testMetadata() public view {
        assertEq(token.name(), "DeFi LP");
        assertEq(token.symbol(), "DLP");
        assertEq(token.decimals(), 18);
    }

    function testAmmCanMint() public {
        vm.prank(amm);
        token.mint(user, 100e18);

        assertEq(token.balanceOf(user), 100e18);
        assertEq(token.totalSupply(), 100e18);
    }

    function testNonAmmCannotMint() public {
        vm.prank(user);
        vm.expectRevert();
        token.mint(user, 1e18);
    }

    function testAmmCanBurn() public {
        vm.prank(amm);
        token.mint(user, 100e18);

        vm.prank(amm);
        token.burn(user, 40e18);

        assertEq(token.balanceOf(user), 60e18);
        assertEq(token.totalSupply(), 60e18);
    }

    function testNonAmmCannotBurn() public {
        vm.prank(amm);
        token.mint(user, 100e18);

        vm.prank(user);
        vm.expectRevert();
        token.burn(user, 1e18);
    }

    function testTransfer() public {
        vm.prank(amm);
        token.mint(user, 100e18);

        vm.prank(user);
        assertTrue(token.transfer(receiver, 35e18));

        assertEq(token.balanceOf(user), 65e18);
        assertEq(token.balanceOf(receiver), 35e18);
    }
}
