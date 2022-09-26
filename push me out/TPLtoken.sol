// SPDX-License-Identifier: MIT LICENSE

pragma solidity ^0.8.0;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract VTE is ERC20, Ownable {

    constructor(address _owner) ERC20("Voice2Earn Token", "VTE") {
        _mint(_owner, 1000000 ether);
        transferOwnership(_owner);
    }

    function mint(address to, uint256 amount) external onlyOwner{
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}
