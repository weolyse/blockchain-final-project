// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {PriceFeedAdapter} from "../../src/oracles/PriceFeedAdapter.sol";
import {MockAggregator} from "../mocks/MockAggregator.sol";

contract PriceFeedAdapterTest is Test {
    PriceFeedAdapter private adapter;
    MockAggregator private feed;

    function setUp() public {
        vm.warp(10_000);
        adapter = new PriceFeedAdapter();
        feed = new MockAggregator(8, 2_000e8);
    }

    function testGetPrice() public view {
        (uint256 price, uint8 decimals) = adapter.getPrice(address(feed));

        assertEq(price, 2_000e8);
        assertEq(decimals, 8);
    }

    function testZeroFeedReverts() public {
        vm.expectRevert("Zero feed");
        adapter.getPrice(address(0));
    }

    function testStalePriceReverts() public {
        feed.setStaleness(block.timestamp - 7_200);

        vm.expectRevert("Stale price");
        adapter.getPrice(address(feed));
    }

    function testNegativePriceReverts() public {
        feed.setPrice(-1);

        vm.expectRevert("Invalid price");
        adapter.getPrice(address(feed));
    }

    function testZeroPriceReverts() public {
        feed.setPrice(0);

        vm.expectRevert("Invalid price");
        adapter.getPrice(address(feed));
    }

    function testFuzz_PriceFeed(int256 price, uint256 age) public {
        age = bound(age, 0, 7_200);
        price = bound(price, -1e18, 1_000_000e8);
        feed.setPrice(price);
        feed.setStaleness(block.timestamp - age);

        if (age > adapter.STALENESS_THRESHOLD()) {
            vm.expectRevert("Stale price");
            adapter.getPrice(address(feed));
        } else if (price <= 0) {
            vm.expectRevert("Invalid price");
            adapter.getPrice(address(feed));
        } else {
            (uint256 returnedPrice, uint8 decimals) = adapter.getPrice(address(feed));
            assertEq(returnedPrice, SafeCast.toUint256(price));
            assertEq(decimals, 8);
        }
    }

    function testFork_ChainlinkETHUSD() public {
        string memory rpcUrl = vm.envOr("ARBITRUM_SEPOLIA_RPC", string(""));
        address feedAddress = vm.envOr("ARBITRUM_SEPOLIA_ETH_USD_FEED", address(0));
        if (bytes(rpcUrl).length == 0 || feedAddress == address(0)) {
            return;
        }

        vm.createSelectFork(rpcUrl);
        (uint256 price, uint8 decimals) = adapter.getPrice(feedAddress);

        assertGt(price, 0);
        assertGt(decimals, 0);
    }
}
