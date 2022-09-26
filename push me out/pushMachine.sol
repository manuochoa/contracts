// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "./CPLToken.sol";
import "./INFTPrize.sol";

contract MachineCreator is Ownable, IERC721Receiver, ERC1155Holder {
    using ECDSA for bytes32;

    IERC1155 public ticketsContract;

    uint256 public MachineCount;
    uint256 public NFTsCount;
    uint256 public CPLPerTicket = 1 ether;
    uint256 public minCPLToCreate = 10000 ether;

    uint256[] public activeMachines;    
    uint256[] priceLevels = [5 ether, 50 ether, 500 ether, 5000 ether, 50000 ether];
    uint256[] licensePrices = [10, 100, 1000, 10000, 100000];

    address public CPLTokenAddress;
    address[] public acceptedNFTs;

    address private _signerAddress = 0x10B22E69768d825638981c0050626F5b9C4EADc2;

    struct pushMachine {
        string name;
        address owner;
        address currentPlayer;
        uint256 price;
        uint256 size;
        uint256 itemsAvailable;
        uint256 expirationDate;
        uint256 lockedTime;
    }

    struct NFT {
        address tokenAddress;
        address owner;
        uint256 tokenId;
        uint256 machineId;
        uint256 indexInMachine;
    }

    mapping(uint256 => uint256[]) public NFTsByMachineId;

    mapping(uint256 => uint256) public activeMachineIndex;
    mapping(uint256 => uint256) public userMachinesIndex;

    mapping(uint256 => pushMachine) public machineById;
    mapping(uint256 => NFT) public NFTById;
    
    mapping(address => bool) public isAcceptedNFT;
    mapping(address => uint256[]) public userMachines;

    constructor() {}

    modifier hasEnoughBalance () {
        uint256 balance = IERC20(CPLTokenAddress).balanceOf(msg.sender);
        require (balance >= minCPLToCreate, "NOT_ENOUGH_CPL_BALANCE");
        _;
    }

    function addAcceptedNFT(address _newNFT) external onlyOwner {       
        isAcceptedNFT[_newNFT] = true;
        acceptedNFTs.push(_newNFT);
    }

    function setAddresses (address _ticket, address _CPLTokenAddress) external onlyOwner {
        ticketsContract = IERC1155(_ticket);
        CPLTokenAddress = _CPLTokenAddress;
    }

    function setValues (uint256 _CPLPerTicket, uint256 _minCPLToCreate) external onlyOwner {
        CPLPerTicket = _CPLPerTicket;
        minCPLToCreate = _minCPLToCreate;
    }

    function createMachine(
        string memory _name,
        uint256 _price, // tickets neededed to play
        uint256 _size, // from 0-4 (S - M - L - XL - XXL)
        uint256 _days, // days active
        uint256[] memory _ids,
        address[] memory _addresses
    ) external hasEnoughBalance returns (uint256 machineId) {
        machineId = MachineCount;
        uint256 machinePrice = licensePrices[_size] * _days;

        ticketsContract.safeTransferFrom(msg.sender, address(this), 1, machinePrice, "0x00");

        machineById[machineId] = pushMachine({
            name: _name,
            owner: msg.sender,
            currentPlayer: address(0),
            price: _price,
            size: _size,
            itemsAvailable: 0,
            expirationDate: block.timestamp + _days * 1 days,
            lockedTime: 0
        });

        for (uint256 i = 0; i < _ids.length; i++) {
            addNFTtoMachine(_ids[i], _addresses[i], machineId);
        }

        // Save machine to user address
        userMachinesIndex[machineId] = userMachines[msg.sender].length;
        userMachines[msg.sender].push(machineId);

        // Save to active machines list
        MachineCount++;        
    }

    function batchAddToMachine ( uint256 _machineId, uint256[] memory _ids, address[] memory _addresses) external {
        require(machineById[_machineId].owner == msg.sender, "NOT_MACHINE_OWNER");
        for (uint256 i = 0; i < _ids.length; i++) {
            addNFTtoMachine(_ids[i], _addresses[i], _machineId);
        }
    }

    function addNFTtoMachine(uint256 _id, address _address, uint256 _machineId) internal returns (uint256 NFTid) {
        require(isAcceptedNFT[_address], "NFT_NOT_ACCEPTED");
        require(block.timestamp < machineById[_machineId].expirationDate, "MACHINE_EXPIRED");
        uint256 machineSize = machineById[_machineId].size;
        uint256 tokenPrice = INFTPrize(_address).getPrice(_id);
        require(priceLevels[machineSize] >= tokenPrice, "GIFT_PRICE_TOO_HIGH");

        NFTid = NFTsCount + 1;

        NFTById[NFTid] = NFT({
            tokenAddress: _address,
            tokenId: _id,
            owner: msg.sender,
            machineId: _machineId,
            indexInMachine: NFTsByMachineId[_machineId].length
        });

        IERC721(_address).safeTransferFrom(msg.sender, address(this), _id, "");        

        // If machine was empty push again on the active list.
        if(machineById[_machineId].itemsAvailable == 0){
            activeMachineIndex[_machineId] = activeMachines.length;
            activeMachines.push(_machineId);
        }

        machineById[_machineId].itemsAvailable++;
        NFTsByMachineId[_machineId].push(NFTid);
        NFTsCount++;     
    }

    function play(uint256 _machineId) external {
        require(machineById[_machineId].itemsAvailable > 0, "MACHINE_EMPTY");
        require(block.timestamp < machineById[_machineId].expirationDate, "MACHINE_EXPIRED");
        require(block.timestamp > machineById[_machineId].lockedTime, "MACHINE_IN_USE");

        uint256 machinePrice = machineById[_machineId].price;

        machineById[_machineId].currentPlayer = msg.sender;
        machineById[_machineId].lockedTime = block.timestamp + 5 minutes;

        ticketsContract.safeTransferFrom( msg.sender, machineById[_machineId].owner, 0, machinePrice, "0x00");

        CPLToken(CPLTokenAddress).mint(msg.sender, CPLPerTicket * machinePrice);
    }

    function claimReward(uint256[] memory _NFTIds, uint256 _machineId, bytes32 hash, bytes memory signature) external{
        require(machineById[_machineId].currentPlayer == msg.sender, "ONLY_CURRENT_PLAYER_ALLOWED");
        require (hashTransaction(_NFTIds, _machineId, msg.sender) == hash, "TRANSACTION_HASH_FAILED");
        require (matchAddresSigner(hash, signature), "WRONG_SIGNATURE");

        machineById[_machineId].currentPlayer = address(0);
        machineById[_machineId].lockedTime = block.timestamp;        

        for (uint256 i = 0; i < _NFTIds.length; i++) {
            transferNFT(_NFTIds[i], _machineId);
        }       
    }

    function destroyMachine(uint256 _machineId, uint256[] memory _NFTIds) external {
        require(machineById[_machineId].owner == msg.sender, "NOT_MACHINE_OWNER");
        require(block.timestamp > machineById[_machineId].expirationDate, "MACHINE_NOT_EXPIRED");

        uint256 itemsAvailable = machineById[_machineId].itemsAvailable;
        if (itemsAvailable > 0) {
            require(_NFTIds.length == itemsAvailable, "EMPTY_MACHINE_FIRST");

            for (uint256 i = 0; i < _NFTIds.length; i++) {
                transferNFT(_NFTIds[i], _machineId);
            }
        }         

        removeFromUserMachines(_machineId);
        delete machineById[_machineId];
    }

    function withdrawFromMachine(uint256[] memory _NFTIds, uint256 _machineId) external {
        require(machineById[_machineId].owner == msg.sender, "NOT_MACHINE_OWNER");
        require(block.timestamp > machineById[_machineId].expirationDate, "MACHIEN_STILL_ACTIVE");        

        for (uint256 i = 0; i < _NFTIds.length; i++) {
            transferNFT(_NFTIds[i], _machineId);
        }
    }

    function transferNFT(uint256 NFTid, uint256 _machineId) internal {
        NFT memory nft = NFTById[NFTid];
        require(nft.machineId == _machineId, "INVALID_TOKEN_ID");

        IERC721(nft.tokenAddress).safeTransferFrom(address(this), msg.sender, nft.tokenId, "");

        machineById[_machineId].itemsAvailable--;

        if (machineById[_machineId].itemsAvailable == 0) {
            removeFromActiveMachine(_machineId);
        }

        delete NFTById[NFTid];
        delete NFTsByMachineId[_machineId][nft.indexInMachine];
    }

    function removeFromActiveMachine(uint256 _machineId) internal {
        uint256 lastMachine = activeMachines[activeMachines.length - 1];

        activeMachines[activeMachineIndex[_machineId]] = lastMachine;
        activeMachineIndex[lastMachine] = activeMachineIndex[_machineId];

        activeMachines.pop();      
    }

    function removeFromUserMachines(uint256 _machineId) internal {
        uint256 lastMachine = userMachines[msg.sender][userMachines[msg.sender].length - 1];

        userMachines[msg.sender][userMachinesIndex[_machineId]] = lastMachine;
        userMachinesIndex[lastMachine] = userMachinesIndex[_machineId];

        userMachines[msg.sender].pop();
    }   

    function activeMachinesCounter() public view returns (uint256) {
        return activeMachines.length;
    }

    function getActiveMachines() external view returns (uint256[] memory) {
        uint256 machineCount = activeMachinesCounter();

        uint256[] memory machinesId = new uint256[](machineCount);
        for (uint256 i = 0; i < machineCount; i++) {
            machinesId[i] = activeMachines[i];
        }

        return machinesId;
    }

    function getUserMachines(address user) external view returns (uint256[] memory) {
        uint256 machineCount = userMachines[user].length;

        uint256[] memory machinesId = new uint256[](machineCount);
        for (uint256 i = 0; i < machineCount; i++) {
            machinesId[i] = userMachines[user][i];
        }

        return machinesId;
    }

    function machineNFTs(uint256 _machineId) external view returns (uint256[] memory) {
        uint256 size = NFTsByMachineId[_machineId].length;
        uint256[] memory result = new uint256[](size);

        for (uint256 i; i < size; i++) {
            uint256 id = NFTsByMachineId[_machineId][i];
            if (NFTById[id].owner != address(0)) {
                result[i] = id;
            }
        }

        return result;
    }

    function machineNFTsData(uint256 _machineId) external view returns (NFT[] memory) {
        uint256 size = NFTsByMachineId[_machineId].length;
        NFT[] memory result = new NFT[](size);

        for (uint256 i; i < size; i++) {
            result[i] = NFTById[NFTsByMachineId[_machineId][i]];
        }

        return result;
    }

    function onERC721Received(address, address, uint256, bytes memory) public virtual override returns (bytes4) {
        return this.onERC721Received.selector;
    }  

    function hashTransaction(uint256[] memory _NFTIds, uint256 _machineId, address _user) internal pure returns (bytes32) {
        bytes32 s = keccak256(abi.encodePacked(_NFTIds, _machineId, _user));

        return ECDSA.toEthSignedMessageHash(s);
    }

    function matchAddresSigner(bytes32 hash, bytes memory signature) internal view returns (bool) {
        return _signerAddress == hash.recover(signature);
    }
}
