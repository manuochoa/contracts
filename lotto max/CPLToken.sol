// SPDX-License-Identifier: MIT LICENSE

pragma solidity ^0.8.0;
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/ERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol";

contract CPLToken is ERC20, Ownable {

    constructor() ERC20("TEST", "TEST") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
