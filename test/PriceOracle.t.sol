// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import "../src/oracle/PriceOracle.sol";
import "../src/oracle/PriceOracleV2.sol";
import "../src/mocks/MockV3Aggregator.sol";
import "../src/mocks/MockERC20.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract PriceOracleTest is Test {
    PriceOracle oracle;

    MockV3Aggregator ethFeed;
    MockV3Aggregator usdcFeed;

    MockERC20 usdc;

    address owner = address(1);
    address token = address(2);

    function setUp() public {
        vm.startPrank(owner);

        PriceOracle impl = new PriceOracle();

        oracle = PriceOracle(address(new ERC1967Proxy(address(impl), abi.encodeCall(PriceOracle.initialize, (owner)))));

        ethFeed = new MockV3Aggregator(8, 3000e8);
        usdcFeed = new MockV3Aggregator(8, 1e8);
        usdc = new MockERC20("USDC", "USDC", 6);

        oracle.setTokenFeed(address(0), address(ethFeed));
        oracle.setTokenFeed(address(usdc), address(usdcFeed));

        vm.stopPrank();
    }

    // =========================
    // ETH price
    // =========================

    function testETHPrice() public view {
        uint256 usd = oracle.getUsdValue(address(0), 1 ether);

        assertGt(usd, 0);
    }

    // =========================
    // ERC20 price
    // =========================

    function testTokenPrice() public view {
        uint256 usd = oracle.getUsdValue(address(usdc), 1000e6);

        assertGt(usd, 0);
    }

    // =========================
    // Feed update
    // =========================

    function testUpdateFeed() public {
        MockV3Aggregator newFeed = new MockV3Aggregator(8, 2000e8);
        vm.prank(owner);
        oracle.setTokenFeed(address(usdc), address(newFeed));

        uint256 usd = oracle.getUsdValue(address(usdc), 1000e6);

        assertGt(usd, 0);
    }

    function testRemoveTokenDisablesToken() public {
        vm.prank(owner);

        oracle.removeToken(address(usdc));

        vm.expectRevert(PriceOracle.TokenNotSupported.selector);
        oracle.getLatestPrice(address(usdc));

        vm.expectRevert(PriceOracle.TokenNotSupported.selector);
        oracle.getFeedDecimals(address(usdc));

        vm.expectRevert(PriceOracle.TokenNotSupported.selector);
        oracle.getTokenDecimals(address(usdc));

        vm.expectRevert(PriceOracle.TokenNotSupported.selector);
        oracle.getUsdValue(address(usdc), 1e6);

        vm.expectRevert(PriceOracle.TokenNotSupported.selector);
        oracle.getTokenAmountFromUsd(address(usdc), 1e18);
    }

    function testRemoveTokenConfig() public {
        vm.prank(owner);

        oracle.removeToken(address(usdc));

        (address feed, uint8 tokenDecimals, bool enabled) = oracle.getTokenConfig(address(usdc));

        assertEq(feed, address(0));
        assertEq(tokenDecimals, 0);
        assertFalse(enabled);
    }

    function testGetLatestPriceETH() public view {
        uint256 price = oracle.getLatestPrice(address(0));

        assertEq(price, 3000e8);
    }

    function testGetLatestPriceUSDC() public view {
        uint256 price = oracle.getLatestPrice(address(usdc));

        assertEq(price, 1e8);
    }

    function testGetFeedDecimals() public view {
        uint8 decimals = oracle.getFeedDecimals(address(0));

        assertEq(decimals, 8);
    }

    function testGetTokenAmountFromUsdETH() public view {
        uint256 amount = oracle.getTokenAmountFromUsd(address(0), 3000e18);

        assertEq(amount, 1e18);
    }

    function testGetTokenAmountFromUsdETHHalf() public view {
        uint256 amount = oracle.getTokenAmountFromUsd(address(0), 1500e18);

        assertEq(amount, 0.5e18);
    }

    function testGetTokenAmountFromUsdUSDC() public view {
        uint256 amount = oracle.getTokenAmountFromUsd(address(usdc), 100e18);

        assertEq(amount, 100e6);
        // USDC 6 decimals
    }

    function testGetTokenConfigUSDC() public view {
        (address feed, uint8 tokenDecimals, bool enabled) = oracle.getTokenConfig(address(usdc));

        assertEq(feed, address(usdcFeed));
        assertEq(tokenDecimals, 6);
        assertTrue(enabled);
    }

    function testGetLatestPriceAfterRemove() public {
        vm.prank(owner);

        oracle.removeToken(address(usdc));

        vm.expectRevert(PriceOracle.TokenNotSupported.selector);

        oracle.getLatestPrice(address(usdc));
    }

    // =========================
    // Unsupported token
    // =========================
    function testUnsupportedToken() public {
        vm.expectRevert(PriceOracle.TokenNotSupported.selector);

        oracle.getLatestPrice(token);
    }

    function testPauseBlocksSetTokenFeed() public {
        vm.startPrank(owner);

        oracle.pause();

        MockV3Aggregator newFeed = new MockV3Aggregator(8, 2000e8);

        vm.expectRevert();

        oracle.setTokenFeed(address(123), address(newFeed));

        vm.stopPrank();
    }

    function testPauseBlocksRemoveToken() public {
        vm.startPrank(owner);

        oracle.pause();

        vm.expectRevert();

        oracle.removeToken(address(usdc));

        vm.stopPrank();
    }

    function testUnpauseAllowsSetTokenFeed() public {
        vm.startPrank(owner);

        oracle.pause();

        oracle.unpause();

        MockV3Aggregator newFeed = new MockV3Aggregator(8, 2000e8);

        oracle.setTokenFeed(address(usdc), address(newFeed));

        vm.stopPrank();

        assertTrue(oracle.isSupportedToken(address(usdc)));
    }

    function testUnpauseAllowsRemoveToken() public {
        vm.startPrank(owner);

        oracle.pause();

        oracle.unpause();

        oracle.removeToken(address(usdc));

        vm.stopPrank();

        assertFalse(oracle.isSupportedToken(address(usdc)));
    }

    function testPauseAndUnpause() public {
        vm.startPrank(owner);

        oracle.pause();

        MockV3Aggregator newFeed = new MockV3Aggregator(8, 2000e8);

        vm.expectRevert();

        oracle.setTokenFeed(address(usdc), address(newFeed));

        oracle.unpause();

        oracle.setTokenFeed(address(usdc), address(newFeed));

        vm.stopPrank();

        assertTrue(oracle.isSupportedToken(address(usdc)));
    }

    function testPauseDoesNotAffectPriceQuery() public {
        vm.prank(owner);

        oracle.pause();

        uint256 price = oracle.getLatestPrice(address(0));

        assertEq(price, 3000e8);
    }

    function testGetTokenDecimals() public view {
        uint8 decimals = oracle.getTokenDecimals(address(usdc));

        assertEq(decimals, 6);
    }

    function testGetSupportedTokens() public view {
        address[] memory tokens = oracle.getSupportedTokens();

        assertEq(tokens.length, 2);

        assertEq(tokens[0], address(0));
        assertEq(tokens[1], address(usdc));
    }

    function testSupportedTokenCount() public view {
        assertEq(oracle.supportedTokenCount(), 2);
    }

    function testGetUsdValueUnsupportedToken() public {
        vm.expectRevert(PriceOracle.TokenNotSupported.selector);

        oracle.getUsdValue(token, 1e18);
    }

    function testGetTokenAmountFromUsdUnsupportedToken() public {
        vm.expectRevert(PriceOracle.TokenNotSupported.selector);

        oracle.getTokenAmountFromUsd(token, 100e18);
    }

    function testGetUsdValueAfterRemoveToken() public {
        vm.prank(owner);

        oracle.removeToken(address(usdc));

        vm.expectRevert(PriceOracle.TokenNotSupported.selector);

        oracle.getUsdValue(address(usdc), 100e6);
    }

    function testGetTokenAmountFromUsdAfterRemoveToken() public {
        vm.prank(owner);

        oracle.removeToken(address(usdc));

        vm.expectRevert(PriceOracle.TokenNotSupported.selector);

        oracle.getTokenAmountFromUsd(address(usdc), 100e18);
    }

    function testRemoveTokenUpdatesArray() public {
        vm.prank(owner);

        oracle.removeToken(address(usdc));

        assertEq(oracle.supportedTokenCount(), 1);

        address[] memory tokens = oracle.getSupportedTokens();

        assertEq(tokens.length, 1);
        assertEq(tokens[0], address(0));
    }

    function testUpgrade() public {
        PriceOracleV2 impl = new PriceOracleV2();

        vm.prank(owner);

        oracle.upgradeToAndCall(address(impl), "");

        assertEq(PriceOracleV2(address(oracle)).version(), 2);
    }
}
