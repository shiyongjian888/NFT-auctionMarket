// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./PriceOracle.sol";

contract PriceOracleV2 is PriceOracle {
    function version() external pure returns (uint256) {
        return 2;
    }
}
