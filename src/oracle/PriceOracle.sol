// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "../interfaces/IPriceOracle.sol";

contract PriceOracle is Initializable, OwnableUpgradeable, PausableUpgradeable, UUPSUpgradeable, IPriceOracle {
    // =====================================================
    // 常量
    // =====================================================

    address public constant ETH = address(0);

    // =====================================================
    // 自定义错误
    // =====================================================

    error FeedNotFound();
    error InvalidFeed();
    error InvalidPrice();
    error TokenNotSupported();

    // =====================================================
    // 结构体
    // =====================================================

    struct TokenConfig {
        AggregatorV3Interface feed;
        uint8 tokenDecimals;
        bool enabled;
    }

    // =====================================================
    // 事件
    // =====================================================

    event TokenSupported(address indexed token, address indexed feed, uint8 tokenDecimals);

    event TokenRemoved(address indexed token);

    // =====================================================
    // 状态变量
    // =====================================================

    mapping(address => TokenConfig) private tokenConfigs;

    address[] private supportedTokens;

    // =====================================================
    // 初始化
    // =====================================================

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address owner_) external initializer {
        __Ownable_init(owner_);
        __Pausable_init();
        __UUPSUpgradeable_init();
    }

    // =====================================================
    // 配置
    // =====================================================

    /**
     * ETH:
     * token = address(0)
     * decimals = 18
     */
    function setTokenFeed(address token, address feed) external onlyOwner whenNotPaused {
        if (feed == address(0)) revert InvalidFeed();

        uint8 decimals;

        if (token == ETH) {
            decimals = 18;
        } else {
            decimals = IERC20Metadata(token).decimals();
        }

        if (!tokenConfigs[token].enabled) {
            supportedTokens.push(token);
        }

        tokenConfigs[token] = TokenConfig({feed: AggregatorV3Interface(feed), tokenDecimals: decimals, enabled: true});

        emit TokenSupported(token, feed, decimals);
    }

    function removeToken(address token) external onlyOwner whenNotPaused {
        delete tokenConfigs[token];
        uint256 len = supportedTokens.length;

        for (uint256 i; i < len; i++) {
            if (supportedTokens[i] == token) {
                supportedTokens[i] = supportedTokens[len - 1];

                supportedTokens.pop();

                break;
            }
        }
        emit TokenRemoved(token);
    }

    // =====================================================
    // Price
    // =====================================================

    /**
     * 返回Feed原始价格
     *
     * ETH/USD
     * 3000e8
     */
    function getLatestPrice(address token) public view override returns (uint256) {
        TokenConfig storage config = tokenConfigs[token];

        if (!config.enabled) {
            revert TokenNotSupported();
        }

        (, int256 answer,, uint256 updatedAt,) = config.feed.latestRoundData();

        require(updatedAt > 0, "stale price");

        if (answer <= 0) revert InvalidPrice();

        // casting to uint256 is safe because answer is checked to be > 0
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint256(answer);
    }

    function getFeedDecimals(address token) public view returns (uint8) {
        TokenConfig storage config = tokenConfigs[token];

        if (!config.enabled) {
            revert TokenNotSupported();
        }

        return config.feed.decimals();
    }

    function getTokenDecimals(address token) public view returns (uint8) {
        TokenConfig storage config = tokenConfigs[token];

        if (!config.enabled) {
            revert TokenNotSupported();
        }

        return config.tokenDecimals;
    }

    // =====================================================
    // USD Conversion
    // =====================================================

    /**
     * 返回统一1e18精度USD
     *
     * 例：
     *
     * 1 ETH
     * =>
     * 3000e18
     *
     * 2000 USDC
     * =>
     * 2000e18
     */
    function getUsdValue(address token, uint256 amount) public view override returns (uint256) {
        TokenConfig storage config = tokenConfigs[token];

        if (!config.enabled) {
            revert TokenNotSupported();
        }

        uint256 price = getLatestPrice(token);

        uint8 feedDecimals = config.feed.decimals();

        uint8 tokenDecimals = config.tokenDecimals;

        return (amount * price * 1e18) / (10 ** tokenDecimals * 10 ** feedDecimals);
    }

    /**
     * USD -> Token
     *
     * 返回Token最小单位
     */
    function getTokenAmountFromUsd(address token, uint256 usdAmount) external view returns (uint256) {
        TokenConfig storage config = tokenConfigs[token];

        if (!config.enabled) {
            revert TokenNotSupported();
        }

        uint256 price = getLatestPrice(token);

        uint8 feedDecimals = config.feed.decimals();

        return (usdAmount * (10 ** config.tokenDecimals) * (10 ** feedDecimals)) / (price * 1e18);
    }

    // =====================================================
    // Views
    // =====================================================

    function isSupportedToken(address token) public view override returns (bool) {
        return tokenConfigs[token].enabled;
    }

    function getTokenConfig(address token) external view returns (address feed, uint8 tokenDecimals, bool enabled) {
        TokenConfig storage config = tokenConfigs[token];

        return (address(config.feed), config.tokenDecimals, config.enabled);
    }

    function getSupportedTokens() external view returns (address[] memory) {
        return supportedTokens;
    }

    function supportedTokenCount() external view returns (uint256) {
        return supportedTokens.length;
    }

    // =====================================================
    // Pause
    // =====================================================

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // =====================================================
    // UUPS
    // =====================================================

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // =====================================================
    // Storage Gap
    // =====================================================

    uint256[50] private __gap;
}
