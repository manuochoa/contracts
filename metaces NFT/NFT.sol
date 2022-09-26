// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol";

contract metacesNFT is ERC721Enumerable, Ownable {
    using Strings for uint256;

    uint256 public price = 0.1 ether;
    uint256 public walletLimit = 20;
    uint256 public saleStart;
    uint256 public MAX_SUPPLY = 888;

    string public baseURI;

    constructor(
        string memory _URI,
        uint256 saleTime,
        address _owner
    ) ERC721("metacesNFT", "ACES") {
        baseURI = _URI;
        saleStart = saleTime;
        _transferOwnership(_owner);
    }

    function mint(uint256 _amount) external payable {
        uint256 balance = balanceOf(msg.sender);
        require(balance <= walletLimit, "exceeds minting limit per wallet");
        require(totalSupply() + _amount <= MAX_SUPPLY, "exceeds max supply");
        require(_amount <= 10, "exceeds max buy amount");
        require(_amount * price <= msg.value, "not enough ETH to buy");

        uint256 _tokenId = totalSupply();

        for (uint256 i = 1; i <= _amount; i++) {
            _mint(msg.sender, _tokenId + i);
        }
    }

    function withdraw() public onlyOwner {
        payable(msg.sender).transfer(address(this).balance);
    }

    function setURI(string memory _newURI) public onlyOwner {
        baseURI = _newURI;
    }

    function changeValues(uint256 _price, uint256 _walletLimit)
        public
        onlyOwner
    {
        price = _price;
        walletLimit = _walletLimit;
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721)
        returns (string memory)
    {
        require(_exists(tokenId), "Cannot query non-existent token");

        return string(abi.encodePacked(baseURI, tokenId.toString(), ".json"));
    }

    function walletOfOwner(address _owner)
        external
        view
        returns (uint256[] memory)
    {
        uint256 tokenCount = balanceOf(_owner);

        uint256[] memory tokensId = new uint256[](tokenCount);
        for (uint256 i = 0; i < tokenCount; i++) {
            tokensId[i] = tokenOfOwnerByIndex(_owner, i);
        }

        return tokensId;
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return baseURI;
    }

    function changeStartTime(uint256 _SaleTime) public onlyOwner {
        saleStart = _SaleTime;
    }
}
