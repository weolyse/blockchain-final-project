// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract PositionNFT is ERC721, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    uint256 private _nextTokenId = 1;

    constructor(address admin) ERC721("Borrow Position", "BPOS") {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, admin);
    }

    function mint(address to) external onlyRole(MINTER_ROLE) returns (uint256 tokenId) {
        tokenId = _nextTokenId++;
        _safeMint(to, tokenId);
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);

        string memory tokenIdString = Strings.toString(tokenId);
        string memory svg = string.concat(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 360 180">',
            '<rect width="360" height="180" fill="#111827"/>',
            '<text x="24" y="76" fill="#f9fafb" font-family="monospace" font-size="24">Borrow Position</text>',
            '<text x="24" y="118" fill="#93c5fd" font-family="monospace" font-size="18">#',
            tokenIdString,
            "</text></svg>"
        );

        string memory json = Base64.encode(
            bytes(
                string.concat(
                    '{"name":"Borrow Position #',
                    tokenIdString,
                    '","description":"On-chain receipt for a DeFi Super App borrow position.",',
                    '"image":"data:image/svg+xml;base64,',
                    Base64.encode(bytes(svg)),
                    '"}'
                )
            )
        );

        return string.concat("data:application/json;base64,", json);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
