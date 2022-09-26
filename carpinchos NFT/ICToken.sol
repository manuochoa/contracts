// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

interface ICToken {
    function name() external view returns (string memory);
  function maxSupply() external view returns (uint256);
  function claim(address wallet, uint256 tokenAmount) external;
  function pay(uint256) external;
  function treasuryWallet() external view returns (address);
}
