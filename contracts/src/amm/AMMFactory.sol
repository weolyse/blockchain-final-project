// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ConstantProductAMM} from "./ConstantProductAMM.sol";

contract AMMFactory {
    mapping(address token0 => mapping(address token1 => address pair)) public getPair;
    address[] public allPairs;

    event PairCreated(address indexed token0, address indexed token1, address pair, uint256 pairCount);

    function createPair(address tokenA, address tokenB) external returns (address pair) {
        (address token0, address token1) = _sortTokens(tokenA, tokenB);
        _validatePair(token0, token1);

        pair = address(new ConstantProductAMM(token0, token1));
        _registerPair(token0, token1, pair);
    }

    function createPair2(address tokenA, address tokenB, bytes32 salt) external returns (address pair) {
        (address token0, address token1) = _sortTokens(tokenA, tokenB);
        _validatePair(token0, token1);

        bytes32 finalSalt = keccak256(abi.encode(token0, token1, salt));
        pair = address(new ConstantProductAMM{salt: finalSalt}(token0, token1));
        _registerPair(token0, token1, pair);
    }

    function allPairsLength() external view returns (uint256) {
        return allPairs.length;
    }

    function _sortTokens(address tokenA, address tokenB) private pure returns (address token0, address token1) {
        require(tokenA != tokenB, "Identical tokens");
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), "Zero token");
    }

    function _validatePair(address token0, address token1) private view {
        require(getPair[token0][token1] == address(0), "Pair exists");
    }

    function _registerPair(address token0, address token1, address pair) private {
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair;
        allPairs.push(pair);

        emit PairCreated(token0, token1, pair, allPairs.length);
    }
}
