// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/interfaces/IERC2981.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "../interfaces/IPriceOracle.sol";

/**
 * @title 拍卖合约 
 * @notice 支持升级、暂停
 */
contract AuctionMarket is
    Initializable,
    OwnableUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable,
    ERC721Holder
{
    using SafeERC20 for IERC20;

    // =====================================================
    // 自定义错误
    // =====================================================

    error AuctionNotFound();
    error AuctionEnded();
    error AuctionCancelled();
    error AuctionNotEnded();
    error InvalidBid();
    error NotSeller();
    error UnsupportedToken();
    error AlreadyHasBid();
    error InvalidDuration();

    // =====================================================
    // 事件
    // =====================================================

    event AuctionCreated(
        uint256 indexed auctionId, address indexed seller, address indexed nft, uint256 tokenId, uint256 endTime
    );

    event AuctionCancelledEvent(uint256 indexed auctionId);

    event BidPlaced(
        uint256 indexed auctionId, address indexed bidder, address bidToken, uint256 amount, uint256 usdValue
    );

    event AuctionEndedEvent(
        uint256 indexed auctionId, address winner, address bidToken, uint256 amount, uint256 usdValue
    );

    event Withdrawal(address indexed user, address token, uint256 amount);

    // =====================================================
    // 结构体
    // =====================================================

    enum AuctionStatus {
        Active,   // 开始
        Ended,    // 结束
        Cancelled // 取消
    }

    struct Auction {
        address seller; // NFT 卖家（发起拍卖的人）
        address nft; // NFT 合约地址
        address highestBidder; // 当前最高出价者
        address highestBidToken; // 出价使用的代币
        uint256 tokenId; // NFT 在该合约中的编号
        uint256 highestBidAmount; // 当前最高出价金额（原始 token 单位）
        uint256 highestBidUsd; // 折算后的 USD 价值
        uint64 startTime; // 拍卖开始时间
        uint64 endTime; // 拍卖结束时间
        AuctionStatus status; // 拍卖状态
    }

    // =====================================================
    // 状态变量
    // =====================================================

    uint256 public nextAuctionId;

    address public feeRecipient;

    IPriceOracle public oracle;

    uint96 public platformFee;

    mapping(uint256 => Auction) private auctions;

    mapping(address => uint256[]) private sellerAuctions;

    mapping(address => uint256[]) private bidderAuctions;

    mapping(address => mapping(uint256 => bool)) private bidderJoined;

    mapping(address => mapping(address => uint256)) public pendingWithdrawals;

    // =====================================================
    // Initialize 初始化
    // =====================================================

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address owner_, address oracle_, address feeRecipient_, uint96 platformFee_)
        external
        initializer
    {
        __Ownable_init(owner_);

        __Pausable_init();

        __ReentrancyGuard_init();

        __UUPSUpgradeable_init();

        oracle = IPriceOracle(oracle_);

        feeRecipient = feeRecipient_;

        platformFee = platformFee_;
    }

    // =====================================================
    // 创建拍卖
    // =====================================================

    function createAuction(address nft, uint256 tokenId, uint256 duration) external whenNotPaused nonReentrant {
        if (duration == 0) {
            revert InvalidDuration();
        }

        if (block.timestamp > type(uint64).max || duration > type(uint64).max - block.timestamp) {
            revert InvalidDuration();
        }

        uint256 endTime = block.timestamp + duration;

        require(IERC721(nft).ownerOf(tokenId) == msg.sender, "not owner");

        IERC721(nft).safeTransferFrom(msg.sender, address(this), tokenId);

        uint256 auctionId = ++nextAuctionId;

        auctions[auctionId] = Auction({
            seller: msg.sender,
            nft: nft,
            highestBidder: address(0),
            highestBidToken: address(0),
            tokenId: tokenId,
            highestBidAmount: 0,
            highestBidUsd: 0,
            startTime: uint64(block.timestamp),
            endTime: uint64(endTime),
            status: AuctionStatus.Active
        });

        sellerAuctions[msg.sender].push(auctionId);

        emit AuctionCreated(auctionId, msg.sender, nft, tokenId, endTime);
    }

    // =====================================================
    // 取消拍卖
    // =====================================================

    function cancelAuction(uint256 auctionId) external nonReentrant {
        Auction storage a = auctions[auctionId];

        if (a.seller == address(0)) {
            revert AuctionNotFound();
        }

        if (msg.sender != a.seller) {
            revert NotSeller();
        }

        if (a.status == AuctionStatus.Cancelled) {
            revert AuctionCancelled();
        }

        if (a.status == AuctionStatus.Ended) {
            revert AuctionEnded();
        }

        if (a.highestBidder != address(0)) {
            revert AlreadyHasBid();
        }

        a.status = AuctionStatus.Cancelled;

        IERC721(a.nft).safeTransferFrom(address(this), a.seller, a.tokenId);

        emit AuctionCancelledEvent(auctionId);
    }

    // =====================================================
    // ETH 出价
    // =====================================================

    function bidETH(uint256 auctionId) external payable nonReentrant whenNotPaused {
        Auction storage a = auctions[auctionId];

        _validateAuctionBid(a);

        uint256 usdValue = oracle.getUsdValue(address(0), msg.value);

        if (usdValue <= a.highestBidUsd) {
            revert InvalidBid();
        }

        _refundPreviousBid(a);

        a.highestBidder = msg.sender;

        a.highestBidToken = address(0);

        a.highestBidAmount = msg.value;

        a.highestBidUsd = usdValue;

        _recordBidder(auctionId);

        emit BidPlaced(auctionId, msg.sender, address(0), msg.value, usdValue);
    }

    // =====================================================
    // ERC20 出价
    // =====================================================

    function bidERC20(uint256 auctionId, address token, uint256 amount) external nonReentrant whenNotPaused {
        if (!oracle.isSupportedToken(token)) {
            revert UnsupportedToken();
        }

        Auction storage a = auctions[auctionId];

        _validateAuctionBid(a);

        uint256 usdValue = oracle.getUsdValue(token, amount);

        if (usdValue <= a.highestBidUsd) {
            revert InvalidBid();
        }

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        _refundPreviousBid(a);

        a.highestBidder = msg.sender;

        a.highestBidToken = token;

        a.highestBidAmount = amount;

        a.highestBidUsd = usdValue;

        _recordBidder(auctionId);

        emit BidPlaced(auctionId, msg.sender, token, amount, usdValue);
    }

    // =====================================================
    // Internal  验证拍卖状态
    // =====================================================

    function _validateAuctionBid(Auction storage a) internal view {
        if (a.seller == address(0)) {
            revert AuctionNotFound();
        }

        if (a.status == AuctionStatus.Cancelled) {
            revert AuctionCancelled();
        }

        if (a.status == AuctionStatus.Ended) {
            revert AuctionEnded();
        }
        // forge-lint: disable-start(block-timestamp)
        if (block.timestamp >= a.endTime) {
            revert AuctionEnded();
        }
    }

    function _refundPreviousBid(Auction storage a) internal {
        if (a.highestBidder == address(0)) {
            return;
        }

        pendingWithdrawals[a.highestBidder][a.highestBidToken] += a.highestBidAmount;
    }
    
    // =====================================================
    // 记录出价人
    // =====================================================

    function _recordBidder(uint256 auctionId) internal {
        if (!bidderJoined[msg.sender][auctionId]) {
            bidderJoined[msg.sender][auctionId] = true;

            bidderAuctions[msg.sender].push(auctionId);
        }
    }

    // =====================================================
    // 结束拍卖
    // =====================================================

    function endAuction(uint256 auctionId) external nonReentrant {
        Auction storage a = auctions[auctionId];

        if (a.seller == address(0)) {
            revert AuctionNotFound();
        }

        if (a.status == AuctionStatus.Cancelled) {
            revert AuctionCancelled();
        }

        if (a.status == AuctionStatus.Ended) {
            revert AuctionEnded();
        }
        // forge-lint: disable-start(block-timestamp)
        if (block.timestamp < a.endTime) {
            revert AuctionNotEnded();
        }

        a.status = AuctionStatus.Ended;

        // 无人出价
        if (a.highestBidder == address(0)) {
            IERC721(a.nft).safeTransferFrom(address(this), a.seller, a.tokenId);

            emit AuctionEndedEvent(auctionId, address(0), address(0), 0, 0);

            return;
        }

        _settleAuction(a);

        IERC721(a.nft).safeTransferFrom(address(this), a.highestBidder, a.tokenId);

        emit AuctionEndedEvent(auctionId, a.highestBidder, a.highestBidToken, a.highestBidAmount, a.highestBidUsd);
    }

    // =====================================================
    // Settlement 结算拍卖
    // =====================================================

    function _settleAuction(Auction storage a) internal {
        uint256 feeAmount = (a.highestBidAmount * platformFee) / 10000;

        (address royaltyReceiver, uint256 royaltyAmount) = _getRoyaltyInfo(a.nft, a.tokenId, a.highestBidAmount);

        require(feeAmount + royaltyAmount <= a.highestBidAmount, "invalid fee");

        uint256 sellerAmount = a.highestBidAmount - feeAmount - royaltyAmount;

        _pay(a.highestBidToken, feeRecipient, feeAmount);

        if (royaltyReceiver != address(0) && royaltyAmount > 0) {
            _pay(a.highestBidToken, royaltyReceiver, royaltyAmount);
        }

        _pay(a.highestBidToken, a.seller, sellerAmount);
    }

    // =====================================================
    // Royalty 获取版税信息
    // =====================================================

    function _getRoyaltyInfo(address nft, uint256 tokenId, uint256 salePrice)
        internal
        view
        returns (address receiver, uint256 royaltyAmount)
    {
        try IERC165(nft).supportsInterface(type(IERC2981).interfaceId) returns (bool supported) {
            if (supported) {
                return IERC2981(nft).royaltyInfo(tokenId, salePrice);
            }
        } catch {}

        return (address(0), 0);
    }

    // =====================================================
    // Payment 支付
    // =====================================================

    function _pay(address token, address to, uint256 amount) internal {
        if (amount == 0) {
            return;
        }

        if (token == address(0)) {
            (bool success,) = payable(to).call{value: amount}("");

            require(success, "eth transfer failed");
        } else {
            IERC20(token).safeTransfer(to, amount);
        }
    }

    // =====================================================
    // Withdraw 取款
    // =====================================================

    function withdraw(address token) external nonReentrant {
        uint256 amount = pendingWithdrawals[msg.sender][token];

        require(amount > 0, "no balance");

        pendingWithdrawals[msg.sender][token] = 0;

        _pay(token, msg.sender, amount);

        emit Withdrawal(msg.sender, token, amount);
    }

    // =====================================================
    // Views
    // =====================================================

    function getAuction(uint256 auctionId) external view returns (Auction memory) {
        return auctions[auctionId];
    }

    function isAuctionActive(uint256 auctionId) public view returns (bool) {
        Auction storage a = auctions[auctionId];
        // forge-lint: disable-start(block-timestamp)
        return a.status == AuctionStatus.Active && block.timestamp < a.endTime;
    }

    function getHighestBid(uint256 auctionId)
        external
        view
        returns (address bidder, address bidToken, uint256 amount, uint256 usdValue)
    {
        Auction storage a = auctions[auctionId];

        return (a.highestBidder, a.highestBidToken, a.highestBidAmount, a.highestBidUsd);
    }

    function getSellerAuctions(address seller) external view returns (uint256[] memory) {
        return sellerAuctions[seller];
    }

    function getBidderAuctions(address bidder) external view returns (uint256[] memory) {
        return bidderAuctions[bidder];
    }

    function getPendingWithdrawal(address user, address token) external view returns (uint256) {
        return pendingWithdrawals[user][token];
    }

    // =====================================================
    // Admin
    // =====================================================

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function setOracle(address oracle_) external onlyOwner {
        oracle = IPriceOracle(oracle_);
    }

    function setPlatformFee(uint96 fee_) external onlyOwner {
        require(fee_ <= 1000, "max 10%");

        platformFee = fee_;
    }

    function setFeeRecipient(address recipient) external onlyOwner {
        require(recipient != address(0), "zero address");

        feeRecipient = recipient;
    }

    // =====================================================
    // UUPS
    // =====================================================

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    receive() external payable {}

    // =====================================================
    // Storage Gap
    // =====================================================

    uint256[50] private __gap;
}
