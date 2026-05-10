// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract Treasury is Ownable {
    using SafeERC20 for IERC20;

    constructor(address owner_) Ownable(owner_) {}

    function release(address token, address to, uint256 amount) external onlyOwner {
        require(to != address(0), "Zero recipient");
        IERC20(token).safeTransfer(to, amount);
    }
}
