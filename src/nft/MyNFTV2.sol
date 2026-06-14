// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./MyNFT.sol";

contract MyNFTV2 is MyNFT {
    function version() external pure returns (uint256) {
        return 2;
    }
}
