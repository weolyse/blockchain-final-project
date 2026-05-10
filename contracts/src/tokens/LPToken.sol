// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract LPToken is ERC20, AccessControl {
    bytes32 public constant AMM_ROLE = keccak256("AMM_ROLE");

    constructor(address admin, string memory name_, string memory symbol_) ERC20(name_, symbol_) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(AMM_ROLE, admin);
    }

    function mint(address to, uint256 amount) external onlyRole(AMM_ROLE) {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyRole(AMM_ROLE) {
        _burn(from, amount);
    }
}
