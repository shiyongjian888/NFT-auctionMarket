// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721URIStorageUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/common/ERC2981Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title NFT合约 
 * @notice 支持升级、暂停
 */
contract MyNFT is
    Initializable,
    ERC721Upgradeable,
    ERC721URIStorageUpgradeable,
    ERC2981Upgradeable,
    OwnableUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable
{
    // =====================================================
    // 自定义错误
    // =====================================================

    error MaxSupplyReached();
    error InvalidMaxSupply();
    error TokenNotExist();

    // =====================================================
    // 事件定义
    // =====================================================

    event Minted(address indexed to, uint256 indexed tokenId, string uri);

    event BatchMinted(address indexed to, uint256 amount);

    event MaxSupplyUpdated(uint256 oldMaxSupply, uint256 newMaxSupply);

    // =====================================================
    // 状态变量
    // =====================================================

    uint256 private _nextTokenId;

    uint256 public maxSupply;

    uint256 public totalMinted;

    string private _baseTokenURI;

    // =====================================================
    // 初始化
    // =====================================================

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        string memory name_,
        string memory symbol_,
        uint256 maxSupply_,
        address royaltyReceiver_,
        uint96 royaltyFee_
    ) external initializer {
        require(maxSupply_ > 0, "Invalid supply");

        __ERC721_init(name_, symbol_);

        __ERC721URIStorage_init();

        __ERC2981_init();

        __Ownable_init(msg.sender);

        __Pausable_init();

        __UUPSUpgradeable_init();

        maxSupply = maxSupply_;

        _nextTokenId = 1;

        _setDefaultRoyalty(royaltyReceiver_, royaltyFee_);
    }

    // =====================================================
    // 铸造
    // =====================================================

    function mint(address to, string calldata uri) external onlyOwner whenNotPaused returns (uint256 tokenId) {
        if (totalMinted >= maxSupply) revert MaxSupplyReached();

        tokenId = _nextTokenId++;
        ++totalMinted;
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, uri);
        emit Minted(to, tokenId, uri);
    }
    
    // =====================================================
    // 批量铸造
    // =====================================================
    function batchMint(address to, string[] calldata uris) external onlyOwner whenNotPaused {
        uint256 len = uris.length;

        if (totalMinted + len > maxSupply) {
            revert MaxSupplyReached();
        }

        for (uint256 i; i < len; ++i) {
            uint256 tokenId = _nextTokenId++;

            ++totalMinted;

            _safeMint(to, tokenId);

            _setTokenURI(tokenId, uris[i]);
        }

        emit BatchMinted(to, len);
    }

    // =====================================================
    // Royalty
    // =====================================================

    function setDefaultRoyalty(address receiver, uint96 feeNumerator) external onlyOwner {
        _setDefaultRoyalty(receiver, feeNumerator);
    }

    function setTokenRoyalty(uint256 tokenId, address receiver, uint96 feeNumerator) external onlyOwner {
        _setTokenRoyalty(tokenId, receiver, feeNumerator);
    }

    function resetTokenRoyalty(uint256 tokenId) external onlyOwner {
        _resetTokenRoyalty(tokenId);
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

    function setBaseURI(string calldata baseURI_) external onlyOwner {
        _baseTokenURI = baseURI_;
    }

    function setMaxSupply(uint256 newMaxSupply) external onlyOwner {
        if (newMaxSupply < totalMinted) {
            revert InvalidMaxSupply();
        }

        emit MaxSupplyUpdated(maxSupply, newMaxSupply);

        maxSupply = newMaxSupply;
    }

    // =====================================================
    // Views
    // =====================================================

    function exists(uint256 tokenId) external view returns (bool) {
        return _ownerOf(tokenId) != address(0);
    }

    function remainingSupply() external view returns (uint256) {
        return maxSupply - totalMinted;
    }

    function nextTokenId() external view returns (uint256) {
        return _nextTokenId;
    }

    // =====================================================
    // Overrides
    // =====================================================

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721Upgradeable, ERC721URIStorageUpgradeable)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721Upgradeable, ERC721URIStorageUpgradeable, ERC2981Upgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
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
