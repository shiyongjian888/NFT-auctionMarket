// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./AuctionMarket.t.sol";
import "../src/market/AuctionMarketV2.sol";
import "../src/mocks/MockNFTNoRoyalty.sol";

contract AuctionMarketSettlementTest is AuctionMarketTest {
    // =====================================================
    // ETH Settlement
    // =====================================================

    function testEndAuctionETH() public {
        _createAuction();

        vm.prank(bidder1);

        market.bidETH{value: 10 ether}(1);

        uint256 sellerBefore = seller.balance;

        uint256 feeBefore = feeRecipient.balance;

        uint256 royaltyBefore = royaltyReceiver.balance;

        vm.warp(block.timestamp + 2 days);

        market.endAuction(1);

        AuctionMarket.Auction memory auction = market.getAuction(1);

        assertEq(
            uint256(auction.status),
            uint256(AuctionMarket.AuctionStatus.Ended)
        );

        // NFT归买家

        assertEq(nft.ownerOf(1), bidder1);

        uint256 feeAmount = (10 ether * 250) / 10000;

        uint256 royaltyAmount = (10 ether * 500) / 10000;

        uint256 sellerAmount = 10 ether - feeAmount - royaltyAmount;

        assertEq(seller.balance, sellerBefore + sellerAmount);

        assertEq(feeRecipient.balance, feeBefore + feeAmount);

        assertEq(royaltyReceiver.balance, royaltyBefore + royaltyAmount);
    }

    // =====================================================
    // ERC20 Settlement
    // =====================================================

    function testEndAuctionERC20() public {
        _createAuction();

        vm.startPrank(bidder1);

        usdc.approve(address(market), 5000e6);

        market.bidERC20(1, address(usdc), 2000e6);

        vm.stopPrank();

        uint256 sellerBefore = usdc.balanceOf(seller);

        uint256 feeBefore = usdc.balanceOf(feeRecipient);

        uint256 royaltyBefore = usdc.balanceOf(royaltyReceiver);

        vm.warp(block.timestamp + 2 days);

        market.endAuction(1);

        AuctionMarket.Auction memory auction = market.getAuction(1);

        assertEq(
            uint256(auction.status),
            uint256(AuctionMarket.AuctionStatus.Ended)
        );

        assertEq(nft.ownerOf(1), bidder1);

        uint256 feeAmount = (2000e6 * 250) / 10000;

        uint256 royaltyAmount = (2000e6 * 500) / 10000;

        uint256 sellerAmount = 2000e6 - feeAmount - royaltyAmount;

        assertEq(usdc.balanceOf(seller), sellerBefore + sellerAmount);

        assertEq(usdc.balanceOf(feeRecipient), feeBefore + feeAmount);

        assertEq(
            usdc.balanceOf(royaltyReceiver),
            royaltyBefore + royaltyAmount
        );
    }

    // =====================================================
    // Highest Bid Wins
    // =====================================================

    function testHighestUsdBidWins() public {
        _createAuction();

        vm.prank(bidder1);

        market.bidETH{value: 1 ether}(1);

        // 1 ETH ≈ 3000 USD

        vm.startPrank(bidder2);

        usdc.approve(address(market), 4000e6);

        market.bidERC20(1, address(usdc), 4000e6);

        vm.stopPrank();

        vm.warp(block.timestamp + 2 days);

        market.endAuction(1);

        assertEq(nft.ownerOf(1), bidder2);
    }

    // =====================================================
    // Previous Bid Refund
    // =====================================================

    function testPreviousBidRefund() public {
        _createAuction();

        vm.prank(bidder1);

        market.bidETH{value: 1 ether}(1);

        vm.prank(bidder2);

        market.bidETH{value: 2 ether}(1);

        assertEq(market.getPendingWithdrawal(bidder1, address(0)), 1 ether);
    }

    // =====================================================
    // Multiple Out Bids
    // =====================================================

    function testMultipleOutBids() public {
        _createAuction();

        vm.prank(bidder1);

        market.bidETH{value: 1 ether}(1);

        vm.prank(bidder2);

        market.bidETH{value: 2 ether}(1);

        vm.prank(bidder1);

        market.bidETH{value: 3 ether}(1);

        assertEq(market.getPendingWithdrawal(bidder2, address(0)), 2 ether);
    }

    // =====================================================
    // Fee Update
    // =====================================================

    function testSetPlatformFee() public {
        vm.prank(owner);

        market.setPlatformFee(500);

        assertEq(market.platformFee(), 500);
    }

    function testFeeTooLarge() public {
        vm.prank(owner);

        vm.expectRevert("max 10%");

        market.setPlatformFee(1001);
    }

    // =====================================================
    // Fee Recipient
    // =====================================================

    function testSetFeeRecipient() public {
        address newRecipient = address(999);

        vm.prank(owner);

        market.setFeeRecipient(newRecipient);

        assertEq(market.feeRecipient(), newRecipient);
    }

    function testIsAuctionActive() public {
        _createAuction();

        assertTrue(market.isAuctionActive(1));

        vm.warp(block.timestamp + 2 days);

        assertFalse(market.isAuctionActive(1));
    }

    function testGetSellerAuctions() public {
        _createAuction();

        uint256[] memory auctions = market.getSellerAuctions(seller);

        assertEq(auctions.length, 1);
        assertEq(auctions[0], 1);
    }

    function testGetBidderAuctions() public {
        _createAuction();

        vm.prank(bidder1);

        market.bidETH{value: 1 ether}(1);

        uint256[] memory auctions = market.getBidderAuctions(bidder1);

        assertEq(auctions.length, 1);

        assertEq(auctions[0], 1);
    }

    function testUnpause() public {
        vm.startPrank(owner);

        market.pause();

        assertTrue(market.paused());

        market.unpause();

        assertFalse(market.paused());

        vm.stopPrank();
    }

    function testPauseAndUnpause() public {
        vm.prank(owner);
        market.pause();

        vm.startPrank(seller);

        nft.approve(address(market), 1);

        vm.expectRevert();

        market.createAuction(address(nft), 1, 1 days);

        vm.stopPrank();

        vm.prank(owner);
        market.unpause();

        _createAuction();
    }

    function testSetOracle() public {
        vm.startPrank(owner);

        PriceOracle newImpl = new PriceOracle();

        ERC1967Proxy proxy = new ERC1967Proxy(
            address(newImpl),
            abi.encodeCall(PriceOracle.initialize, (owner))
        );

        PriceOracle newOracle = PriceOracle(address(proxy));

        market.setOracle(address(newOracle));

        assertEq(address(market.oracle()), address(newOracle));

        vm.stopPrank();
    }

    function testBidETHAuctionNotFound() public {
        vm.prank(bidder1);

        vm.expectRevert(AuctionMarket.AuctionNotFound.selector);

        market.bidETH{value: 1 ether}(999);
    }

    function testBidERC20AuctionNotFound() public {
        vm.startPrank(bidder1);

        usdc.approve(address(market), 100e6);

        vm.expectRevert(AuctionMarket.AuctionNotFound.selector);

        market.bidERC20(999, address(usdc), 100e6);

        vm.stopPrank();
    }

    function testBidETHAuctionCancelled() public {
        _createAuction();

        vm.prank(seller);

        market.cancelAuction(1);

        AuctionMarket.Auction memory auction = market.getAuction(1);

        assertEq(
            uint256(auction.status),
            uint256(AuctionMarket.AuctionStatus.Cancelled)
        );

        vm.prank(bidder1);

        vm.expectRevert(AuctionMarket.AuctionCancelled.selector);

        market.bidETH{value: 1 ether}(1);
    }

    function testBidETHAuctionEnded() public {
        _createAuction();

        vm.warp(block.timestamp + 2 days);

        vm.prank(bidder1);

        vm.expectRevert(AuctionMarket.AuctionEnded.selector);

        market.bidETH{value: 1 ether}(1);
    }

    function testEndAuctionCancelled() public {
        _createAuction();

        vm.prank(seller);

        market.cancelAuction(1);

        AuctionMarket.Auction memory auction = market.getAuction(1);

        assertEq(
            uint256(auction.status),
            uint256(AuctionMarket.AuctionStatus.Cancelled)
        );

        vm.expectRevert(AuctionMarket.AuctionCancelled.selector);

        market.endAuction(1);
    }

    function testEndAuctionAlreadyEnded() public {
        _createAuction();

        vm.prank(bidder1);

        market.bidETH{value: 1 ether}(1);

        vm.warp(block.timestamp + 2 days);

        market.endAuction(1);

        AuctionMarket.Auction memory auction = market.getAuction(1);

        assertEq(
            uint256(auction.status),
            uint256(AuctionMarket.AuctionStatus.Ended)
        );

        vm.expectRevert(AuctionMarket.AuctionEnded.selector);

        market.endAuction(1);
    }

    function testCancelAuctionNotFound() public {
        vm.expectRevert(AuctionMarket.AuctionNotFound.selector);

        market.cancelAuction(1);
    }

    function testCancelAuctionAfterEnded() public {
        _createAuction();

        vm.prank(bidder1);

        market.bidETH{value: 1 ether}(1);

        vm.warp(block.timestamp + 2 days);

        market.endAuction(1);

        vm.prank(seller);

        vm.expectRevert(AuctionMarket.AuctionEnded.selector);

        market.cancelAuction(1);
    }

    function testBidERC20InvalidBidCrossToken() public {
        _createAuction();

        // 100 USD
        vm.startPrank(bidder1);

        usdc.approve(address(market), 100e6);

        market.bidERC20(1, address(usdc), 100e6);

        vm.stopPrank();

        // 70 USD
        vm.startPrank(bidder2);

        linkToken.approve(address(market), 5e18);

        vm.expectRevert(AuctionMarket.InvalidBid.selector);

        market.bidERC20(1, address(linkToken), 5e18);

        vm.stopPrank();
    }

    function testEndAuctionWithoutRoyalty() public {
        MockNFTNoRoyalty mockNft = new MockNFTNoRoyalty();

        mockNft.mint(seller, 1);

        vm.startPrank(seller);

        mockNft.approve(address(market), 1);

        market.createAuction(address(mockNft), 1, 1 days);

        vm.stopPrank();

        vm.prank(bidder1);

        market.bidETH{value: 1 ether}(1);

        vm.warp(block.timestamp + 2 days);

        market.endAuction(1);

        assertEq(mockNft.ownerOf(1), bidder1);
    }

    // =====================================================
    // UUPS Upgrade
    // =====================================================

    function testUpgrade() public {
        AuctionMarketV2 newImpl = new AuctionMarketV2();

        vm.prank(owner);

        market.upgradeToAndCall(
            address(newImpl),
            abi.encodeCall(AuctionMarketV2.initializeV2, (2))
        );

        AuctionMarketV2 upgraded = AuctionMarketV2(payable(address(market)));

        assertEq(upgraded.version(), 2);
    }

    function testUpgradeUnauthorized() public {
        AuctionMarketV2 newImpl = new AuctionMarketV2();

        vm.prank(bidder1);

        vm.expectRevert();

        market.upgradeToAndCall(
            address(newImpl),
            abi.encodeCall(AuctionMarketV2.initializeV2, (2))
        );

        // UUPSUpgradeable(address(market)).upgradeToAndCall(address(newImpl), "");
    }
}
