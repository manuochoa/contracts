// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";


contract Marketplace is Ownable, ReentrancyGuard, ERC721Holder {
    IERC721 public flokiNFT;  
   
    uint256 public orders;    
    uint256 public itemsSold;
    uint256 public totalVolumen;
    uint256 public collectedFees;    
    uint256 public marketFee = 500; // 5% market fee.

    address public feeCollector;

    struct Order {        
        address seller;
        uint256 tokenId;
        uint256 createdAt;
        uint256 price;        
    }  

    struct Bid {
        address bidder;
        uint256 price;
        uint256 timestamp;
    }    
    
    mapping(uint256 => Order) public orderByTokenId;    
    mapping(address => uint256[]) public ordersBySeller;
    mapping(uint256 => uint256) public ordersIndex;     
    mapping(uint256 => Bid) public bidByTokenId;     

    event OrderCreated(address indexed seller,uint256 tokenId,uint256 createdAt,uint256 priceInWei);
    event OrderUpdated(uint256 tokenId,uint256 priceInWei);    
    event OrderSuccessful(uint256 tokenId,address indexed buyer,uint256 priceInWei);
    event OrderCancelled(uint256 tokenId,address user);
    event bidReceived(uint256 tokenId,uint256 amount,address bidder,uint256 timestamp);
    event bidAccepted(uint256 tokenId,address indexed buyer,uint256 priceInWei);
    event bidCancelled(uint256 tokenId,address user);

    constructor(address _flokiNFT)  {      
        flokiNFT = IERC721(_flokiNFT);       
    }

    function createOrder(uint256 _tokenId, uint256 _priceInWei) external {
        require(_priceInWei > 0, "Marketplace: Price should be bigger than 0");     

        orderByTokenId[_tokenId] = Order({           
            seller: msg.sender,           
            tokenId: _tokenId,
            createdAt: block.timestamp,
            price: _priceInWei          
        });     

        ordersIndex[_tokenId] = ordersBySeller[msg.sender].length;
        ordersBySeller[msg.sender].push(_tokenId);  

        flokiNFT.safeTransferFrom(msg.sender, address(this), _tokenId);      

        orders++;

        emit OrderCreated(msg.sender, _tokenId, block.timestamp, _priceInWei);
    }

    function cancelOrder(uint256 _tokenId) external {
        (address seller,,) = getOrderDetails(_tokenId);

        require(seller == msg.sender || msg.sender == owner(), "Marketplace: unauthorized sender");

        removeOrder(seller, _tokenId);
       
        flokiNFT.safeTransferFrom(address(this), seller, _tokenId);

        emit OrderCancelled(_tokenId, seller);
    }

    function updateOrder(uint256 _tokenId, uint256 _priceInWei) external {            
        require(orderByTokenId[_tokenId].seller == msg.sender, "Marketplace: sender not allowed");
        require(_priceInWei > 0, "Marketplace: Price should be bigger than 0");

        orderByTokenId[_tokenId].price = _priceInWei;        

        emit OrderUpdated(_tokenId, _priceInWei);
    }

    function executeOrder(uint256 _tokenId) external payable nonReentrant{
        (address seller,uint256 price,) = getOrderDetails(_tokenId);        
        
        require(msg.value == price, "Marketplace: Invalid paid value");       

        if (bidByTokenId[_tokenId].price > 0){
            _refundBid(bidByTokenId[_tokenId].bidder, bidByTokenId[_tokenId].price, _tokenId);
        }

        _executeOrder(_tokenId, msg.sender, seller, price);       
                              
        emit OrderSuccessful(_tokenId, msg.sender, price);
    }

    function placeBid(uint256 _tokenId) external payable nonReentrant{
        (address bidder,uint256 price,) = getBidDetails(_tokenId);
        
        require(price < msg.value, "Marketplace: Bid needs to be bigger than current bid");

        if(price > 0){
            _refundBid(bidder, price, _tokenId);            
        }

        bidByTokenId[_tokenId] = Bid({
            bidder: msg.sender,
            price: msg.value,
            timestamp: block.timestamp
        });

        emit bidReceived(_tokenId, msg.value, msg.sender, block.timestamp);
    }

    function cancelBid(uint256 _tokenId) external nonReentrant{
        (address bidder,uint256 price,) = getBidDetails(_tokenId);

        require(bidder == msg.sender, "Marketplace: Only bidder can cancel the bid");

        _refundBid(bidder, price, _tokenId);          
    }

    function acceptBid(uint256 _tokenId) external nonReentrant{
        (address bidder,uint256 price,) = getBidDetails(_tokenId);

        require(price > 0, "Marketplace: No bids for this item");
        require(msg.sender == orderByTokenId[_tokenId].seller, "Marketplace: Only seller can accept bid");        

        _executeOrder(_tokenId, bidder, msg.sender, price);    
        
        delete bidByTokenId[_tokenId];

        emit bidAccepted(_tokenId, msg.sender, price);
    }

    function _executeOrder(uint256 tokenId, address buyer, address seller, uint256 price) internal {
        uint256 fee = 0;

        if (marketFee > 0) {
            fee = (price * marketFee) / 10000;   
            collectedFees += fee;         
        }

        flokiNFT.safeTransferFrom(address(this), buyer, tokenId);

        payable(seller).transfer(price - fee);   

        payable(feeCollector).transfer(fee); 
        
        removeOrder(seller, tokenId);

        itemsSold++;
        totalVolumen += price;
    }

    function _refundBid(address bidder, uint256 price, uint256 _tokenId) internal {
        delete bidByTokenId[_tokenId]; 

        payable(bidder).transfer(price);

        emit bidCancelled(_tokenId, bidder);
    }

    function removeOrder(address seller, uint256 _tokenId) internal {
        uint256 lastTokenId = ordersBySeller[seller][ordersBySeller[seller].length - 1];

        ordersBySeller[seller][ordersIndex[_tokenId]] = lastTokenId;

        ordersIndex[lastTokenId] = ordersIndex[_tokenId];

        ordersBySeller[seller].pop();

        delete orderByTokenId[_tokenId];        
    }

    function getOrderDetails(uint256 tokenId) public view returns (address seller,uint256 price,uint256 createdAt){
        seller = orderByTokenId[tokenId].seller;        
        price = orderByTokenId[tokenId].price;
        createdAt = orderByTokenId[tokenId].createdAt;
    }

    function getBidDetails(uint256 tokenId) public view returns (address bidder,uint256 price,uint256 timestamp){
        bidder = bidByTokenId[tokenId].bidder;        
        price = bidByTokenId[tokenId].price;
        timestamp = bidByTokenId[tokenId].timestamp;
    }    

    function getTokensIds(address _sellerAddress)
        external
        view
        returns (uint256[] memory)
    {
        uint256 ordersCount = ordersBySeller[_sellerAddress].length;

        uint256[] memory tokensIds = new uint256[](ordersCount);
        for (uint256 i = 0; i < ordersCount; i++) {
            tokensIds[i] = ordersBySeller[_sellerAddress][i];
        }

        return tokensIds;
    }    

    function setMarketFee(uint256 _marketFee) external onlyOwner {
        marketFee = _marketFee;
    }   

    function setFeeCollector(address _feeCollector) external onlyOwner {
        feeCollector = _feeCollector;
    }

    function withdrawFees() external nonReentrant{
        require(collectedFees != 0, "No fees to colect");
        require(msg.sender == feeCollector, "Not allowed to collect fees");

        payable(feeCollector).transfer(collectedFees);

        collectedFees = 0;
    }
}
