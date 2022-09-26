// SPDX-License-Identifier: GPL-3.0
// solhint-disable-next-line
pragma solidity 0.8.12;
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./ICryptoCarpinchos.sol";
import "./ICToken.sol";

contract MasterContractV1 is ReentrancyGuard, Ownable {
    address public CCAddress;
    address public CTokenAddress;

    address public secret;

    uint256 public timeCounter = 1 days; 
    uint256 public matchsCreated;

    mapping(uint256 => uint256) public lastClaim;
    mapping(uint256 => uint256) public matchsIndex;
    mapping(uint256 => matchStruct) public matchByToken;
    mapping(uint256 => tokenStats) public tokenData;

    struct matchStruct {
        uint256 id;
        uint256 tokenId;
        uint256 price;
        uint256 createdAt;
        address creator;
    }

    struct tokenStats {
        uint256 wins;
        uint256 loses;
    }

    ICryptoCarpinchos CCInterface;
    ICToken CTokenInterface;

    event MATCH_CREATED(uint256 tokenId, uint256 price, uint256 timestamp);
    event MATCH_ACCEPTED(
        uint256 tokenId,
        uint256 oponent,
        uint256 price,
        uint256 result,
        uint256 timestamp
    );
    event MATCH_CANCELLED(uint256 tokenId, uint256 timestamp);

    constructor(address _CCAddress, address _CTokenAddress) {
        CCAddress = _CCAddress;
        CCInterface = ICryptoCarpinchos(_CCAddress);

        CTokenAddress = _CTokenAddress;
        CTokenInterface = ICToken(_CTokenAddress);
    }

    modifier noZeroAddress(address _address) {
        require(_address != address(0), "No Zero Address");
        _;
    }

    modifier onlyAllowed() {
        require(
            owner() == msg.sender || secret == msg.sender,
            "Ownable: caller is not Allowed"
        );
        _;
    }

    function createMatch(uint256 tokenId, uint256 price) external {
        require(
            CCInterface.ownerOf(tokenId) == msg.sender,
            "Not the token owner"
        );
        require(
            CCInterface.usdtAvailable(tokenId) >= price,
            "Not enough usdt available"
        );

        if (matchByToken[tokenId].price == 0) {
            CTokenInterface.pay(20);
            matchsCreated++;
        }

        matchsIndex[matchsCreated - 1] = tokenId;

        matchByToken[tokenId] = matchStruct({
            id: matchsCreated - 1,
            tokenId: tokenId,
            price: price,
            createdAt: block.timestamp,
            creator: msg.sender
        });    

        CCInterface.lockUsdt(tokenId, price);       

        emit MATCH_CREATED(tokenId, price, block.timestamp);
    }

    function cancelMatch(uint256 tokenId) external {
        require(
            CCInterface.ownerOf(tokenId) == msg.sender,
            "Not the token owner"
        );

        removeMatch(tokenId);

        CCInterface.lockUsdt(tokenId, 0);

        emit MATCH_CANCELLED(tokenId, block.timestamp);
    }

    function fight(
        uint256 tokenId,
        uint256 oponent,
        uint256 num
    ) external onlyAllowed {
        matchStruct memory currentMatch = matchByToken[tokenId];
        uint256 price = currentMatch.price;
        uint256 oponentUsdt = CCInterface.usdtNotLocked(oponent);

        require(oponentUsdt > price, "Not enough USDT available for fighting");
        require(price > 0, "There's no match for this token");

        uint256 result = random(num) % 2;

        if (result == 0) {
            CCInterface.finishFight(tokenId, price - 1 * 10**6, true);
            CCInterface.finishFight(oponent, price, false);
            tokenData[tokenId].wins++;
            tokenData[oponent].loses++;
        } else {
            CCInterface.finishFight(tokenId, price, false);
            CCInterface.finishFight(oponent, price - 1 * 10**6, true);
            tokenData[tokenId].loses++;
            tokenData[oponent].wins++;
        }

        CCInterface.payFee();
        removeMatch(tokenId);

        emit MATCH_ACCEPTED(tokenId, oponent, price, result, block.timestamp);
    }

    function claimCtoken(uint256[] memory tokenIds) external {
        uint256 CTokenAmount;

        for (uint256 i; i < tokenIds.length; i++) {
            require(
                CCInterface.ownerOf(tokenIds[i]) == msg.sender,
                "Not your token"
            );

            CTokenAmount += getCTokens(tokenIds[i]);
            lastClaim[tokenIds[i]] = block.timestamp;
        }

        CTokenInterface.claim(msg.sender, CTokenAmount);
    }

    function removeMatch(uint256 tokenId) internal {
        uint256 lastTokenId = matchsIndex[matchsCreated - 1];

        if (lastTokenId != tokenId) {
            uint256 currentIndex = matchByToken[tokenId].id;
            matchsIndex[currentIndex] = lastTokenId;
            matchByToken[lastTokenId].id = currentIndex;
        }

        matchsCreated--;
        delete matchByToken[tokenId];
    }

    function getCTokens(uint256 tokenId) public view returns (uint256) {
        uint256 last = lastClaim[tokenId] != 0
            ? lastClaim[tokenId]
            : CCInterface.mintingDatetime(tokenId);

        uint256 timeFromCreation = (block.timestamp - last) / (timeCounter);

        return 100 * timeFromCreation;
    }

    function getActiveMatchs()
        public
        view
        returns (matchStruct[] memory matchs, tokenStats[] memory results)
    {
        matchs = new matchStruct[](matchsCreated);
        results = new tokenStats[](matchsCreated);

        for (uint256 i; i < matchsCreated; i++) {
            uint256 tokenId = matchsIndex[i];
            matchs[i] = matchByToken[tokenId];
            results[i] = tokenData[tokenId];
        }
    }

    function random(uint256 seed) internal view returns (uint256) {
        return
            uint256(
                keccak256(
                    abi.encodePacked(
                        seed,
                        block.timestamp,
                        gasleft(),
                        msg.sender,
                        matchsCreated
                    )
                )
            );
    }

    function setCTokenAddress(address _newAddress)
        external
        onlyOwner
        noZeroAddress(_newAddress)
    {
        CTokenAddress = _newAddress;
        CTokenInterface = ICToken(_newAddress);
    }

    function setCCAddress(address _newAddress)
        external
        onlyOwner
        noZeroAddress(_newAddress)
    {
        CCAddress = _newAddress;
        CCInterface = ICryptoCarpinchos(_newAddress);
    }

    function setSecret(address _secret)
        external
        onlyOwner
        noZeroAddress(_secret)
    {
        secret = _secret;
    }
}
