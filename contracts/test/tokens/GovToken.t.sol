// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {GovToken} from "../../src/tokens/GovToken.sol";

contract GovTokenTest is Test {
    bytes32 private constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    GovToken private token;

    address private admin = address(0xA11CE);
    address private minter = address(0xB0B);
    address private user = address(0xCAFE);
    address private receiver = address(0xD00D);

    function setUp() public {
        token = new GovToken(admin);
        bytes32 minterRole = token.MINTER_ROLE();

        vm.prank(admin);
        token.grantRole(minterRole, minter);
    }

    function testConstructorGrantsAdminAndMinterRoles() public view {
        assertTrue(token.hasRole(token.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(token.hasRole(token.MINTER_ROLE(), admin));
    }

    function testAdminCanGrantMinterRole() public view {
        assertTrue(token.hasRole(token.MINTER_ROLE(), minter));
    }

    function testMinterCanMint() public {
        vm.prank(minter);
        token.mint(user, 100e18);

        assertEq(token.balanceOf(user), 100e18);
        assertEq(token.totalSupply(), 100e18);
    }

    function testNonMinterCannotMint() public {
        vm.prank(user);
        vm.expectRevert();
        token.mint(user, 1e18);
    }

    function testMintRevertsAboveMaxSupply() public {
        uint256 maxSupply = token.MAX_SUPPLY();

        vm.prank(minter);
        token.mint(user, maxSupply);

        vm.prank(minter);
        vm.expectRevert("Exceeds max supply");
        token.mint(user, 1);
    }

    function testTransferMovesBalance() public {
        vm.prank(minter);
        token.mint(user, 50e18);

        vm.prank(user);
        assertTrue(token.transfer(receiver, 20e18));

        assertEq(token.balanceOf(user), 30e18);
        assertEq(token.balanceOf(receiver), 20e18);
    }

    function testDelegateCreatesVotingPowerCheckpoint() public {
        vm.prank(minter);
        token.mint(user, 10e18);

        vm.prank(user);
        token.delegate(user);

        assertEq(token.getVotes(user), 10e18);
    }

    function testTransferUpdatesDelegatedVotes() public {
        vm.prank(minter);
        token.mint(user, 10e18);

        vm.prank(user);
        token.delegate(user);

        vm.prank(receiver);
        token.delegate(receiver);

        vm.prank(user);
        assertTrue(token.transfer(receiver, 4e18));

        assertEq(token.getVotes(user), 6e18);
        assertEq(token.getVotes(receiver), 4e18);
    }

    function testPermitApprovesSpender() public {
        (address owner, uint256 ownerKey) = makeAddrAndKey("permit-owner");
        uint256 value = 25e18;
        uint256 deadline = block.timestamp + 1 days;

        bytes32 structHash =
            keccak256(abi.encode(PERMIT_TYPEHASH, owner, receiver, value, token.nonces(owner), deadline));
        bytes32 digest = keccak256(abi.encodePacked(hex"1901", token.DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerKey, digest);

        token.permit(owner, receiver, value, deadline, v, r, s);

        assertEq(token.allowance(owner, receiver), value);
        assertEq(token.nonces(owner), 1);
    }

    function testExpiredPermitReverts() public {
        (address owner, uint256 ownerKey) = makeAddrAndKey("expired-permit-owner");
        uint256 deadline = block.timestamp;

        bytes32 structHash =
            keccak256(abi.encode(PERMIT_TYPEHASH, owner, receiver, 1e18, token.nonces(owner), deadline));
        bytes32 digest = keccak256(abi.encodePacked(hex"1901", token.DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerKey, digest);

        vm.warp(block.timestamp + 1);
        vm.expectRevert();
        token.permit(owner, receiver, 1e18, deadline, v, r, s);
    }

    function testFuzz_GovTokenDelegate(address delegatee, uint96 amount) public {
        vm.assume(delegatee != address(0));
        amount = uint96(bound(amount, 1, 1_000_000e18));

        vm.prank(minter);
        token.mint(user, amount);

        vm.prank(user);
        token.delegate(delegatee);

        assertEq(token.delegates(user), delegatee);
        assertEq(token.getVotes(delegatee), amount);
    }
}
