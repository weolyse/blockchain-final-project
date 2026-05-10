// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {PositionNFT} from "../../src/tokens/PositionNFT.sol";

contract PositionNFTTest is Test {
    PositionNFT private nft;

    address private admin = address(0xA11CE);
    address private lendingPool = address(0xBEEF);
    address private borrower = address(0xCAFE);
    address private receiver = address(0xD00D);

    function setUp() public {
        nft = new PositionNFT(admin);
        bytes32 minterRole = nft.MINTER_ROLE();

        vm.prank(admin);
        nft.grantRole(minterRole, lendingPool);
    }

    function testConstructorGrantsRoles() public view {
        assertTrue(nft.hasRole(nft.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(nft.hasRole(nft.MINTER_ROLE(), admin));
    }

    function testMinterCanMint() public {
        vm.prank(lendingPool);
        uint256 tokenId = nft.mint(borrower);

        assertEq(tokenId, 1);
        assertEq(nft.ownerOf(tokenId), borrower);
    }

    function testMintIncrementsTokenId() public {
        vm.startPrank(lendingPool);
        uint256 first = nft.mint(borrower);
        uint256 second = nft.mint(receiver);
        vm.stopPrank();

        assertEq(first, 1);
        assertEq(second, 2);
        assertEq(nft.ownerOf(second), receiver);
    }

    function testNonMinterCannotMint() public {
        vm.prank(borrower);
        vm.expectRevert();
        nft.mint(borrower);
    }

    function testTokenUriIsDataUri() public {
        vm.prank(lendingPool);
        uint256 tokenId = nft.mint(borrower);

        string memory uri = nft.tokenURI(tokenId);

        assertTrue(bytes(uri).length > 29);
        assertEq(_slicePrefix(uri, 29), "data:application/json;base64,");
    }

    function testTokenUriRevertsForMissingToken() public {
        vm.expectRevert();
        nft.tokenURI(999);
    }

    function testTransfer() public {
        vm.prank(lendingPool);
        uint256 tokenId = nft.mint(borrower);

        vm.prank(borrower);
        nft.transferFrom(borrower, receiver, tokenId);

        assertEq(nft.ownerOf(tokenId), receiver);
    }

    function _slicePrefix(string memory value, uint256 length) private pure returns (string memory) {
        bytes memory input = bytes(value);
        bytes memory output = new bytes(length);

        for (uint256 i = 0; i < length; i++) {
            output[i] = input[i];
        }

        return string(output);
    }
}
