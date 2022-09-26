// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/finance/PaymentSplitter.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract RoyaltiesWallet is PaymentSplitter, Ownable {    
    
    uint[] private _shares = [20, 40];
    address[] private _team = [
        0xfacEBeBe5989c2b72b51545300fb01a92a4C90Bc,
        0xA89e554f2E5D442426245b016FFbBb9e04B3d4b2            
    ];

    constructor () PaymentSplitter(_team, _shares) payable {}
        
    function totalBalance() public view returns(uint) {
        return address(this).balance;
    }
        
    function totalReceived() public view returns(uint) {
        return totalBalance() + totalReleased();
    }
    
    function balanceOf(address _account) public view returns(uint) {
        return totalReceived() * shares(_account) / totalShares() - released(_account);
    }
    
    function release(address payable account) public override onlyOwner {
        super.release(account);
    }
    
    function withdraw() public {
        require(balanceOf(msg.sender) > 0, "No funds to withdraw");
        super.release(payable(msg.sender));
    }
    
}