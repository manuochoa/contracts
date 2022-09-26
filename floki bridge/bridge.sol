// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IERC20Decimals is IERC20 {
    function decimals() external view returns (uint8);
}

contract TokenBridge is Ownable {
    IERC20Decimals private _token;

    address public tokenOwner;
    address payable public oracleAddress;
    uint256 public maxSwapAmount;
    uint8 public targetTokenDecimals;
    uint256 public minimumGasForOperation = 2 * 10**15; // 2 finney (0.002 ETH)
    bool public isActive = true;

    struct Swap {
        bytes32 id;
        uint256 origTimestamp;
        uint256 currentTimestamp;
        bool isOutbound;
        bool isComplete;
        bool isRefunded;
        bool isSendGasFunded;
        address swapAddress;
        uint256 amount;
    }

    mapping(bytes32 => Swap) public swaps;
    mapping(address => Swap) public lastUserSwap;

    event ReceiveTokensFromSource(
        bytes32 indexed id,
        uint256 origTimestamp,
        address sender,
        uint256 amount
    );

    event SendTokensToDestination(
        bytes32 indexed id,
        address receiver,
        uint256 amount
    );

    event RefundTokensToSource(
        bytes32 indexed id,
        address sender,
        uint256 amount
    );

    event swapFunded(
        bytes32 indexed id,
        address sender,
        uint256 amount
    );

    event TokenOwnerUpdated(address previousOwner, address newOwner);

    constructor(
        address _oracleAddress,
        address _tokenOwner,
        address _tokenAddy,
        uint8 _targetTokenDecimals,
        uint256 _maxSwapAmount
    ) {
        oracleAddress = payable(_oracleAddress);
        tokenOwner = _tokenOwner;
        _token = IERC20Decimals(_tokenAddy);
        targetTokenDecimals = _targetTokenDecimals;
        maxSwapAmount = _maxSwapAmount;
    }

    function getSwapTokenAddress() external view returns (address) {
        return address(_token);
    }

    function setActiveState(bool _isActive) external {
        require(
            msg.sender == owner() || msg.sender == tokenOwner,
            "setActiveState user must be contract creator"
        );
        isActive = _isActive;
    }

    function setOracleAddress(address _oracleAddress) external onlyOwner {
        oracleAddress = payable(_oracleAddress);
        transferOwnership(oracleAddress);
    }

    function setTargetTokenDecimals(uint8 _decimals) external onlyOwner {
        targetTokenDecimals = _decimals;
    }

    function setTokenOwner(address newOwner) external {
        require(
            msg.sender == tokenOwner,
            "user must be current token owner to change it"
        );
        address previousOwner = tokenOwner;
        tokenOwner = newOwner;
        emit TokenOwnerUpdated(previousOwner, newOwner);
    }

    function withdrawTokens(uint256 _amount) external {
        require(
            msg.sender == tokenOwner,
            "withdrawTokens user must be token owner"
        );
        _token.transfer(msg.sender, _amount);
    }

    function setSwapCompletionStatus(bytes32 _id, bool _isComplete)
        external
        onlyOwner
    {
        swaps[_id].isComplete = _isComplete;
    }

    function setMinimumGasForOperation(uint256 _amountGas) external onlyOwner {
        minimumGasForOperation = _amountGas;
    }

    function receiveTokensFromSource(uint256 _amount)
        external
        payable
        returns (bytes32, uint256)
    {
        require(isActive, "this atomic swap instance is not active");
        require(
            msg.value >= minimumGasForOperation,
            "you must also send enough gas to cover the target transaction"
        );
        require(
            maxSwapAmount == 0 || _amount <= maxSwapAmount,
            "trying to send more than maxSwapAmount"
        );

        if (minimumGasForOperation > 0) {
            oracleAddress.call{value: minimumGasForOperation}("");
        }
        _token.transferFrom(msg.sender, address(this), _amount);

        uint256 _ts = block.timestamp;
        bytes32 _id = sha256(abi.encodePacked(msg.sender, _ts, _amount));
        swaps[_id] = Swap({
            id: _id,
            origTimestamp: _ts,
            currentTimestamp: _ts,
            isOutbound: false,
            isComplete: false,
            isRefunded: false,
            isSendGasFunded: false,
            swapAddress: msg.sender,
            amount: _amount
        });
        lastUserSwap[msg.sender] = swaps[_id];
        emit ReceiveTokensFromSource(_id, _ts, msg.sender, _amount);
        return (_id, _ts);
    }

    function unsetLastUserSwap(address _addy) external onlyOwner {
        delete lastUserSwap[_addy];
    }

    function fundSendToDestinationGas(
        bytes32 _id,
        uint256 _origTimestamp,
        uint256 _amount
    ) external payable {
        require(
            msg.value >= minimumGasForOperation,
            "you must send enough gas to cover the send transaction"
        );
        require(
            _id ==
                sha256(abi.encodePacked(msg.sender, _origTimestamp, _amount)),
            "we don't recognize this swap"
        );
        if (minimumGasForOperation > 0) {
            oracleAddress.call{value: minimumGasForOperation}("");
        }
        // swaps[_id] = Swap({
        //     id: _id,
        //     origTimestamp: _origTimestamp,
        //     currentTimestamp: block.timestamp,
        //     isOutbound: true,
        //     isComplete: false,
        //     isRefunded: false,
        //     isSendGasFunded: true,
        //     swapAddress: msg.sender,
        //     amount: _amount
        // });
        swaps[_id].id = _id;
        swaps[_id].origTimestamp = _origTimestamp;
        swaps[_id].isOutbound = true;
        swaps[_id].isSendGasFunded = true;
        swaps[_id].swapAddress = msg.sender;
        swaps[_id].amount = _amount;

        emit swapFunded(_id, msg.sender, _amount);
    }

    function refundTokensFromSource(bytes32 _id) external {
        require(isActive, "this atomic swap instance is not active");

        Swap storage swap = swaps[_id];

        _confirmSwapExistsGasFundedAndSenderValid(swap);
        swap.isRefunded = true;
        _token.transfer(swap.swapAddress, swap.amount);
        emit RefundTokensToSource(_id, swap.swapAddress, swap.amount);
    }

    function sendTokensToDestination(bytes32 _id) external returns (bytes32) {
        require(isActive, "this atomic swap instance is not active");

        Swap storage swap = swaps[_id];

        _confirmSwapExistsGasFundedAndSenderValid(swap);

        uint256 _swapAmount = swap.amount;
        if (targetTokenDecimals > 0) {
            _swapAmount =
                (_swapAmount * 10**_token.decimals()) /
                10**targetTokenDecimals;
        }
        _token.transfer(swap.swapAddress, _swapAmount);

        swap.currentTimestamp = block.timestamp;
        swap.isComplete = true;
        emit SendTokensToDestination(_id, swap.swapAddress, _swapAmount);
        return _id;
    }

    function _confirmSwapExistsGasFundedAndSenderValid(Swap memory swap)
        private
        view
        onlyOwner
    {
        require(
            swap.origTimestamp > 0 && swap.amount > 0,
            "swap does not exist yet."
        );
        require(
            !swap.isComplete && !swap.isRefunded && swap.isSendGasFunded,
            "swap has already been completed, refunded, or gas has not been funded"
        );
    }
}
