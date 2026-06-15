// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import "../src/market/AuctionMarket.sol";
import "../src/market/AuctionMarketV2.sol";
import "../src/mocks/MockERC20.sol";
import "../src/mocks/MockNFTNoRoyalty.sol";
import "../src/mocks/MockV3Aggregator.sol";
import "../src/nft/MyNFT.sol";
import "../src/oracle/PriceOracle.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract RejectETH {
    receive() external payable {
        revert("reject eth");
    }
}

contract AuctionMarketTest is Test {
    event AuctionCreated(
        uint256 indexed auctionId,
        address indexed seller,
        address indexed nft,
        uint256 tokenId,
        uint256 endTime
    );
    event AuctionCancelledEvent(uint256 indexed auctionId);
    event BidPlaced(uint256 indexed auctionId, address indexed bidder, address bidToken, uint256 amount, uint256 usdValue);
    event AuctionEndedEvent(
        uint256 indexed auctionId,
        address winner,
        address bidToken,
        uint256 amount,
        uint256 usdValue
    );
    event VersionUpgraded(uint256 indexed oldVersion, uint256 indexed newVersion);

    MyNFT internal nft;
    MockNFTNoRoyalty internal nftNoRoyalty;
    PriceOracle internal oracle;
    AuctionMarket internal market;

    MockERC20 internal usdc;
    MockERC20 internal linkToken;
    MockERC20 internal unsupportedToken;

    MockV3Aggregator internal ethFeed;
    MockV3Aggregator internal usdcFeed;
    MockV3Aggregator internal linkFeed;

    address internal owner = address(0x1);
    address internal seller = address(0x2);
    address internal bidder1 = address(0x3);
    address internal bidder2 = address(0x4);
    address internal royaltyReceiver = address(0x5);
    address internal feeRecipient = address(0x6);
    address internal newFeeRecipient = address(0x7);
    address internal attacker = address(0x8);

    uint256 internal constant TOKEN_ID = 1;
    uint256 internal constant AUCTION_ID = 1;
    uint256 internal constant ETH_PRICE = 3000e8;
    uint256 internal constant USDC_PRICE = 1e8;
    uint256 internal constant LINK_PRICE = 14e8;
    uint96 internal constant PLATFORM_FEE = 250;
    uint96 internal constant ROYALTY_FEE = 500;

    function setUp() public {
        vm.warp(100);

        vm.startPrank(owner);

        ethFeed = new MockV3Aggregator(8, int256(ETH_PRICE));
        usdcFeed = new MockV3Aggregator(8, int256(USDC_PRICE));
        linkFeed = new MockV3Aggregator(8, int256(LINK_PRICE));

        MyNFT nftImpl = new MyNFT();
        nft = MyNFT(
            address(
                new ERC1967Proxy(
                    address(nftImpl),
                    abi.encodeCall(MyNFT.initialize, ("Test NFT", "TNFT", 1000, royaltyReceiver, ROYALTY_FEE))
                )
            )
        );

        PriceOracle oracleImpl = new PriceOracle();
        oracle = PriceOracle(
            address(new ERC1967Proxy(address(oracleImpl), abi.encodeCall(PriceOracle.initialize, (owner))))
        );

        usdc = new MockERC20("USDC", "USDC", 6);
        linkToken = new MockERC20("LINK", "LINK", 18);
        unsupportedToken = new MockERC20("BAD", "BAD", 18);

        oracle.setTokenFeed(address(0), address(ethFeed));
        oracle.setTokenFeed(address(usdc), address(usdcFeed));
        oracle.setTokenFeed(address(linkToken), address(linkFeed));

        AuctionMarket marketImpl = new AuctionMarket();
        market = AuctionMarket(
            payable(
                address(
                    new ERC1967Proxy(
                        address(marketImpl),
                        abi.encodeCall(
                            AuctionMarket.initialize, (owner, address(oracle), feeRecipient, PLATFORM_FEE)
                        )
                    )
                )
            )
        );

        nft.mint(seller, "ipfs://1");

        vm.stopPrank();

        nftNoRoyalty = new MockNFTNoRoyalty();
        nftNoRoyalty.mint(seller, TOKEN_ID);

        usdc.mint(bidder1, 10_000e6);
        usdc.mint(bidder2, 10_000e6);
        linkToken.mint(bidder1, 10_000e18);
        linkToken.mint(bidder2, 10_000e18);
        unsupportedToken.mint(bidder1, 10_000e18);

        vm.deal(bidder1, 100 ether);
        vm.deal(bidder2, 100 ether);
    }

    function testInitializeStoresConfig() public view {
        assertEq(market.owner(), owner);
        assertEq(address(market.oracle()), address(oracle));
        assertEq(market.feeRecipient(), feeRecipient);
        assertEq(market.platformFee(), PLATFORM_FEE);
        assertEq(market.nextAuctionId(), 0);
    }

    function testCreateAuctionTransfersNftAndStoresAuction() public {
        vm.startPrank(seller);
        nft.approve(address(market), TOKEN_ID);

        vm.expectEmit(true, true, true, true, address(market));
        emit AuctionCreated(AUCTION_ID, seller, address(nft), TOKEN_ID, block.timestamp + 1 days);
        market.createAuction(address(nft), TOKEN_ID, 1 days);
        vm.stopPrank();

        AuctionMarket.Auction memory auction = market.getAuction(AUCTION_ID);
        assertEq(market.nextAuctionId(), AUCTION_ID);
        assertEq(auction.seller, seller);
        assertEq(auction.nft, address(nft));
        assertEq(auction.tokenId, TOKEN_ID);
        assertEq(auction.startTime, block.timestamp);
        assertEq(auction.endTime, block.timestamp + 1 days);
        assertEq(uint256(auction.status), uint256(AuctionMarket.AuctionStatus.Active));
        assertTrue(market.isAuctionActive(AUCTION_ID));
        assertEq(nft.ownerOf(TOKEN_ID), address(market));
    }

    function testCreateAuctionRevertsForZeroDuration() public {
        vm.startPrank(seller);
        nft.approve(address(market), TOKEN_ID);

        vm.expectRevert(AuctionMarket.InvalidDuration.selector);
        market.createAuction(address(nft), TOKEN_ID, 0);
        vm.stopPrank();
    }

    function testCreateAuctionRevertsForDurationOverflow() public {
        vm.warp(type(uint64).max);
        vm.startPrank(seller);
        nft.approve(address(market), TOKEN_ID);

        vm.expectRevert(AuctionMarket.InvalidDuration.selector);
        market.createAuction(address(nft), TOKEN_ID, 1);
        vm.stopPrank();
    }

    function testCreateAuctionRevertsWhenCallerIsNotOwner() public {
        vm.prank(attacker);
        vm.expectRevert("not owner");
        market.createAuction(address(nft), TOKEN_ID, 1 days);
    }

    function testCreateAuctionRevertsWhenPaused() public {
        vm.prank(owner);
        market.pause();

        vm.startPrank(seller);
        nft.approve(address(market), TOKEN_ID);

        vm.expectRevert();
        market.createAuction(address(nft), TOKEN_ID, 1 days);
        vm.stopPrank();
    }

    function testCancelAuctionReturnsNft() public {
        _createAuction();

        vm.prank(seller);
        vm.expectEmit(true, true, true, true, address(market));
        emit AuctionCancelledEvent(AUCTION_ID);
        market.cancelAuction(AUCTION_ID);

        AuctionMarket.Auction memory auction = market.getAuction(AUCTION_ID);
        assertEq(uint256(auction.status), uint256(AuctionMarket.AuctionStatus.Cancelled));
        assertFalse(market.isAuctionActive(AUCTION_ID));
        assertEq(nft.ownerOf(TOKEN_ID), seller);
    }

    function testCancelAuctionRevertsForUnknownAuction() public {
        vm.expectRevert(AuctionMarket.AuctionNotFound.selector);
        market.cancelAuction(AUCTION_ID);
    }

    function testCancelAuctionRevertsWhenCallerIsNotSeller() public {
        _createAuction();

        vm.prank(attacker);
        vm.expectRevert(AuctionMarket.NotSeller.selector);
        market.cancelAuction(AUCTION_ID);
    }

    function testCancelAuctionRevertsAfterBid() public {
        _createAuction();
        _bidEth(bidder1, 1 ether);

        vm.prank(seller);
        vm.expectRevert(AuctionMarket.AlreadyHasBid.selector);
        market.cancelAuction(AUCTION_ID);
    }

    function testCancelAuctionRevertsWhenAlreadyCancelled() public {
        _createAuction();

        vm.startPrank(seller);
        market.cancelAuction(AUCTION_ID);

        vm.expectRevert(AuctionMarket.AuctionCancelled.selector);
        market.cancelAuction(AUCTION_ID);
        vm.stopPrank();
    }

    function testCancelAuctionRevertsWhenEnded() public {
        _createAuction();
        vm.warp(block.timestamp + 1 days);
        market.endAuction(AUCTION_ID);

        vm.prank(seller);
        vm.expectRevert(AuctionMarket.AuctionEnded.selector);
        market.cancelAuction(AUCTION_ID);
    }

    function testBidETHStoresHighestBid() public {
        _createAuction();

        vm.prank(bidder1);
        vm.expectEmit(true, true, true, true, address(market));
        emit BidPlaced(AUCTION_ID, bidder1, address(0), 1 ether, 3000e18);
        market.bidETH{value: 1 ether}(AUCTION_ID);

        (address bidder, address bidToken, uint256 amount, uint256 usdValue) = market.getHighestBid(AUCTION_ID);
        assertEq(bidder, bidder1);
        assertEq(bidToken, address(0));
        assertEq(amount, 1 ether);
        assertEq(usdValue, 3000e18);
        assertEq(address(market).balance, 1 ether);
    }

    function testBidERC20StoresHighestBid() public {
        _createAuction();

        vm.startPrank(bidder1);
        usdc.approve(address(market), 2_000e6);
        market.bidERC20(AUCTION_ID, address(usdc), 2_000e6);
        vm.stopPrank();

        (address bidder, address bidToken, uint256 amount, uint256 usdValue) = market.getHighestBid(AUCTION_ID);
        assertEq(bidder, bidder1);
        assertEq(bidToken, address(usdc));
        assertEq(amount, 2_000e6);
        assertEq(usdValue, 2_000e18);
        assertEq(usdc.balanceOf(address(market)), 2_000e6);
    }

    function testHigherETHBidRefundsPreviousETHBid() public {
        _createAuction();
        _bidEth(bidder1, 1 ether);

        vm.prank(bidder2);
        market.bidETH{value: 2 ether}(AUCTION_ID);

        assertEq(bidder1.balance, 100 ether);
        assertEq(address(market).balance, 2 ether);

        (address bidder,, uint256 amount, uint256 usdValue) = market.getHighestBid(AUCTION_ID);
        assertEq(bidder, bidder2);
        assertEq(amount, 2 ether);
        assertEq(usdValue, 6000e18);
    }

    function testHigherERC20BidRefundsPreviousERC20Bid() public {
        _createAuction();

        vm.startPrank(bidder1);
        usdc.approve(address(market), 2_000e6);
        market.bidERC20(AUCTION_ID, address(usdc), 2_000e6);
        vm.stopPrank();

        vm.startPrank(bidder2);
        usdc.approve(address(market), 3_000e6);
        market.bidERC20(AUCTION_ID, address(usdc), 3_000e6);
        vm.stopPrank();

        assertEq(usdc.balanceOf(bidder1), 10_000e6);
        assertEq(usdc.balanceOf(address(market)), 3_000e6);
    }

    function testHigherETHBidRefundsPreviousERC20Bid() public {
        _createAuction();

        vm.startPrank(bidder1);
        usdc.approve(address(market), 2_000e6);
        market.bidERC20(AUCTION_ID, address(usdc), 2_000e6);
        vm.stopPrank();

        _bidEth(bidder2, 1 ether);

        assertEq(usdc.balanceOf(bidder1), 10_000e6);
        assertEq(usdc.balanceOf(address(market)), 0);
        assertEq(address(market).balance, 1 ether);
    }

    function testHigherERC20BidRefundsPreviousETHBid() public {
        _createAuction();
        _bidEth(bidder1, 1 ether);

        vm.startPrank(bidder2);
        usdc.approve(address(market), 4_000e6);
        market.bidERC20(AUCTION_ID, address(usdc), 4_000e6);
        vm.stopPrank();

        assertEq(bidder1.balance, 100 ether);
        assertEq(address(market).balance, 0);
        assertEq(usdc.balanceOf(address(market)), 4_000e6);
    }

    function testBidRevertsWhenAuctionMissing() public {
        vm.expectRevert(AuctionMarket.AuctionNotFound.selector);
        market.bidETH{value: 1 ether}(AUCTION_ID);
    }

    function testBidRevertsWhenAuctionCancelled() public {
        _createAuction();
        vm.prank(seller);
        market.cancelAuction(AUCTION_ID);

        vm.expectRevert(AuctionMarket.AuctionCancelled.selector);
        market.bidETH{value: 1 ether}(AUCTION_ID);
    }

    function testBidRevertsWhenAuctionEndedByTime() public {
        _createAuction();
        vm.warp(block.timestamp + 1 days);

        vm.expectRevert(AuctionMarket.AuctionEnded.selector);
        market.bidETH{value: 1 ether}(AUCTION_ID);
    }

    function testBidRevertsWhenAuctionStatusEnded() public {
        _createAuction();
        vm.warp(block.timestamp + 1 days);
        market.endAuction(AUCTION_ID);

        vm.expectRevert(AuctionMarket.AuctionEnded.selector);
        market.bidETH{value: 1 ether}(AUCTION_ID);
    }

    function testBidRevertsWhenAlreadyHighestBidder() public {
        _createAuction();
        _bidEth(bidder1, 1 ether);

        vm.prank(bidder1);
        vm.expectRevert(AuctionMarket.AlreadyHighestBidder.selector);
        market.bidETH{value: 2 ether}(AUCTION_ID);
    }

    function testBidRevertsWhenBidIsNotHigherInUsd() public {
        _createAuction();
        _bidEth(bidder1, 1 ether);

        vm.prank(bidder2);
        vm.expectRevert(AuctionMarket.InvalidBid.selector);
        market.bidETH{value: 1 ether}(AUCTION_ID);
    }

    function testBidERC20RevertsWhenBidIsNotHigherInUsd() public {
        _createAuction();
        _bidEth(bidder1, 1 ether);

        vm.startPrank(bidder2);
        usdc.approve(address(market), 3_000e6);

        vm.expectRevert(AuctionMarket.InvalidBid.selector);
        market.bidERC20(AUCTION_ID, address(usdc), 3_000e6);
        vm.stopPrank();
    }

    function testBidERC20RevertsForUnsupportedToken() public {
        _createAuction();

        vm.startPrank(bidder1);
        unsupportedToken.approve(address(market), 1 ether);

        vm.expectRevert(AuctionMarket.UnsupportedToken.selector);
        market.bidERC20(AUCTION_ID, address(unsupportedToken), 1 ether);
        vm.stopPrank();
    }

    function testBidERC20RevertsWhenAllowanceIsMissing() public {
        _createAuction();

        vm.prank(bidder1);
        vm.expectRevert();
        market.bidERC20(AUCTION_ID, address(usdc), 1_000e6);
    }

    function testBidRevertsWhenPaused() public {
        _createAuction();

        vm.prank(owner);
        market.pause();

        vm.expectRevert();
        market.bidETH{value: 1 ether}(AUCTION_ID);
    }

    function testEndAuctionNoBidsReturnsNftToSeller() public {
        _createAuction();
        vm.warp(block.timestamp + 1 days);

        vm.expectEmit(true, true, true, true, address(market));
        emit AuctionEndedEvent(AUCTION_ID, address(0), address(0), 0, 0);
        market.endAuction(AUCTION_ID);

        AuctionMarket.Auction memory auction = market.getAuction(AUCTION_ID);
        assertEq(uint256(auction.status), uint256(AuctionMarket.AuctionStatus.Ended));
        assertEq(nft.ownerOf(TOKEN_ID), seller);
        assertFalse(market.isAuctionActive(AUCTION_ID));
    }

    function testEndAuctionWithETHSettlesFeeRoyaltySellerAndTransfersNft() public {
        _createAuction();
        _bidEth(bidder1, 2 ether);
        vm.warp(block.timestamp + 1 days);

        vm.expectEmit(true, true, true, true, address(market));
        emit AuctionEndedEvent(AUCTION_ID, bidder1, address(0), 2 ether, 6000e18);
        market.endAuction(AUCTION_ID);

        assertEq(nft.ownerOf(TOKEN_ID), bidder1);
        assertEq(feeRecipient.balance, 0.05 ether);
        assertEq(royaltyReceiver.balance, 0.1 ether);
        assertEq(seller.balance, 1.85 ether);
        assertEq(address(market).balance, 0);
    }

    function testEndAuctionWithERC20SettlesFeeRoyaltySellerAndTransfersNft() public {
        _createAuction();

        vm.startPrank(bidder1);
        usdc.approve(address(market), 2_000e6);
        market.bidERC20(AUCTION_ID, address(usdc), 2_000e6);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days);
        market.endAuction(AUCTION_ID);

        assertEq(nft.ownerOf(TOKEN_ID), bidder1);
        assertEq(usdc.balanceOf(feeRecipient), 50e6);
        assertEq(usdc.balanceOf(royaltyReceiver), 100e6);
        assertEq(usdc.balanceOf(seller), 1_850e6);
        assertEq(usdc.balanceOf(address(market)), 0);
    }

    function testEndAuctionWithNoRoyaltyNftPaysOnlyFeeAndSeller() public {
        _createNoRoyaltyAuction();
        _bidEth(bidder1, 2 ether);
        vm.warp(block.timestamp + 1 days);

        market.endAuction(AUCTION_ID);

        assertEq(nftNoRoyalty.ownerOf(TOKEN_ID), bidder1);
        assertEq(feeRecipient.balance, 0.05 ether);
        assertEq(seller.balance, 1.95 ether);
        assertEq(royaltyReceiver.balance, 0);
    }

    function testEndAuctionRevertsWhenFeePlusRoyaltyExceedsBidAmount() public {
        vm.prank(owner);
        nft.setTokenRoyalty(TOKEN_ID, royaltyReceiver, 9500);

        vm.prank(owner);
        market.setPlatformFee(1000);

        _createAuction();
        _bidEth(bidder1, 2 ether);
        vm.warp(block.timestamp + 1 days);

        vm.expectRevert("invalid fee");
        market.endAuction(AUCTION_ID);
    }

    function testEndAuctionRevertsWhenEthPaymentFails() public {
        RejectETH rejectETH = new RejectETH();

        vm.prank(owner);
        market.setFeeRecipient(address(rejectETH));

        _createAuction();
        _bidEth(bidder1, 2 ether);
        vm.warp(block.timestamp + 1 days);

        vm.expectRevert("eth transfer failed");
        market.endAuction(AUCTION_ID);
    }

    function testEndAuctionRevertsBeforeEndTime() public {
        _createAuction();

        vm.expectRevert(AuctionMarket.AuctionNotEnded.selector);
        market.endAuction(AUCTION_ID);
    }

    function testEndAuctionRevertsForUnknownAuction() public {
        vm.expectRevert(AuctionMarket.AuctionNotFound.selector);
        market.endAuction(AUCTION_ID);
    }

    function testEndAuctionRevertsWhenCancelled() public {
        _createAuction();
        vm.prank(seller);
        market.cancelAuction(AUCTION_ID);

        vm.expectRevert(AuctionMarket.AuctionCancelled.selector);
        market.endAuction(AUCTION_ID);
    }

    function testEndAuctionRevertsWhenAlreadyEnded() public {
        _createAuction();
        vm.warp(block.timestamp + 1 days);
        market.endAuction(AUCTION_ID);

        vm.expectRevert(AuctionMarket.AuctionEnded.selector);
        market.endAuction(AUCTION_ID);
    }

    function testAdminCanSetOracle() public {
        PriceOracle newOracleImpl = new PriceOracle();
        PriceOracle newOracle = PriceOracle(
            address(new ERC1967Proxy(address(newOracleImpl), abi.encodeCall(PriceOracle.initialize, (owner))))
        );

        vm.prank(owner);
        market.setOracle(address(newOracle));

        assertEq(address(market.oracle()), address(newOracle));
    }

    function testOnlyOwnerCanSetOracle() public {
        vm.prank(attacker);
        vm.expectRevert();
        market.setOracle(address(oracle));
    }

    function testAdminCanSetPlatformFee() public {
        vm.prank(owner);
        market.setPlatformFee(1000);

        assertEq(market.platformFee(), 1000);
    }

    function testSetPlatformFeeRevertsAboveTenPercent() public {
        vm.prank(owner);
        vm.expectRevert("max 10%");
        market.setPlatformFee(1001);
    }

    function testOnlyOwnerCanSetPlatformFee() public {
        vm.prank(attacker);
        vm.expectRevert();
        market.setPlatformFee(100);
    }

    function testAdminCanSetFeeRecipient() public {
        vm.prank(owner);
        market.setFeeRecipient(newFeeRecipient);

        assertEq(market.feeRecipient(), newFeeRecipient);
    }

    function testSetFeeRecipientRevertsForZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert("zero address");
        market.setFeeRecipient(address(0));
    }

    function testOnlyOwnerCanSetFeeRecipient() public {
        vm.prank(attacker);
        vm.expectRevert();
        market.setFeeRecipient(newFeeRecipient);
    }

    function testOwnerCanPauseAndUnpause() public {
        vm.startPrank(owner);
        market.pause();
        assertTrue(market.paused());

        market.unpause();
        assertFalse(market.paused());
        vm.stopPrank();
    }

    function testOnlyOwnerCanPauseAndUnpause() public {
        vm.prank(attacker);
        vm.expectRevert();
        market.pause();

        vm.prank(owner);
        market.pause();

        vm.prank(attacker);
        vm.expectRevert();
        market.unpause();
    }

    function testUpgradeToAuctionMarketV2InitializesVersionAndKeepsState() public {
        _createAuction();

        AuctionMarketV2 impl = new AuctionMarketV2();

        vm.prank(owner);
        vm.expectEmit(true, true, true, true, address(market));
        emit VersionUpgraded(1, 2);
        market.upgradeToAndCall(address(impl), abi.encodeCall(AuctionMarketV2.initializeV2, (2)));

        AuctionMarketV2 marketV2 = AuctionMarketV2(payable(address(market)));
        AuctionMarket.Auction memory auction = marketV2.getAuction(AUCTION_ID);

        assertEq(marketV2.version(), 2);
        assertEq(marketV2.owner(), owner);
        assertEq(address(marketV2.oracle()), address(oracle));
        assertEq(marketV2.feeRecipient(), feeRecipient);
        assertEq(marketV2.platformFee(), PLATFORM_FEE);
        assertEq(marketV2.nextAuctionId(), AUCTION_ID);
        assertEq(auction.seller, seller);
        assertEq(auction.nft, address(nft));
        assertEq(auction.tokenId, TOKEN_ID);
        assertEq(uint256(auction.status), uint256(AuctionMarket.AuctionStatus.Active));

        vm.prank(bidder1);
        marketV2.bidETH{value: 1 ether}(AUCTION_ID);

        (address bidder, address bidToken, uint256 amount, uint256 usdValue) = marketV2.getHighestBid(AUCTION_ID);
        assertEq(bidder, bidder1);
        assertEq(bidToken, address(0));
        assertEq(amount, 1 ether);
        assertEq(usdValue, 3000e18);
    }

    function testOnlyOwnerCanUpgradeToAuctionMarketV2() public {
        AuctionMarketV2 impl = new AuctionMarketV2();

        vm.prank(attacker);
        vm.expectRevert();
        market.upgradeToAndCall(address(impl), abi.encodeCall(AuctionMarketV2.initializeV2, (2)));
    }

    function testReceiveETH() public {
        vm.deal(attacker, 1 ether);

        vm.prank(attacker);
        (bool success,) = address(market).call{value: 1 ether}("");

        assertTrue(success);
        assertEq(address(market).balance, 1 ether);
    }

    function _createAuction() internal {
        vm.startPrank(seller);
        nft.approve(address(market), TOKEN_ID);
        market.createAuction(address(nft), TOKEN_ID, 1 days);
        vm.stopPrank();
    }

    function _createNoRoyaltyAuction() internal {
        vm.startPrank(seller);
        nftNoRoyalty.approve(address(market), TOKEN_ID);
        market.createAuction(address(nftNoRoyalty), TOKEN_ID, 1 days);
        vm.stopPrank();
    }

    function _bidEth(address bidder, uint256 amount) internal {
        vm.prank(bidder);
        market.bidETH{value: amount}(AUCTION_ID);
    }
}
