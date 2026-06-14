// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";

import "../src/market/AuctionMarket.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployAuctionMarket is Script {
    AuctionMarket public market;

    function run(address oracle) external returns (address) {
        uint256 pk = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(pk);
        address owner = vm.addr(pk);
        AuctionMarket impl = new AuctionMarket();
        console.log("AuctionMarket Impl:", address(impl));
        market = AuctionMarket(
            payable(address(
                    new ERC1967Proxy(
                        address(impl), abi.encodeCall(AuctionMarket.initialize, (owner, oracle, owner, 250))
                    )
                ))
        );

        vm.stopBroadcast();
        console.log("AuctionMarket Proxy:", address(market));
        console.log("Owner:", owner);
        return address(market);
    }
}
