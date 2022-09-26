// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./launchpad.sol";

contract Deployer is Ownable {
    uint256 public launchpadCount;
    uint256 public deployCost = 0.01 ether;
    uint256 public totalInvested;
    uint256 public totalParticipants;

    address public senseiLocker;

    mapping(uint256 => address) public launchpadById;
    mapping(address => uint256) public launchpadIdByAddress;
    mapping(address => bool) private isLaunchpad;
    mapping(address => address) public launchpadByToken;
    mapping(address => address[]) public userLaunchpadInvested;
    mapping(address => mapping(address => bool)) isLaunchpadAdded;

    event launchpadDeployed(address newTokenAddress, address deployer);

    function createLaunchpad(
        uint256[] memory _prices,
        uint256[] memory _caps,
        uint256[] memory _limits,
        uint256[] memory _times,
        uint256 _lockupPeriod,
        uint256 _liquidityPerc,
        string memory _URIData,
        address _token,
        bool whitelist
    ) public payable {
        require(msg.value >= deployCost, "Not enough BNB to deploy");
        require(
            launchpadByToken[_token] == address(0),
            "Launchpad already created"
        );

        address[] memory _addresses = new address[](3);
        _addresses[0] = _token;
        _addresses[1] = msg.sender;
        _addresses[2] = senseiLocker;
        launchPad newLaunchpad = new launchPad(
            _prices,
            _caps,
            _limits,
            _times,
            _lockupPeriod,
            _liquidityPerc,
            _URIData,
            _addresses,
            whitelist
        );
        newLaunchpad.transferOwnership(owner());

        uint256 tokensToDistribute = _prices[0] * _caps[1];
        uint256 tokensToLiquidity = (_prices[1] * _caps[1] * _liquidityPerc) /
            100;
        uint256 tokensNeeded = ((tokensToDistribute + tokensToLiquidity) *
            10**ERC20(_token).decimals()) / 100000000;

        ERC20(_token).transferFrom(
            msg.sender,
            address(newLaunchpad),
            tokensNeeded
        );

        payable(owner()).transfer(msg.value);

        launchpadById[launchpadCount] = address(newLaunchpad);
        launchpadIdByAddress[address(newLaunchpad)] = launchpadCount;
        launchpadCount++;

        launchpadByToken[_token] = address(newLaunchpad);
        isLaunchpad[address(newLaunchpad)] = true;

        emit launchpadDeployed(address(newLaunchpad), msg.sender);
    }

    function getDeployedLaunchpads(uint256 startIndex, uint256 endIndex)
        public
        view
        returns (address[] memory)
    {
        if (endIndex >= launchpadCount) {
            endIndex = launchpadCount - 1;
        }

        uint256 arrayLength = endIndex - startIndex + 1;
        uint256 currentIndex;
        address[] memory launchpadAddress = new address[](arrayLength);

        for (uint256 i = startIndex; i <= endIndex; i++) {
            launchpadAddress[currentIndex] = launchpadById[startIndex + i];
            currentIndex++;
        }

        return launchpadAddress;
    }

    function setPrice(uint256 _price) external onlyOwner {
        deployCost = _price;
    }

    //     function getContractNumbers() external view returns (uint256 [] memory)
    // function getContractInfo() external view returns (uint8 _status, string memory _URIData, address _contractAdmin, address _tokenAddress, bool _whitelistActive, bool _remainingClaimed)
    function getInfo(uint256 id)
        external
        view
        returns (
            uint256[] memory data,
            uint8 _status,
            uint8 decimals,
            uint256 _score,
            string memory _URIData,
            string[] memory symbol,
            address _contractAdmin,
            address _tokenAddress,
            address contractAddress,
            bool [] memory booleans
        )
    {
        contractAddress = launchpadById[id];

        launchPad instance = launchPad(contractAddress);

        data = new uint256[](14);
        data = instance.getContractNumbers();
        
        (
            _status,
            _score,
            _URIData,
            _contractAdmin,
            _tokenAddress,
            booleans
        ) = instance.getContractInfo();

        symbol = new string[](2);

        decimals = ERC20(_tokenAddress).decimals();
        symbol[0] = ERC20(_tokenAddress).symbol();
        symbol[1] = ERC20(_tokenAddress).name();
    }

    function addToUserLaunchpad(address _user, address _launchpad) external {
        require(isLaunchpad[msg.sender], "Only launchpads can add");

        if (!isLaunchpadAdded[_user][_launchpad]) {
            userLaunchpadInvested[_user].push(_launchpad);
            isLaunchpadAdded[_user][_launchpad] = true;
        }
    }

    function updateStats(uint256 _invested, uint256 _contributors) external {
        require(isLaunchpad[msg.sender], "Only launchpads can add");

        totalInvested += _invested;
        totalParticipants += _contributors;
    }

    function removeLaunchpad(address _token, address _launchpad) external {
        require(isLaunchpad[msg.sender], "Only launchpads can remove");

        launchpadByToken[_token] = address(0);
        isLaunchpad[_launchpad] = false;
    }

    function getUserContributions(address _user)
        external
        view
        returns (uint256[] memory ids, uint256[] memory contributions)
    {
        uint256 count = userLaunchpadInvested[_user].length;
        ids = new uint256[](count);
        contributions = new uint256[](count);

        for (uint256 i; i < count; i++) {
            address launchpadaddress = userLaunchpadInvested[_user][i];
            ids[i] = launchpadIdByAddress[launchpadaddress];
            contributions[i] = launchPad(launchpadaddress).depositedAmount(
                _user
            );
        }
    }

    function getStats()
        external
        view
        returns (
            uint256 _projects,
            uint256 _invested,
            uint256 _participants
        )
    {
        _projects = launchpadCount;
        _invested = totalInvested;
        _participants = totalParticipants;
    }

    function changeLockerAddress(address _newLocker) external onlyOwner {
        senseiLocker = _newLocker;
    }
}
