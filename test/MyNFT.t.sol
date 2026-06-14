// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import "../src/nft/MyNFT.sol";
import "../src/nft/MyNFTV2.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract MyNFTTest is Test {
    MyNFT nft;

    address owner = address(1);
    address user1 = address(2);
    address user2 = address(3);
    address royaltyReceiver = address(4);

    function setUp() public {
        vm.startPrank(owner);

        MyNFT impl = new MyNFT();

        ERC1967Proxy proxy = new ERC1967Proxy(
            address(impl), abi.encodeCall(MyNFT.initialize, ("MyNFT", "MNFT", 1000, royaltyReceiver, 500))
        );

        nft = MyNFT(address(proxy));

        vm.stopPrank();
    }

    // =========================
    // Mint
    // =========================

    function testMintSuccess() public {
        vm.prank(owner);

        nft.mint(user1, "ipfs://1");

        assertEq(nft.ownerOf(1), user1);
    }

    // =========================
    // Max Supply
    // =========================

    function testMaxSupplyLimit() public {
        vm.startPrank(owner);

        nft.setMaxSupply(2);
        nft.mint(user1, "ipfs://1");
        nft.mint(user1, "ipfs://2");

        vm.expectRevert(MyNFT.MaxSupplyReached.selector);

        nft.mint(user1, "ipfs://3");

        vm.stopPrank();
    }

    // =========================
    // Transfer
    // =========================

    function testTransferNFT() public {
        vm.startPrank(owner);

        nft.mint(user1, "ipfs://1");

        vm.stopPrank();

        vm.prank(user1);

        nft.transferFrom(user1, user2, 1);

        assertEq(nft.ownerOf(1), user2);
    }

    // =========================
    // Royalty
    // =========================

    function testRoyaltyInfo() public {
        vm.startPrank(owner);

        nft.mint(user1, "ipfs://1");

        vm.stopPrank();

        (address receiver, uint256 amount) = nft.royaltyInfo(1, 100 ether);

        assertEq(receiver, royaltyReceiver);
        assertEq(amount, 5 ether);
    }

    function testBatchMint() public {
        string[] memory uris = new string[](3);

        uris[0] = "1";
        uris[1] = "2";
        uris[2] = "3";

        vm.prank(owner);

        nft.batchMint(user1, uris);

        assertEq(nft.totalMinted(), 3);
        assertEq(nft.ownerOf(1), user1);
        assertEq(nft.ownerOf(2), user1);
        assertEq(nft.ownerOf(3), user1);
    }

    function testBatchMintExceedSupply() public {
        vm.startPrank(owner);

        nft.setMaxSupply(2);

        string[] memory uris = new string[](3);

        uris[0] = "1";
        uris[1] = "2";
        uris[2] = "3";

        vm.expectRevert(MyNFT.MaxSupplyReached.selector);

        nft.batchMint(user1, uris);

        vm.stopPrank();
    }

    function testBatchMintReachExactSupply() public {
        vm.startPrank(owner);

        nft.setMaxSupply(3);

        string[] memory uris = new string[](3);

        uris[0] = "1";
        uris[1] = "2";
        uris[2] = "3";

        nft.batchMint(user1, uris);

        assertEq(nft.totalMinted(), 3);

        vm.stopPrank();
    }

    function testPauseMint() public {
        vm.prank(owner);

        nft.pause();

        vm.prank(owner);

        vm.expectRevert();

        nft.mint(user1, "uri");
    }

    function testPauseAndUnpause() public {
        vm.startPrank(owner);

        nft.pause();

        vm.expectRevert();

        nft.mint(user1, "ipfs://1");

        nft.unpause();

        nft.mint(user1, "ipfs://1");

        vm.stopPrank();

        assertEq(nft.ownerOf(1), user1);
    }

    function testSetMaxSupply() public {
        vm.prank(owner);

        nft.setMaxSupply(5000);

        assertEq(nft.maxSupply(), 5000);
    }

    function testSetMaxSupplyTooSmall() public {
        vm.prank(owner);

        nft.mint(user1, "uri");

        vm.prank(owner);

        vm.expectRevert(MyNFT.InvalidMaxSupply.selector);

        nft.setMaxSupply(0);
    }

    function testExists() public {
        vm.prank(owner);

        nft.mint(user1, "uri");

        assertTrue(nft.exists(1));

        assertFalse(nft.exists(999));
    }

    function testNextTokenId() public {
        assertEq(nft.nextTokenId(), 1);

        vm.prank(owner);

        nft.mint(user1, "uri");

        assertEq(nft.nextTokenId(), 2);
    }

    function testRemainingSupply() public {
        vm.prank(owner);

        nft.mint(user1, "uri");

        assertEq(nft.remainingSupply(), 999);
    }

    function testTokenRoyalty() public {
        vm.prank(owner);

        nft.mint(user1, "uri");

        vm.prank(owner);

        nft.setTokenRoyalty(1, user2, 1000);

        (address receiver, uint256 amount) = nft.royaltyInfo(1, 100 ether);

        assertEq(receiver, user2);
        assertEq(amount, 10 ether);
    }

    function testResetTokenRoyalty() public {
        vm.prank(owner);

        nft.mint(user1, "uri");

        vm.startPrank(owner);

        nft.setTokenRoyalty(1, user2, 1000);

        nft.resetTokenRoyalty(1);

        vm.stopPrank();

        (address receiver, uint256 amount) = nft.royaltyInfo(1, 100 ether);

        assertEq(receiver, royaltyReceiver);
        assertEq(amount, 5 ether);
    }

    function testSetDefaultRoyalty() public {
        vm.prank(owner);

        nft.setDefaultRoyalty(user2, 1000);

        (address receiver, uint256 royalty) = nft.royaltyInfo(1, 100 ether);

        assertEq(receiver, user2);
        assertEq(royalty, 10 ether);
    }

    function testSetBaseURI() public {
        vm.prank(owner);

        nft.setBaseURI("ipfs://base/");
    }

    function testSupportsInterface() public {
        bool ok = nft.supportsInterface(type(IERC721).interfaceId);
        assertTrue(ok);
    }

    function testTokenURI() public {
        vm.prank(owner);

        nft.mint(user1, "ipfs://1");

        string memory uri = nft.tokenURI(1);

        assertEq(uri, "ipfs://1");
    }

    function testUpgradeNFT() public {
        MyNFTV2 impl = new MyNFTV2();

        vm.prank(owner);

        nft.upgradeToAndCall(address(impl), "");

        uint256 version = MyNFTV2(address(nft)).version();

        assertEq(version, 2);
    }
}
