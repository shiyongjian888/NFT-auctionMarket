// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";

import "../src/oracle/PriceOracle.sol";
import "../src/nft/MyNFT.sol";
import "../src/market/AuctionMarket.sol";

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployAll is Script {
    // =====================================================
    // Chainlink Sepolia Price Feeds
    // =====================================================

    address constant ETH_USD_FEED = 0x694AA1769357215DE4FAC081bf1f309aDC325306;

    address constant USDC_USD_FEED = 0xA2F78ab2355fe2f984D808B5CeE7FD0A93D5270E;

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(pk);

        address owner = vm.addr(pk);

        // =====================================================
        // 1. Deploy Oracle
        // =====================================================

        PriceOracle oracleImpl = new PriceOracle();

        PriceOracle oracle = PriceOracle(
            address(new ERC1967Proxy(address(oracleImpl), abi.encodeCall(PriceOracle.initialize, (owner))))
        );

        // register Chainlink feeds (Sepolia)
        oracle.setTokenFeed(address(0), ETH_USD_FEED);

        // 如果你支持 ERC20（如 USDC）
        // oracle.setTokenFeed(
        //     0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, // example mainnet USDC style address (replace if needed)
        //     USDC_USD_FEED
        // );

        // =====================================================
        // 2. Deploy NFT
        // =====================================================

        MyNFT nftImpl = new MyNFT();

        MyNFT nft = MyNFT(
            address(
                new ERC1967Proxy(
                    address(nftImpl), abi.encodeCall(MyNFT.initialize, ("MyNFT", "MNFT", 1000, msg.sender, 500))
                )
            )
        );

        // =====================================================
        // 3. Deploy Auction Market
        // =====================================================

        AuctionMarket marketImpl = new AuctionMarket();

        AuctionMarket market = AuctionMarket(
            payable(address(
                    new ERC1967Proxy(
                        address(marketImpl),
                        abi.encodeCall(AuctionMarket.initialize, (owner, address(oracle), owner, 250))
                    )
                ))
        );

        vm.stopBroadcast();

        // =====================================================
        // Logs
        // =====================================================

        console.log("=== SEPOLIA DEPLOY RESULT ===");

        console.log("Oracle Impl:", address(oracleImpl));
        console.log("NFT Impl:", address(nftImpl));
        console.log("Market Impl:", address(marketImpl));

        console.log("Oracle Proxy:", address(oracle));
        console.log("NFT Proxy:", address(nft));
        console.log("Market Proxy:", address(market));

        console.log("ETH/USD Feed:", ETH_USD_FEED);
        console.log("USDC/USD Feed:", USDC_USD_FEED);

        console.log("Owner:", owner);
    }
}
