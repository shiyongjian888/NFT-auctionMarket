// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";

import "../src/market/AuctionMarket.sol";
import "../src/market/AuctionMarketV2.sol";

contract UpgradeAuctionMarket is Script {
    function run() external {
        // =====================================================
        // 1. Load env variables
        // =====================================================

        uint256 pk = vm.envUint("PRIVATE_KEY");
        address proxyAddress = vm.envAddress("PROXY_ADDRESS");

        vm.startBroadcast(pk);

        // =====================================================
        // 2. Deploy new implementation (V2)
        // =====================================================

        AuctionMarketV2 newImplementation = new AuctionMarketV2();

        console.log("New Implementation:", address(newImplementation));

        // =====================================================
        // 3. Upgrade proxy
        // =====================================================

        AuctionMarket(payable(proxyAddress)).upgradeToAndCall(
            address(newImplementation),
            abi.encodeCall(AuctionMarketV2.initializeV2, (2))
        );

        vm.stopBroadcast();

        console.log("Upgrade completed for proxy:", proxyAddress);
    }
}
