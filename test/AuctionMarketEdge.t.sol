// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./AuctionMarket.t.sol";

contract AuctionMarketEdgeTest is AuctionMarketTest {
    // =====================================================
    // Create Auction
    // =====================================================

    function testRevertCreateAuctionWithZeroDuration() public {
        vm.startPrank(seller);

        nft.approve(address(market), 1);

        vm.expectRevert(AuctionMarket.InvalidDuration.selector);

        market.createAuction(address(nft), 1, 0);

        vm.stopPrank();
    }

    function testRevertCreateAuctionWithOverflowDuration() public {
        vm.startPrank(seller);

        nft.approve(address(market), 1);

        vm.expectRevert(AuctionMarket.InvalidDuration.selector);

        market.createAuction(address(nft), 1, type(uint64).max);

        vm.stopPrank();
    }

    // =====================================================
    // Cancel Auction
    // =====================================================

    function testCancelAuction() public {
        _createAuction();

        vm.prank(seller);

        market.cancelAuction(1);

        AuctionMarket.Auction memory auction = market.getAuction(1);

        assertEq(uint256(auction.status), uint256(AuctionMarket.AuctionStatus.Cancelled));

        assertEq(nft.ownerOf(1), seller);
    }

    function testRevertCancelAlreadyCancelled() public {
        _createAuction();

        vm.prank(seller);

        market.cancelAuction(1);

        vm.prank(seller);

        vm.expectRevert(AuctionMarket.AuctionCancelled.selector);

        market.cancelAuction(1);
    }

    function testRevertCancelByNonSeller() public {
        _createAuction();

        vm.prank(bidder1);

        vm.expectRevert(AuctionMarket.NotSeller.selector);

        market.cancelAuction(1);
    }

    function testRevertCancelAfterBid() public {
        _createAuction();

        vm.prank(bidder1);

        market.bidETH{value: 1 ether}(1);

        vm.prank(seller);

        vm.expectRevert(AuctionMarket.AlreadyHasBid.selector);

        market.cancelAuction(1);
    }

    // =====================================================
    // Unsupported Token
    // =====================================================

    function testUnsupportedToken() public {
        _createAuction();

        MockERC20 fakeToken = new MockERC20("FAKE", "FAKE", 18);

        fakeToken.mint(bidder1, 1000 ether);

        vm.startPrank(bidder1);

        fakeToken.approve(address(market), type(uint256).max);

        vm.expectRevert(AuctionMarket.UnsupportedToken.selector);

        market.bidERC20(1, address(fakeToken), 100 ether);

        vm.stopPrank();
    }

    // =====================================================
    // Invalid Bid
    // =====================================================

    function testLowerBidReverts() public {
        _createAuction();

        vm.prank(bidder1);

        market.bidETH{value: 2 ether}(1);

        vm.prank(bidder2);

        vm.expectRevert(AuctionMarket.InvalidBid.selector);

        market.bidETH{value: 1 ether}(1);
    }

    // =====================================================
    // Auction Not Ended
    // =====================================================

    function testEndAuctionTooEarly() public {
        _createAuction();

        vm.expectRevert(AuctionMarket.AuctionNotEnded.selector);

        market.endAuction(1);
    }

    // =====================================================
    // No Bid
    // =====================================================

    function testEndAuctionWithoutBid() public {
        _createAuction();

        vm.warp(block.timestamp + 2 days);

        market.endAuction(1);

        AuctionMarket.Auction memory auction = market.getAuction(1);

        assertEq(uint256(auction.status), uint256(AuctionMarket.AuctionStatus.Ended));

        assertEq(nft.ownerOf(1), seller);
    }

    // =====================================================
    // Auction Ended
    // =====================================================

    function testCannotBidAfterEnded() public {
        _createAuction();

        vm.warp(block.timestamp + 2 days);

        market.endAuction(1);

        AuctionMarket.Auction memory auction = market.getAuction(1);

        assertEq(uint256(auction.status), uint256(AuctionMarket.AuctionStatus.Ended));

        vm.prank(bidder1);

        vm.expectRevert(AuctionMarket.AuctionEnded.selector);

        market.bidETH{value: 1 ether}(1);
    }

    // =====================================================
    // Pause
    // =====================================================

    function testPauseCreateAuction() public {
        vm.prank(owner);

        market.pause();

        vm.startPrank(seller);

        nft.approve(address(market), 1);

        vm.expectRevert();

        market.createAuction(address(nft), 1, 1 days);

        vm.stopPrank();
    }

    function testPauseBid() public {
        _createAuction();

        vm.prank(owner);

        market.pause();

        vm.prank(bidder1);

        vm.expectRevert();

        market.bidETH{value: 1 ether}(1);
    }

    // =====================================================
    // Withdraw
    // =====================================================

    function testWithdrawETH() public {
        _createAuction();

        vm.prank(bidder1);

        market.bidETH{value: 1 ether}(1);

        vm.prank(bidder2);

        market.bidETH{value: 2 ether}(1);

        uint256 beforeBalance = bidder1.balance;

        vm.prank(bidder1);

        market.withdraw(address(0));

        assertEq(bidder1.balance, beforeBalance + 1 ether);
    }

    // =====================================================
    // Auction Not Found
    // =====================================================

    function testAuctionNotFound() public {
        vm.expectRevert(AuctionMarket.AuctionNotFound.selector);

        market.endAuction(999);
    }

    // =====================================================
    // Royalty
    // =====================================================

    function testRoyaltyPayment() public {
        _createAuction();

        vm.prank(bidder1);

        market.bidETH{value: 10 ether}(1);

        uint256 royaltyBefore = royaltyReceiver.balance;

        vm.warp(block.timestamp + 2 days);

        market.endAuction(1);

        assertGt(royaltyReceiver.balance, royaltyBefore);
    }
}
