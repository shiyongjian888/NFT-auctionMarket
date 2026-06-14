// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";

import "../src/nft/MyNFT.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployNFT is Script {
    MyNFT public nft;

    function run() external returns (address) {
        uint256 pk = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(pk);

        MyNFT impl = new MyNFT();
        console.log("NFT Impl:", address(impl));
        nft = MyNFT(
            address(
                new ERC1967Proxy(
                    address(impl), abi.encodeCall(MyNFT.initialize, ("MyNFT", "MNFT", 1000, msg.sender, 500))
                )
            )
        );

        vm.stopBroadcast();
        console.log("NFT Proxy:", address(nft));
        console.log("Owner:", msg.sender);
        return address(nft);
    }
}
