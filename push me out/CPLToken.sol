// SPDX-License-Identifier: MIT LICENSE

pragma solidity ^0.8.0;
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/ERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol";

contract CPLToken is ERC20, Ownable { 
  
  mapping(address => bool) controllers;
  
  constructor() ERC20("Commitee of Prize Locker", "CPL") { } 
 
  function mint(address to, uint256 amount) external {    
    require(controllers[msg.sender], "Only controllers can mint");
    
    _mint(to, amount);
  } 

  function addController(address controller) external onlyOwner {
    controllers[controller] = true;
  }
  
  function removeController(address controller) external onlyOwner {
    controllers[controller] = false;
  }
}