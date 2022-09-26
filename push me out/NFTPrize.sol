// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract NFTPrize is ERC721Enumerable, Ownable {

    uint256 public minCPLToMint = 5000000 ether;
    uint256 public mintFee = 1000; // on basis points, 1000 = 10%.
    uint256 public sellNowFee = 8500; // on basis points, 8500 = 85%.

    address public machineCreator;
    address public CPLToken;
    address public TPLToken;
    address public treasuryWallet;

    mapping(uint256 => NFT) public NFTdetails;
    mapping(uint256 => string) tokensURI;

    struct NFT {
        address creator;
        uint256 price;
    }

    event prizeMinted (address creator, uint256 tokenId, uint256 price, uint256 timestamp);
    event sellNowClaimed (address user, address creator, uint256 tokenId, uint256 price, uint256 payment, uint256 timestamp);
    event addressesChanged (address machineCreator, address CPLToken, address TPLToken, address treasuryWallet);
    event feesChanged (uint256 minCPLToMint, uint256 mintFee, uint256 sellNowFee);

    constructor() ERC721("NFT Prize", "NP") {}

    modifier hasEnoughBalance () {
        uint256 balance = IERC20(CPLToken).balanceOf(msg.sender);
        require (balance >= minCPLToMint, "NOT_ENOUGH_CPL_BALANCE");
        _;
    }

    function setAddresses (address _machineCreator, address _CPLToken, address _TPLToken, address _treasuryWallet) external onlyOwner{
        machineCreator = _machineCreator;
        CPLToken = _CPLToken;
        TPLToken = _TPLToken;
        treasuryWallet = _treasuryWallet;

        emit addressesChanged (_machineCreator, _CPLToken, _TPLToken, _treasuryWallet);
    }   

    function changeFees (uint256 _minCPLToMint, uint256 _mintFee, uint256 _sellNowFee) external onlyOwner{
        minCPLToMint = _minCPLToMint;
        mintFee = _mintFee;
        sellNowFee = _sellNowFee;

        emit feesChanged (_minCPLToMint, _mintFee, _sellNowFee);
    }

    function mint(uint256 _price, string memory _uri) public hasEnoughBalance returns (uint256 tokenId){
        uint256 payment = (_price * mintFee) / 10000;
        IERC20(TPLToken).transferFrom(msg.sender, treasuryWallet, payment);

        tokenId = totalSupply() + 1;

        NFTdetails[tokenId] = NFT({creator: msg.sender, price: _price});

        tokensURI[tokenId] = _uri;

        _mint(msg.sender, tokenId);

        emit prizeMinted (msg.sender, tokenId, _price, block.timestamp);
    }    

    function batchMint (uint256 [] memory _prices, string [] memory _uris) external onlyOwner {
        for(uint256 i; i < _prices.length; i++){    
            uint256 tokenId = totalSupply() + 1;        

            NFTdetails[tokenId] = NFT({creator: msg.sender, price: _prices[i]});

            tokensURI[tokenId] = _uris[i];

            _mint(msg.sender, tokenId);

            emit prizeMinted (msg.sender, tokenId, _prices[i], block.timestamp);
        }
    }

    function sellNow(uint256 _tokenId) external {
        require(ownerOf(_tokenId) == msg.sender, "NOT_TOKEN_OWNER");

        address creator = NFTdetails[_tokenId].creator;
        uint256 price = NFTdetails[_tokenId].price;

        _transfer(msg.sender, creator, _tokenId);

        uint256 payment = (price * sellNowFee) / 10000;
        IERC20(TPLToken).transferFrom(creator, msg.sender, payment);

        emit sellNowClaimed (msg.sender, creator, _tokenId, price, payment, block.timestamp);
    }

    function getPrice(uint256 _tokenId) public view returns (uint256) {
        return NFTdetails[_tokenId].price;
    }

    function tokenURI(uint256 tokenId) public view override(ERC721) returns (string memory){
        require(_exists(tokenId), "Cannot query non-existent token");

        return tokensURI[tokenId];
    }

    function walletOfOwner(address _owner) external view returns (uint256[] memory){
        uint256 tokenCount = balanceOf(_owner);

        uint256[] memory tokensId = new uint256[](tokenCount);
        for (uint256 i = 0; i < tokenCount; i++) {
            tokensId[i] = tokenOfOwnerByIndex(_owner, i);
        }

        return tokensId;
    }

    function transferFrom(address from, address to, uint256 tokenId) public virtual override {    
        if (_msgSender() != machineCreator){
            require(_isApprovedOrOwner(_msgSender(), tokenId), "ERC721: transfer caller is not owner nor approved");
        }
        
        _transfer(from, to, tokenId);
    }
     
    function safeTransferFrom( address from, address to, uint256 tokenId, bytes memory _data) public virtual override {
        if (_msgSender() != machineCreator){
            require(_isApprovedOrOwner(_msgSender(), tokenId), "ERC721: transfer caller is not owner nor approved");
        }
        _safeTransfer(from, to, tokenId, _data);
    }
}
