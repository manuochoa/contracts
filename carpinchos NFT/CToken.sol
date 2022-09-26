// SPDX-License-Identifier: MIT
pragma solidity 0.8.12;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract CToken is ERC20, Ownable {
    uint8 public constant decimalPlaces = 0;
    uint256 public constant maxSupply = 365000000;
    uint256 public constant treasuryLiquidity = 30000000;
    uint256 public burned;

    address public masterContract;

    bool public open;

    mapping(address => uint256) public claims;

    constructor() ERC20("CryptoCarpinchos Token", "CToken") {      
        _mint(msg.sender, treasuryLiquidity);
    }

     modifier onlyAllowed() {
        require(
            owner() == msg.sender || masterContract == msg.sender,
            "Ownable: caller is not the Master Contract"
        );
        _;
    }

    function claim(address wallet, uint256 tokenAmount) external onlyAllowed {
        require(open, "Contract is not open");
        require(totalSupply() + tokenAmount <= maxSupply, "Exceeds max supply");

        _mint(wallet, tokenAmount);
        claims[wallet] += tokenAmount;
    }    

    function pay(uint256 paymentAmount) external onlyAllowed {
        require(open, "Contract is not open");      
        require(balanceOf(tx.origin) >= paymentAmount, "Insufficient funds");
       
        _burn(tx.origin, paymentAmount);
        burned += paymentAmount;        
    }

    function setOpen(bool _open) external onlyOwner {
        open = _open;
    }

     function setMasterContract(address newMasterContract) external onlyOwner {
        require(newMasterContract != address(0), "cannot set zero address");
        masterContract = newMasterContract;
    }  

    function decimals() public view virtual override returns (uint8) {
        return decimalPlaces;
    }
}
