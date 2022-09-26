// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/ERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/security/Pausable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol";

interface IDeployer {
    function addToUserLaunchpad(address _user, address _launchpad) external;
    function removeLaunchpad(address _launchpad) external;
    function updateStats(uint256 _invested, uint256 _contributors) external;
}

contract launchPad is Ownable, Pausable {
    uint256 public softCap;
    uint256 public hardCap;
    uint256 public startTime;
    uint256 public endTime;
    uint256 public totalDeposits;
    uint256 public contributors;
    uint256 public ownerFee;
    uint8 public status; // 0- open, 1- finish, 2- refund

    string public URIData;

    address public tokenToReceive;
    address public contractAdmin;

    bool public kyc;

    mapping (address => uint256) public depositedAmount;
    mapping (uint256 => address) public contributorsList;

    IDeployer deployer;

    event userDeposit(uint256 amount, address user);
    event userRefunded(uint256 amount, address user);
    event saleClosed(uint256 timeStamp, uint256 collectedAmount);
    event saleCanceled(uint256 timeStamp, address operator);

    constructor (uint256 [] memory _caps, uint256 [] memory _times, string memory _URIData, uint256 _fee, address _tokenToReceive, address _contractAdmin) {
        softCap = (_caps[0] * 10**18) / 10000;
        hardCap = (_caps[1] * 10**18) / 10000;        
        startTime = _times[0];
        endTime = _times[1];       
        URIData = _URIData;        
        ownerFee = _fee;        
        tokenToReceive = _tokenToReceive;  
        contractAdmin = _contractAdmin;  
       
        deployer = IDeployer(msg.sender);  
    }

    modifier restricted(){
        require(msg.sender == owner() || msg.sender == contractAdmin, "Caller not allowed");
        _;
    }

    function invest (uint256 _amount) external payable {
        require(status == 1, "Sale is not open");
        require(startTime < block.timestamp, "Sale is not open yet");
        require(endTime > block.timestamp, "Sale is already closed");
        require(_amount + totalDeposits <= hardCap, "Hardcap reached");

        if(tokenToReceive == address(0)){
            require(_amount == msg.value, "Invalid payment amount");
        } else {
            IERC20(tokenToReceive).transferFrom(msg.sender, address(this), _amount);
        }

        if(depositedAmount[msg.sender] == 0){
            contributorsList[contributors] = msg.sender;
            contributors++;
        }

        depositedAmount[msg.sender] = depositedAmount[msg.sender] + _amount;
        totalDeposits += _amount;

        deployer.addToUserLaunchpad(msg.sender, address(this));

        emit userDeposit(_amount, msg.sender);
    }

    function claimRefund () external {
        require(status == 3, "Refund is not available");
        uint256 deposit = depositedAmount[msg.sender];
        require(deposit > 0, "User doesn't have deposits");

        depositedAmount[msg.sender] = 0;

        if(tokenToReceive == address(0)){
            payable(msg.sender).transfer(deposit);
        } else {
            IERC20(tokenToReceive).transfer(msg.sender, deposit);
        }        

        emit userRefunded(deposit, msg.sender);
    }

    function finishSale () external restricted {
        require(block.timestamp > endTime || totalDeposits == hardCap, "Sales has not ended yet");
        require(status == 0, "Sale is already finished");
        require(totalDeposits >= softCap, "Soft cap not reached");

        status = 1;

        deployer.updateStats(totalDeposits, contributors);

        withdraw();

        emit saleClosed(block.timestamp, totalDeposits);    
    } 

    function cancelSale () external restricted {
        require(status == 0, "Sale is already finished");

        status = 2;

        deployer.removeLaunchpad(address(this)); 

        emit saleCanceled(block.timestamp, msg.sender);
    }

    function withdraw () internal {
        uint256 balance;
        uint256 fee;

        if(ownerFee > 0){
            fee = (totalDeposits * ownerFee) / 10000;
        }

        if(tokenToReceive == address(0)){
            balance = address(this).balance;
            payable(owner()).transfer(fee);
            payable(msg.sender).transfer(balance - fee);
        } else {
            balance = IERC20(tokenToReceive).balanceOf(address(this));
            IERC20(tokenToReceive).transfer(owner(), balance - fee);
            IERC20(tokenToReceive).transfer(msg.sender, balance);
        }   
    }

    function getContractNumbers() public view returns (uint256 [] memory data){
        data = new uint256[](6);
        data[0] = softCap;
        data[1] = hardCap;
        data[2] = startTime;
        data[3] = endTime;
        data[4] = totalDeposits;
        data[5] = contributors;
    }

    function getContractInfo() external view returns (uint8 _status, uint256 [] memory numbers, string memory _URIData, address _contractAdmin, address _tokenAddress, bool _kyc){
        _status = status; 
        numbers = getContractNumbers();
        _URIData = URIData;
        _contractAdmin = contractAdmin;
        _tokenAddress = tokenToReceive;
        _kyc = kyc;
    }

    function getContributorsList() external view returns (address [] memory list, uint256 [] memory amounts){
        list = new address [](contributors);
        amounts = new uint256 [](contributors);
        
        for (uint256 i; i < contributors; i++) {
            address userAddress = contributorsList[i];
            list[i] = userAddress;
            amounts[i] = depositedAmount[userAddress];
        }
    }

    function changeData(string memory _newData) external onlyOwner {
        URIData = _newData;
    }
}