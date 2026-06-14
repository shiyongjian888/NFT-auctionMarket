// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IPriceOracle {
    function getUsdValue(address token, uint256 amount) external view returns (uint256);

    function getLatestPrice(address token) external view returns (uint256);

    function isSupportedToken(address token) external view returns (bool);
}
