// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract NFTPrize is ERC721Enumerable, Ownable {
    using ECDSA for bytes32;

    address public treasuryWallet;
    address public TPLToken;

    address private _signerAddress = 0x0D6334a53387c271DB5f29Cec00CdB2220ca7816;

    mapping(uint256 => NFT) public NFTdetails;
    mapping(string => uint256) public videoIdtoTokenId;
    mapping(string => Sponsorship) public sponsorshipByVideoId;
    mapping(uint256 => string) tokensURI;
    mapping(uint256 => mapping(uint256 => Comments)) public commentsByToken;
    mapping(uint256 => uint256) public commentsIndexByToken;
    mapping(uint256 => CommentStatus) public statusById;

    struct Comments {
        address user;
        uint256 timestamp;
        uint256 index;
        string comment;
        bool deleted;
    }

    struct NFT {
        address minter;        
        address postCreator;
        string videoId;
        bool transferable;
        bool commentsActive;
        uint256 price;
    }

    struct Sponsorship {
        uint256 price;
        uint256 timestamp;
        bool claimed;
    }

    struct CommentStatus {
        address closedBy;
        uint256 timestamp;
    }

    event Mint(
        string videoId,
        address minter,
        uint256 indexed timestamp,
        uint256 indexed amount
    );
    event SponsorshipMint(
        string videoId,
        address sponsor,
        uint256 indexed timestamp,
        uint256 indexed amount
    );
    event ClaimSponsorship(
        string videoId,
        address owner,
        uint256 indexed timestamp,
        uint256 indexed amount
    );
    event SetTransferable(string videoId, bool status);
    event Acquire(
        string videoId,
        address seller,
        address indexed buyer,
        uint256 indexed amount
    );
    event CommentStatusChanged(address operator, bool status, uint256 timestamp);
    event CommentAdded(address indexed operator, uint256 tokenId, uint256 indexed commentIndex);
    event CommentDeleted(address indexed operator, uint256 tokenId, uint256 indexed commentIndex);

    constructor(address _treasury, address _token)
        ERC721("Social NFT", "SNFT")
    {
        treasuryWallet = _treasury;
        TPLToken = _token;
    }

    function mint(
        uint256 _price,
        string memory _videoId,
        string memory _uri,
        bytes32 hash,
        bytes memory signature
    ) public returns (uint256 tokenId) {
        require(
            hashTransaction(
                keccak256(abi.encodePacked(_price, _videoId, msg.sender))
            ) == hash,
            "TRANSACTION_HASH_FAILED"
        );
        require(matchAddresSigner(hash, signature), "WRONG_SIGNATURE");
        require(videoIdtoTokenId[_videoId] == 0, "Video Id already minted");

        uint256 mintingPrice = (_price * 20) / 100;

        IERC20(TPLToken).transferFrom(msg.sender, treasuryWallet, mintingPrice); 

        tokenId = totalSupply() + 1;

        NFTdetails[tokenId] = NFT({
            minter: msg.sender,            
            postCreator: msg.sender,
            videoId: _videoId,
            transferable: false,
            commentsActive: true,
            price: 0
        });

        videoIdtoTokenId[_videoId] = tokenId;
        tokensURI[tokenId] = _uri;

        _mint(msg.sender, tokenId);

        emit Mint(_videoId, msg.sender, block.timestamp, mintingPrice);
    }

    function askSponsorship(
        uint256 _price,
        string memory _videoId,
        string memory _uri,
        bytes32 hash,
        bytes memory signature
    ) external {
        require(
            hashTransaction(
                keccak256(abi.encodePacked(_price, _videoId, msg.sender))
            ) == hash,
            "TRANSACTION_HASH_FAILED"
        );
        require(matchAddresSigner(hash, signature), "WRONG_SIGNATURE");
        require(videoIdtoTokenId[_videoId] == 0, "Video Id already minted");

        sponsorshipByVideoId[_videoId] = Sponsorship({
            price: _price,
            timestamp: block.timestamp,
            claimed: false
        });

        uint256 mintingPrice = (_price * 120) / 100;

        IERC20(TPLToken).transferFrom(msg.sender, treasuryWallet, mintingPrice);

        uint256 tokenId = totalSupply() + 1;

        NFTdetails[tokenId] = NFT({
            minter: treasuryWallet,            
            postCreator: address(0),
            videoId: _videoId,
            transferable: false,
            commentsActive: true,
            price: 0
        });

        videoIdtoTokenId[_videoId] = tokenId;
        tokensURI[tokenId] = _uri;

        _mint(msg.sender, tokenId);

        emit SponsorshipMint(
            _videoId,
            msg.sender,
            block.timestamp,
            mintingPrice
        );
    }

    function claimSponsorship(
        string memory _videoId,
        bytes32 hash,
        bytes memory signature
    ) external {
        require(
            hashTransaction(
                keccak256(abi.encodePacked(_videoId, msg.sender))
            ) == hash,
            "TRANSACTION_HASH_FAILED"
        );
        require(matchAddresSigner(hash, signature), "WRONG_SIGNATURE");
        require(
            !sponsorshipByVideoId[_videoId].claimed,
            "sponsorship already claimed"
        );

        uint256 creatorFee = sponsorshipByVideoId[_videoId].price ;

        uint256 tokenId = videoIdtoTokenId[_videoId];

        sponsorshipByVideoId[_videoId].claimed = true;
        
        NFTdetails[tokenId].postCreator = msg.sender;

        IERC20(TPLToken).transferFrom(
            treasuryWallet,
            NFTdetails[tokenId].postCreator,
            creatorFee
        );

        emit ClaimSponsorship(
            _videoId,
            msg.sender,
            block.timestamp,
            creatorFee
        );
    }

    function setTransferableStatus(
        uint256 _tokenId,
        uint256 _price,
        bool _status
    ) external {
        require(msg.sender == ownerOf(_tokenId), "Not the token owner");
        require(
            _price > 0 && _price <= 200,
            "Price should be between 0.01 and 2"
        );

        NFTdetails[_tokenId].transferable = _status;
        NFTdetails[_tokenId].price = _price;

        emit SetTransferable(NFTdetails[_tokenId].videoId, _status);
    }

    function acquire(
        uint256 _tokenId,
        uint256 _price,
        bytes32 hash,
        bytes memory signature
    ) external {
        require(
            hashTransaction(
                keccak256(abi.encodePacked(_tokenId, _price, msg.sender))
            ) == hash,
            "TRANSACTION_HASH_FAILED"
        );
        require(matchAddresSigner(hash, signature), "WRONG_SIGNATURE");
        require(NFTdetails[_tokenId].transferable, "NFT not for sale");

        address prevOwner = ownerOf(_tokenId);

        uint256 buyingPrice = (_price * NFTdetails[_tokenId].price) / 100;

        uint256 creatorFee = (buyingPrice * 15) / 100;
        uint256 adminFee = (buyingPrice * 5) / 100;

        if (NFTdetails[_tokenId].postCreator == address(0)) {
            adminFee += creatorFee;
            creatorFee = 0;
        } else {
            IERC20(TPLToken).transferFrom(
                msg.sender,
                NFTdetails[_tokenId].postCreator,
                creatorFee
            );
        }

        IERC20(TPLToken).transferFrom(msg.sender, treasuryWallet, adminFee);
        IERC20(TPLToken).transferFrom(
            msg.sender,
            prevOwner,
            buyingPrice - creatorFee - adminFee
        );

        NFTdetails[_tokenId].transferable = false;

        _transfer(prevOwner, msg.sender, _tokenId);

        emit Acquire(
            NFTdetails[_tokenId].videoId,
            prevOwner,
            msg.sender,
            buyingPrice
        );
    }

    function saveComment(uint256 _tokenId, string memory _comment) external {     
        uint256 index = commentsIndexByToken[_tokenId]; 

        commentsByToken[_tokenId][index] =  Comments({
            user: msg.sender,
            timestamp: block.timestamp,
            index: index,
            comment: _comment,
            deleted: false
        });

        commentsIndexByToken[_tokenId]++;
        emit CommentAdded(msg.sender, _tokenId, index);
    }

    function deleteComment(uint256 _tokenId, uint256 index) external {
        require(
            msg.sender == ownerOf(_tokenId) || msg.sender == NFTdetails[_tokenId].minter,
            "only owner or minter can delete comments"
        );

        commentsByToken[_tokenId][index].deleted = true;
        emit CommentDeleted(msg.sender, _tokenId, index);
    }

    function turnDownComments(uint256 _tokenId, bool _status) external {
        require(
            msg.sender == ownerOf(_tokenId),
            "only comments owner can turn down"
        );

        NFTdetails[_tokenId].commentsActive = _status;
        statusById[_tokenId] = CommentStatus({
            closedBy: msg.sender,
            timestamp: block.timestamp
        });

        emit CommentStatusChanged(msg.sender, _status, block.timestamp);
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721)
        returns (string memory)
    {
        require(_exists(tokenId), "Cannot query non-existent token");

        return tokensURI[tokenId];
    }

    function detailsByVideoId(string memory _videoId)
        external
        view
        returns (
            uint256 tokenId,
            address owner,
            string memory uri,
            NFT memory details,
            CommentStatus memory status    
        )
    {
        tokenId = videoIdtoTokenId[_videoId];
        (owner, uri, details, status) = detailsByTokenId(tokenId); 
    }

    function detailsByTokenId(uint256 tokenId)
        public
        view
        returns (
            address owner,
            string memory uri,
            NFT memory details,
            CommentStatus memory status            
        )
    {
        owner = ownerOf(tokenId);
        uri = tokensURI[tokenId];
        details = NFTdetails[tokenId];
        status = statusById[tokenId];
    }

    function getComments (uint256 tokenId) external view returns (Comments[] memory comments){
        if (NFTdetails[tokenId].commentsActive) {
            uint256 arrayLength = commentsIndexByToken[tokenId];
            comments = new Comments[](arrayLength);

            for (uint256 i = 0; i < arrayLength; i++) {
                comments[i] = commentsByToken[tokenId][i];
            }
        } else {
            comments = new Comments[](0);
        }
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

    function hashTransaction(bytes32 s) public pure returns (bytes32) {
        return ECDSA.toEthSignedMessageHash(s);
    }

    function matchAddresSigner(bytes32 hash, bytes memory signature)
        internal
        view
        returns (bool)
    {
        return _signerAddress == hash.recover(signature);
    }
}
