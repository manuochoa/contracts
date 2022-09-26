//SPDX-License-Identifier: MIT

pragma solidity =0.8.11;

import "./flokiToken.sol";

contract FlokiGainzToken is DeflationaryERC20 {
    constructor(address _owner)  DeflationaryERC20("FlokiGainz", "GAINZ", 6) {
        // maximum supply   = 500m with decimals = 6
        _mint(_owner, 500e12);
        transferOwnership(_owner);
    }
}