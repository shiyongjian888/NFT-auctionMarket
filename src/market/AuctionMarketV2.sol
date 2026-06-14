// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./AuctionMarket.sol";

contract AuctionMarketV2 is AuctionMarket {

    // ============ 新状态变量 ============
    uint256 public version;

    // ============ 新事件 ============
    event VersionUpgraded(uint256 indexed oldVersion, uint256 indexed newVersion);

    // ============ 初始化 V2 ============
    /**
     * @dev 升级到 V2 版本
     * @param _version 版本号
     */
    function initializeV2(uint256 _version) public reinitializer(2) {
        version = _version;
        emit VersionUpgraded(1, _version);
    }

}
