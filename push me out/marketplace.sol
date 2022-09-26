// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Address.sol";

interface IMarketplace {
    struct Order {
        uint256 orderId;
        address seller;
        address nftAddress;
        uint256 nftId;
        uint256 createdAt;
        uint256 price;
    }

    // Helper Structs

    struct Seller {
        uint256 total;
        uint256[] ordersIds;
    }

    // ORDER EVENTS
    event OrderCreated(
        uint256 orderId,
        address indexed seller,
        address indexed nftAddress,
        uint256 nftId,
        uint256 createdAt,
        uint256 priceInWei
    );

    event OrderUpdated(uint256 orderId, uint256 priceInWei);

    event OrderSuccessful(
        uint256 orderId,
        address indexed buyer,
        uint256 priceInWei
    );

    event OrderCancelled(uint256 id);
}

contract Marketplace is Ownable, IMarketplace, ERC721Holder, ReentrancyGuard {
    using Address for address;

    IERC20 public acceptedToken;

    // From ERC721 address => tokenId => Order (to avoid asset collision)
    mapping(address => mapping(uint256 => Order)) public orderByAssetId;

    // Collect orders from seller address
    mapping(address => uint256[]) public ordersBySeller;
    mapping(uint256 => uint256) public ordersIndex;

    // collect order from order id
    mapping(uint256 => Order) public orderById;

    // Orders id counter
    uint256 public orders;

    // marketplace owner's cut
    uint256 public managerCut;

    constructor(address _acceptedToken) Ownable() {
        require(
            _acceptedToken.isContract(),
            "The accepted token address must be a deployed contract"
        );

        acceptedToken = IERC20(_acceptedToken);
    }

    function createOrder(
        address _nftAddress,
        uint256 _assetId,
        uint256 _priceInWei
    ) external {
        require(_priceInWei > 0, "Marketplace: Price should be bigger than 0");

        // get NFT asset from seller
        IERC721(_nftAddress).safeTransferFrom(
            msg.sender,
            address(this),
            _assetId
        );

        // create the orderId
        uint256 orderId = orders;
        orders++;

        // save order
        orderByAssetId[_nftAddress][_assetId] = Order({
            orderId: orderId,
            seller: msg.sender,
            nftAddress: _nftAddress,
            nftId: _assetId,
            createdAt: block.timestamp,
            price: _priceInWei
        });

        ordersIndex[orderId] = ordersBySeller[msg.sender].length;
        ordersBySeller[msg.sender].push(orderId);

        orderById[orderId] = orderByAssetId[_nftAddress][_assetId];

        emit OrderCreated(
            orderId,
            msg.sender,
            _nftAddress,
            _assetId,
            block.timestamp,
            _priceInWei
        );
    }

    function cancelOrder(address _nftAddress, uint256 _assetId) external {
        Order memory order = orderByAssetId[_nftAddress][_assetId];

        require(
            order.seller == msg.sender || msg.sender == owner(),
            "Marketplace: unauthorized sender"
        );

        removeOrder(msg.sender, order.orderId);

        /// send asset back to seller
        IERC721(_nftAddress).safeTransferFrom(
            address(this),
            order.seller,
            _assetId
        );

        emit OrderCancelled(order.orderId);
    }

    function updateOrder(
        address _nftAddress,
        uint256 _assetId,
        uint256 _priceInWei
    ) external {
        Order storage order = orderByAssetId[_nftAddress][_assetId];

        // Check valid order to update
        require(order.seller == msg.sender, "Marketplace: sender not allowed");

        // check order updated params
        require(_priceInWei > 0, "Marketplace: Price should be bigger than 0");

        order.price = _priceInWei;
        orderById[order.orderId].price = _priceInWei;

        emit OrderUpdated(order.orderId, _priceInWei);
    }

    function safeExecuteOrder(address _nftAddress, uint256 _assetId)
        external
        nonReentrant
    {
        Order memory order = orderByAssetId[_nftAddress][_assetId];

        uint256 marketFee = 0;

        if (managerCut > 0) {
            marketFee = (order.price * managerCut) / 10000;
        }

        // Transfer accepted token amount to seller
        acceptedToken.transferFrom(
            msg.sender, // buyer
            order.seller, // seller
            order.price - marketFee
        );

        // Transfer marketFee
        acceptedToken.transferFrom(
            msg.sender, // buyer
            address(this), // seller
            marketFee
        );

        removeOrder(order.seller, order.orderId);

        // Transfer NFT asset
        IERC721(_nftAddress).safeTransferFrom(
            address(this),
            msg.sender,
            _assetId
        );

        // Notify ..
        emit OrderSuccessful(order.orderId, msg.sender, order.price);
    }

    function removeOrder(address seller, uint256 orderId) internal {
        uint256 lastOrderId = ordersBySeller[seller][
            ordersBySeller[seller].length - 1
        ];

        ordersBySeller[seller][ordersIndex[orderId]] = lastOrderId;

        ordersIndex[lastOrderId] = ordersIndex[orderId];

        ordersBySeller[seller].pop();

        delete orderByAssetId[orderById[orderId].nftAddress][
            orderById[orderId].nftId
        ];
        delete orderById[orderId];
    }

    function setOwnerCut(uint256 _ownerCut) external onlyOwner {
        managerCut = _ownerCut;
    }

    function getOrdersId(address _sellerAddress)
        public
        view
        returns (uint256[] memory)
    {
        uint256 ordersCount = ordersBySeller[_sellerAddress].length;

        uint256[] memory ordersIds = new uint256[](ordersCount);
        for (uint256 i = 0; i < ordersCount; i++) {
            ordersIds[i] = ordersBySeller[_sellerAddress][i];
        }

        return ordersIds;
    }
}
