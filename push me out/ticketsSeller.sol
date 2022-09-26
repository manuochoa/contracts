// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";


contract ticketSeller is  Ownable, ERC1155Holder { 
    
    IERC1155 public ticketsContract;
    IERC20 public TPLtoken;

    uint256 public ticketPrice = 1 ether;

    string baseURI = "ipfs://";

    constructor(address _tickets, address _TPL) {
       ticketsContract = IERC1155(_tickets);
       TPLtoken = IERC20(_TPL);
    }

    function buyTokens(uint256 tokenId, uint256 amount) public {

        TPLtoken.transferFrom(
            msg.sender, 
            address(this), 
            ticketPrice * amount
        );

         ticketsContract.safeTransferFrom(
            address(this),
            msg.sender,
            tokenId,
            amount,
            "0x00"
        );
    }   
}
