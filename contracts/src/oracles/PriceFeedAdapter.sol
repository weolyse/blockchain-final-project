// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IOracleAdapter} from "./IOracleAdapter.sol";

contract PriceFeedAdapter is IOracleAdapter {
    uint256 public constant STALENESS_THRESHOLD = 1 hours;

    function getPrice(address feed) external view returns (uint256 price, uint8 decimals) {
        require(feed != address(0), "Zero feed");

        (, int256 answer,, uint256 updatedAt,) = AggregatorV3Interface(feed).latestRoundData();
        // forge-lint: disable-next-line(block-timestamp)
        require(block.timestamp - updatedAt <= STALENESS_THRESHOLD, "Stale price");
        require(answer > 0, "Invalid price");

        return (SafeCast.toUint256(answer), AggregatorV3Interface(feed).decimals());
    }
}
