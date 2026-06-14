// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";

import "../src/oracle/PriceOracle.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployOracle is Script {
    PriceOracle public oracle;

    function run() external returns (address) {
        uint256 pk = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(pk);
        address owner = vm.addr(pk);
        PriceOracle impl = new PriceOracle();
        console.log("PriceOracle Impl:", address(impl));
        oracle = PriceOracle(
            address(
                new ERC1967Proxy(
                    address(impl),
                    abi.encodeCall(PriceOracle.initialize, (owner))
                )
            )
        );

        vm.stopBroadcast();

        console.log("PriceOracle Proxy:", address(oracle));
        console.log("Owner:", owner);
        return address(oracle);
    }
}
