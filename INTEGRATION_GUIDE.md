# NFT拍卖市场 - Chainlink价格预言机集成指南

## 概述

本项目集成了Chainlink价格预言机，支持：
- ETH/USD价格获取
- ERC20/USD价格转换（如USDC、DAI等）
- 拍卖时的实时价格转换
- 支持Ethereum部署
- 支持UUPS代理升级

## 核心合约

### 1. ChainlinkPriceOracle.sol

价格预言机合约，提供以下功能：

```solidity
// 设置价格源
setTokenFeed(address token, address feed)

// 获取价格（返回Feed原始价格）
 getLatestPrice(address token) → price

// 获取统一1e18精度USD
getUsdValue(address token, uint256 amount) → price

// 返回Token最小单位
getTokenAmountFromUsd(address token, uint256 usdAmount) → tokenAmount

```

### 2. NFTAuction.sol

NFT拍卖合约，支持：
- 使用统一的USD竞价
- 支持ETH和ERC20支付
- 自动结算和平台手续费

## 使用流程

### 部署

```bash
# 编译
forge build

# 在Sepolia测试网部署
forge script script/DeployOracle.s.sol --rpc-url <RPC_URL> --broadcast

```

### 创建拍卖（美元价格）

```solidity
// 卖家创建拍卖
auction.createAuction(
    0x1234...,  // NFT合约
    tokenId,    // NFT ID
    86400       // 拍卖时长：1天
);

```

### 竞价（ETH价格）

```solidity
// 竞价$1500
auction.bidETH{value: 1 ether}(
    auctionId,
    1  // 出价1 ether
);
```

### 使用ERC20支付

```solidity
// 竞价前需要approve
LINK.approve(address(auction), amount);
auction.bidERC20(
    auctionId, 
    token,   // ERC20代币合约地址
    amount   // 金额
);
```

## Chainlink价格源配置|

### Sepolia测试网

| 代币 | 地址 | 价格源 |
|------|------|--------|
| ETH | address(0) | 0x694AA1769357215DE4FAC081bf1f309aDC325306 |
| LINK USD | 0x779877A7B0D9E8603169DdbD7836e478b4624789 | 0xc59E3633BAAC79493d908e63626716e204A45EdF |

完整列表：https://docs.chain.link/data-feeds/price-feeds/addresses

## 测试

```bash
# 运行所有测试
forge test

# 运行特定测试
forge test -k testBidETH

# 启用详细输出
forge test -vvv

# 显示燃气使用情况
forge test --gas-report
```