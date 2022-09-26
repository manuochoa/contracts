// SPDX-License-Identifier: MIT LICENSE

pragma solidity ^0.8.0;

interface IMine {
    function addManyToMineAndPack(address account, uint256[] calldata tokenIds)
        external;

    function randomBadApeOwner(uint256 seed) external view returns (address);

    function getTokensForOwner(address owner)
        external
        view
        returns (uint256[] memory);
}
