// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LendingPoolV1} from "./LendingPoolV1.sol";

contract LendingPoolV2 is LendingPoolV1 {
    uint256 public flashLoanFeeBps;

    event FlashLoanFeeUpdated(uint256 feeBps);

    function initializeV2(uint256 flashLoanFeeBps_) external reinitializer(2) {
        require(flashLoanFeeBps_ <= 100, "Fee too high");
        flashLoanFeeBps = flashLoanFeeBps_;
        emit FlashLoanFeeUpdated(flashLoanFeeBps_);
    }

    function version() external pure returns (string memory) {
        return "2";
    }

    function setFlashLoanFeeBps(uint256 flashLoanFeeBps_) external onlyOwner {
        require(flashLoanFeeBps_ <= 100, "Fee too high");
        flashLoanFeeBps = flashLoanFeeBps_;
        emit FlashLoanFeeUpdated(flashLoanFeeBps_);
    }
}
