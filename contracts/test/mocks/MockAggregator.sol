// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract MockAggregator {
    uint8 public immutable decimals;
    string public description;
    uint256 public version = 1;

    int256 private _answer;
    uint256 private _updatedAt;

    constructor(uint8 decimals_, int256 answer_) {
        decimals = decimals_;
        description = "Mock Aggregator";
        _answer = answer_;
        _updatedAt = block.timestamp;
    }

    function setPrice(int256 price) external {
        _answer = price;
        _updatedAt = block.timestamp;
    }

    function setStaleness(uint256 timestamp) external {
        _updatedAt = timestamp;
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (1, _answer, _updatedAt, _updatedAt, 1);
    }

    function getRoundData(uint80 roundId)
        external
        view
        returns (uint80, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (roundId, _answer, _updatedAt, _updatedAt, roundId);
    }
}
