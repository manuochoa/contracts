// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract testERC1155 is ERC1155 {
    using Strings for uint256;

    address public machineCreator;

    string baseURI = "ipfs://";

    constructor(address _machineCreator) ERC1155("ipfs://") {
        machineCreator = _machineCreator;
    }

    function mint(uint256 _id, uint256 _amount) public {
        _mint(msg.sender, _id, _amount, "0x00");
    }

    function changeMachineCreator (address _machineCreator) external{
        machineCreator = _machineCreator;
    }

    function uri(uint256 tokenId)
        public
        view
        virtual
        override
        returns (string memory)
    {
        return string(abi.encodePacked(baseURI, tokenId.toString()));
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) public virtual override {
        require(
            from == _msgSender() || _msgSender() == machineCreator || isApprovedForAll(from, _msgSender()),
            "ERC1155: caller is not owner nor approved"
        );
        _safeTransferFrom(from, to, id, amount, data);
    }
   
}
