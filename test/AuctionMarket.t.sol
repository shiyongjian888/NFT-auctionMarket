// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import "../src/nft/MyNFT.sol";
import "../src/oracle/PriceOracle.sol";
import "../src/market/AuctionMarket.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/mocks/MockV3Aggregator.sol";
import "../src/mocks/MockERC20.sol";

contract AuctionMarketTest is Test {
    MyNFT nft;
    PriceOracle oracle;
    AuctionMarket market;

    MockERC20 usdc;
    MockERC20 linkToken;

    MockV3Aggregator ethFeed;
    MockV3Aggregator usdcFeed;
    MockV3Aggregator linkFeed;

    address owner = address(1);
    address seller = address(2);

    address bidder1 = address(3);
    address bidder2 = address(4);

    address royaltyReceiver = address(5);
    address feeRecipient = address(6);

    uint256 constant ETH_PRICE = 3000e8;

    uint256 constant USDC_PRICE = 1e8;

    uint256 constant LINK_PRICE = 14e8;

    function setUp() public {
        vm.startPrank(owner);

        //----------------------------------
        // Feed
        //----------------------------------
        // casting to int256 is safe because ETH_PRICE is much smaller than int256 max
        // forge-lint: disable-next-line(unsafe-typecast)
        ethFeed = new MockV3Aggregator(8, int256(ETH_PRICE));
        // casting to int256 is safe because ETH_PRICE is much smaller than int256 max
        // forge-lint: disable-next-line(unsafe-typecast)
        usdcFeed = new MockV3Aggregator(8, int256(USDC_PRICE));
        // casting to int256 is safe because ETH_PRICE is much smaller than int256 max
        // forge-lint: disable-next-line(unsafe-typecast)
        linkFeed = new MockV3Aggregator(8, int256(LINK_PRICE));

        //----------------------------------
        // NFT
        //----------------------------------

        MyNFT nftImpl = new MyNFT();

        ERC1967Proxy nftProxy = new ERC1967Proxy(
            address(nftImpl), abi.encodeCall(MyNFT.initialize, ("Test NFT", "TNFT", 1000, royaltyReceiver, 500))
        );

        nft = MyNFT(address(nftProxy));

        //----------------------------------
        // Oracle
        //----------------------------------

        PriceOracle oracleImpl = new PriceOracle();

        ERC1967Proxy oracleProxy =
            new ERC1967Proxy(address(oracleImpl), abi.encodeCall(PriceOracle.initialize, (owner)));

        oracle = PriceOracle(address(oracleProxy));

        //----------------------------------
        // Tokens
        //----------------------------------

        usdc = new MockERC20("USDC", "USDC", 6);

        linkToken = new MockERC20("LINK", "LINK", 18);

        oracle.setTokenFeed(address(0), address(ethFeed));

        oracle.setTokenFeed(address(usdc), address(usdcFeed));

        oracle.setTokenFeed(address(linkToken), address(linkFeed));

        //----------------------------------
        // Market
        //----------------------------------

        AuctionMarket marketImpl = new AuctionMarket();

        ERC1967Proxy marketProxy = new ERC1967Proxy(
            address(marketImpl), abi.encodeCall(AuctionMarket.initialize, (owner, address(oracle), feeRecipient, 250))
        );

        market = AuctionMarket(payable(address(marketProxy)));

        vm.stopPrank();

        //----------------------------------
        // Mint NFT
        //----------------------------------

        vm.prank(owner);

        nft.mint(seller, "ipfs://1");

        //----------------------------------
        // Mint ERC20
        //----------------------------------

        usdc.mint(bidder1, 5000e6);

        usdc.mint(bidder2, 5000e6);

        linkToken.mint(bidder1, 5000e18);

        linkToken.mint(bidder2, 5000e18);

        vm.deal(bidder1, 100 ether);

        vm.deal(bidder2, 100 ether);
    }

    function testCreateAuction() public {
        vm.startPrank(seller);

        nft.approve(address(market), 1);

        market.createAuction(address(nft), 1, 1 days);

        AuctionMarket.Auction memory auction = market.getAuction(1);

        assertEq(auction.seller, seller);

        assertEq(auction.tokenId, 1);

        assertEq(uint256(auction.status), uint256(AuctionMarket.AuctionStatus.Active));

        assertEq(auction.endTime, auction.startTime + 1 days);

        assertEq(nft.ownerOf(1), address(market));

        vm.stopPrank();
    }

    function testBidETH() public {
        _createAuction();

        vm.prank(bidder1);

        market.bidETH{value: 1 ether}(1);

        (address bidder,, uint256 amount, uint256 usdValue) = market.getHighestBid(1);

        assertEq(bidder, bidder1);

        assertEq(amount, 1 ether);

        assertEq(usdValue, 3000e18);
    }

    function testBidERC20() public {
        _createAuction();

        vm.startPrank(bidder1);

        usdc.approve(address(market), 2000e6);

        market.bidERC20(1, address(usdc), 2000e6);

        (address bidder, address token, uint256 amount,) = market.getHighestBid(1);

        assertEq(bidder, bidder1);

        assertEq(token, address(usdc));

        assertEq(amount, 2000e6);

        vm.stopPrank();
    }

    function testOutBid() public {
        _createAuction();

        vm.prank(bidder1);

        market.bidETH{value: 1 ether}(1);

        vm.prank(bidder2);

        market.bidETH{value: 2 ether}(1);

        uint256 pending = market.getPendingWithdrawal(bidder1, address(0));

        assertEq(pending, 1 ether);
    }

    function _createAuction() internal {
        vm.startPrank(seller);

        nft.approve(address(market), 1);

        market.createAuction(address(nft), 1, 1 days);

        vm.stopPrank();
    }

    function testNFTTransferredToMarket() public {
        _createAuction();

        assertEq(nft.ownerOf(1), address(market));
    }
}
