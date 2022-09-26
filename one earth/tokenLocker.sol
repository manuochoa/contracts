// SPDX-License-Identifier:MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract tokenLocker is Ownable {

    uint256 public lockersCreated;

    struct Locker{
        uint256 id;
        uint256 amount;
        uint256 releaseTime;
        uint256 tokenDecimals;
        address tokenAddress;
        address user;
        string name;
        string symbol;
    }

    mapping (address => mapping(address => Locker)) public lockerByUser; // user address => token address => locker
    mapping (uint256 => Locker) public lockerById;

    event tokensLocked(address user, address token, uint amount, uint releaseTime);
    event tokensUnlocked(address user, address token, uint amount);

    constructor() {}

    function createLocker (address tokenAddress, uint256 amount, uint256 releaseTime) external {
        require(block.timestamp < releaseTime, "Release time should be in the future");
        require(lockerByUser[msg.sender][tokenAddress].amount == 0, "Locker already active for this token");
        ERC20 token = ERC20(tokenAddress);
        token.transferFrom(msg.sender, address(this), amount);

        uint256 id = lockersCreated;
        lockerById[id] = Locker({
            id: id,
            amount: amount,
            releaseTime: releaseTime,
            tokenDecimals: token.decimals(),
            tokenAddress: tokenAddress,
            user: msg.sender,
            name: token.name(),
            symbol: token.symbol()
        });

        lockerByUser[msg.sender][tokenAddress] = lockerById[id];

        lockersCreated++;

        emit tokensLocked(msg.sender, tokenAddress, amount, releaseTime);
    }

    function claimTokens (address tokenAddress) external {
        Locker memory locker = lockerByUser[msg.sender][tokenAddress];
        require(locker.releaseTime < block.timestamp, "Tokens not ready to claim");

        uint256 amountToTranfer = locker.amount;
        require(amountToTranfer > 0, "no tokens to claim");

        delete lockerByUser[msg.sender][tokenAddress];
        delete lockerById[locker.id];

        IERC20(tokenAddress).transfer(msg.sender, amountToTranfer);

        emit tokensUnlocked(msg.sender, tokenAddress, amountToTranfer);
    }

}