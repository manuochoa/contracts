// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

contract AcesStaking is Ownable, Pausable {
    // Address of the token for the staking.
    IERC20 public acceptedToken;

    uint256 earlyWithdrawFee = 10;

    // Struc with user details.
    struct User {
        uint256 balance;
        uint256 claimed;
        uint256 started;
        uint256 lastClaim;
        uint256 unlockTime;
    }

    struct Level {
        uint256 APY;
        uint256 lockPeriod;
    }

    // Mapping for user details of  each class.
    mapping(address => mapping(uint256 => User)) public userLevelDeposit;
    mapping(uint256 => Level) public levelInfo;

    // Events.
    event Deposit(address user, uint256 class, uint256 amount);
    event Withdraw(address user, uint256 class, uint256 amount);
    event Claim(address user, uint256 class, uint256 amount);
    event Compound(address user, uint256 class, uint256 amount);

    // Set the token to be staked.
    constructor(address _token) {
        acceptedToken = IERC20(_token);

        // Level 0 - 1%  daily / 30 Days
        levelInfo[0].APY = 36500;
        levelInfo[0].lockPeriod = 30 days;
        // Level 1 - 1.25% daily / 90 Days
        levelInfo[1].APY = 45625;
        levelInfo[1].lockPeriod = 90 days;
        // Level 2 - 1.5% daily / 180 Days
        levelInfo[2].APY = 54750;
        levelInfo[2].lockPeriod = 180 days;
        // Level 3 -  2% daily / 365 Days
        levelInfo[3].APY = 73000;
        levelInfo[3].lockPeriod = 365 days;
    }

    // Pause and Unpause the contract
    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function deposit(uint256 _amount, uint256 _level) public whenNotPaused {
        address _msgSender = msg.sender;

        acceptedToken.transferFrom(_msgSender, address(this), _amount);

        if (userLevelDeposit[_msgSender][_level].balance > 0) {
            _amount += calculateRewards(_msgSender, _level);
        }

        userLevelDeposit[_msgSender][_level].balance += _amount;
        userLevelDeposit[_msgSender][_level].started = block.timestamp;
        userLevelDeposit[_msgSender][_level].lastClaim = block.timestamp;
        userLevelDeposit[_msgSender][_level].unlockTime =
            block.timestamp +
            levelInfo[_level].lockPeriod;

        emit Deposit(_msgSender, _level, _amount);
    }

    function withdraw(uint256 _amount, uint256 _level) public {
        address _msgSender = msg.sender;
        require(
            userLevelDeposit[_msgSender][_level].balance >= _amount,
            "Not enough deposit"
        );

        uint256 rewards = calculateRewards(_msgSender, _level);
        uint256 withdrawAmount = _amount + rewards;

        uint256 withdrawFee;
        if (userLevelDeposit[_msgSender][_level].unlockTime > block.timestamp) {
            withdrawFee = (withdrawAmount * earlyWithdrawFee) / 100;
        }

        userLevelDeposit[_msgSender][_level].lastClaim = block.timestamp;
        userLevelDeposit[_msgSender][_level].balance -= _amount;

        withdrawAmount -= withdrawFee;

        require(withdrawAmount > 0, "No tokens available to withdraw");

        acceptedToken.transfer(_msgSender, withdrawAmount);

        emit Withdraw(_msgSender, 0, _amount);
    }

    function claim(uint256 _level) external {
        address _msgSender = msg.sender;
        require(
            userLevelDeposit[_msgSender][_level].balance > 0,
            "No active deposit"
        );

        uint256 rewards = calculateRewards(_msgSender, _level);

        userLevelDeposit[_msgSender][_level].lastClaim = block.timestamp;
        userLevelDeposit[_msgSender][_level].claimed += rewards;

        acceptedToken.transfer(_msgSender, rewards);

        emit Claim(_msgSender, _level, rewards);
    }

    function compound(uint256 _level) external {
        address _msgSender = msg.sender;
        require(
            userLevelDeposit[_msgSender][_level].balance > 0,
            "No active deposit"
        );

        uint256 rewards = calculateRewards(_msgSender, _level);

        userLevelDeposit[_msgSender][_level].balance += rewards;
        userLevelDeposit[_msgSender][_level].lastClaim = block.timestamp;

        emit Compound(_msgSender, _level, rewards);
    }

    function calculateRewards(address _user, uint256 _level)
        public
        view
        returns (uint256)
    {
        uint256 timeStaked = block.timestamp -
            userLevelDeposit[_user][_level].lastClaim;
        uint256 balance = userLevelDeposit[_user][_level].balance;
        uint256 APY = levelInfo[_level].APY;

        uint256 rewardsPerSecond = ((balance * APY) / 10000) / 365 days;
        uint256 rewardsEarned = timeStaked * rewardsPerSecond;

        return rewardsEarned;
    }

    function getUserInfo(address _user)
        external
        view
        returns (
            User memory level0,
            User memory level1,
            User memory level2,
            uint256 level0Rewards,
            uint256 level1Rewards,
            uint256 level2Rewards
        )
    {
        level0 = userLevelDeposit[_user][0];
        level1 = userLevelDeposit[_user][1];
        level2 = userLevelDeposit[_user][2];

        level0Rewards = calculateRewards(_user, 0);
        level1Rewards = calculateRewards(_user, 1);
        level2Rewards = calculateRewards(_user, 2);
    }

    function getLevelsInfo()
        external
        view
        returns (
            Level memory level0,
            Level memory level1,
            Level memory level2
        )
    {
        level0 = levelInfo[0];
        level1 = levelInfo[1];
        level2 = levelInfo[2];
    }

    function changeLevelValues(
        uint256 level,
        uint256 _APY,
        uint256 _lockTime
    ) external onlyOwner {
        levelInfo[level].APY = _APY;
        levelInfo[level].lockPeriod = _lockTime;
    }

    function changeEarlyWithdrawFee(uint256 _newFee) external onlyOwner {
        earlyWithdrawFee = _newFee;
    }

    function withdrawTokens() external onlyOwner {
        acceptedToken.transfer(
            msg.sender,
            acceptedToken.balanceOf(address(this))
        );
    }
}
