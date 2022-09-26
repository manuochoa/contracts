// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./airdrop.sol";

contract Deployer is Ownable {
    uint256 public airdropCount;
    uint256 public deployCost = 0.01 ether;

    mapping(uint256 => address) public airdropById;
    mapping(address => uint256) public airdropIdByAddress;
    mapping(address => bool) private isAirdrop;
    mapping(address => address[]) public airdropByToken;
    mapping(address => address[]) public userAirdropInvested;
    mapping(address => mapping(address => bool)) isAirdropAdded;

    event airdropDeployed(address newTokenAddress, address deployer);

    function createAirdrop(       
        address _token,   
        string memory _URIData
    ) public payable {
        require(msg.value >= deployCost, "Not enough BNB to deploy");

        SenseiAirdrop newAirdrop = new SenseiAirdrop(
            _token,
            _URIData,
            msg.sender
        );
        newAirdrop.transferOwnership(owner());

        payable(owner()).transfer(msg.value);

        airdropById[airdropCount] = address(newAirdrop);
        airdropIdByAddress[address(newAirdrop)] = airdropCount;
        airdropCount++;

        airdropByToken[_token].push(address(newAirdrop));
        isAirdrop[address(newAirdrop)] = true;

        emit airdropDeployed(address(newAirdrop), msg.sender);
    }

    function getDeployedAirdrops(uint256 startIndex, uint256 endIndex)
        public
        view
        returns (address[] memory)
    {
        if (endIndex >= airdropCount) {
            endIndex = airdropCount - 1;
        }

        uint256 arrayLength = endIndex - startIndex + 1;
        address[] memory airdropAddress = new address[](arrayLength);
   
        for (uint256 i = startIndex; i <= endIndex; i++) {
            airdropAddress[i] = airdropById[startIndex + i];
        }

        return airdropAddress;
    }

    function setPrice(uint256 _price) external onlyOwner {
        deployCost = _price;
    }

   function getInfo(uint256 id)
        external
        view
        returns (
            uint256[] memory, uint8, string memory, string memory, string memory, address, address, address
        )
    {
        address contractAddress = airdropById[id];

        SenseiAirdrop instance = SenseiAirdrop(contractAddress);

        return instance.getInfo();
    }

    function addToUserAirdrop(address _user, address _airdrop) external {
        require(isAirdrop[msg.sender], "Only airdrops can add");

        if(!isAirdropAdded[_user][_airdrop]){
            userAirdropInvested[_user].push(_airdrop);
            isAirdropAdded[_user][_airdrop] = true;
        }
    }

    function getUserContributions (address _user) external view returns (uint256 [] memory ids, uint256 [] memory contributions, uint256 [] memory claimed){
        uint256 count = userAirdropInvested[_user].length;
        ids = new uint256 [](count);
        contributions = new uint256 [](count);
        claimed = new uint256 [](count);

        for(uint i; i < count ; i++){
            address airdropaddress = userAirdropInvested[_user][i];
            ids[i] = airdropIdByAddress[airdropaddress];
            contributions[i] = SenseiAirdrop(airdropaddress).userAllocation(_user);
            claimed[i] = SenseiAirdrop(airdropaddress).userClaimed(_user);
        }
    }
}
