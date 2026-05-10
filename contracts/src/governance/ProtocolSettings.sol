// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract ProtocolSettings is Ownable {
    uint256 public parameter;

    event ParameterChanged(uint256 parameter);

    constructor(address owner_, uint256 parameter_) Ownable(owner_) {
        parameter = parameter_;
    }

    function changeParameter(uint256 parameter_) external onlyOwner {
        parameter = parameter_;
        emit ParameterChanged(parameter_);
    }
}
