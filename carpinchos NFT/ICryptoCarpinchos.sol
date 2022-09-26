// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

interface ICryptoCarpinchos {
    function ownerOf(uint256 tokenId) external view returns (address);

    function mintingDatetime(uint256 tokenId) external view returns (uint256);

    function usdtAvailable(uint256 tokenId) external view returns (uint256);

    function usdtNotLocked(uint256 tokenId) external view returns (uint256);

    function lockUsdt(uint256 tokenId, uint256 amount) external;

    function finishFight(
        uint256 tokenId,
        uint256 amount,
        bool wins
    ) external;

    function payFee() external;
}
