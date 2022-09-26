// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/IERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC721/extensions/ERC721Enumerable.sol";

contract lottoMax is Ownable, ERC721Enumerable {
    uint256 public roundNum;
    uint256 public totalPayout;
    uint256 public lastEntry;
    uint256 public jackpot;
    uint256 public smallPrizePot;
    uint256 public earningsToClaim;
    uint256 public winnerIndex;
    uint256 public price = 10 ether;

    IERC20 public BUSD;
    address public marketingWallet;

    struct Results {
        uint256 totalEntries;
        uint256 winningNumber;
        uint256 payout;
        uint256 endTime;
        address winningAddress;
    }

    mapping(uint256 => Results) public roundResults;
    mapping(uint256 => address) public roundEntry;
    mapping(address => uint256[]) public entriesIndex;
    mapping(address => uint256) public userEarnings;

    event LotteryWon(address winner, uint256 amount);

    constructor(address _busd, address _marketing) ERC721("Lotto Max", "LMAX") {
        BUSD = IERC20(_busd);
        marketingWallet = _marketing;
    }

    function butTickets(uint256 amount) external {
        uint256 payment = getPrice(amount);

        BUSD.transferFrom(msg.sender, address(this), payment);

        uint256 tokenId = totalSupply();

        for (uint256 i; i < amount; i++) {
            _mint(msg.sender, tokenId + i);
        }

        updatePot();
    }

    function claimEarnings() external {
        uint256 earnings = userEarnings[msg.sender];
        require(earnings > 0, "no earnings for this user");

        userEarnings[msg.sender] = 0;
        earningsToClaim -= earnings;

        BUSD.transfer(msg.sender, earnings);

        updatePot();
    }

    function pickJackpotWinner(uint256 seed) external onlyOwner {
        require(jackpot > 0, "no rewards for this pot");
        updatePot();

        (address winnerAddress, uint256 winnerNum) = pickWinner(seed);

        uint256 prize = jackpot;

        jackpot = 0;

        updateWinner(winnerAddress, winnerNum, prize);
    }

    function pickSmallWinner(uint256 seed, uint256 winners) external onlyOwner {
        require(smallPrizePot > 0, "no rewards for this pot");
        updatePot();

        uint256 prize = smallPrizePot / winners;
        smallPrizePot = 0;

        for (uint256 i; i < winners; i++) {
            (address winnerAddress, uint256 winnerNum) = pickWinner(seed * i);
            updateWinner(winnerAddress, winnerNum, prize);
        }
    }

    function nextRound() external onlyOwner {
        lastEntry = totalSupply();
        roundNum++;
    }

    function updatePrice(uint256 _newPrice) external onlyOwner {
        price = _newPrice;
    }

    function updatePot() internal {
        uint256 nonAccountedBalance = BUSD.balanceOf(address(this)) -
            jackpot -
            smallPrizePot -
            earningsToClaim;

        if (nonAccountedBalance > 0) {
            uint256 marketingFee = (nonAccountedBalance * 25) / 100;
            jackpot += (nonAccountedBalance * 55) / 100;
            smallPrizePot += (nonAccountedBalance * 20) / 100;

            BUSD.transfer(marketingWallet, marketingFee);
        }
    }

    function pickWinner(uint256 seed)
        public
        view
        returns (address winnerAddress, uint256 winnerNum)
    {
        uint256 entries = roundEntries();
        require(entries > 0, "no entries for this round");

        winnerNum = lastEntry + (random(seed) % entries);
        winnerAddress = ownerOf(winnerNum);
    }

    function roundEntries() public view returns (uint256) {
        return totalSupply() - lastEntry;
    }

    function updateWinner(
        address winnerAddress,
        uint256 winnerNum,
        uint256 payout
    ) internal {
        roundResults[winnerIndex] = Results({
            totalEntries: roundEntries(),
            winningNumber: winnerNum,
            payout: payout,
            endTime: block.timestamp,
            winningAddress: winnerAddress
        });

        totalPayout += payout;
        earningsToClaim += payout;
        userEarnings[winnerAddress] += payout;
        winnerIndex++;

        emit LotteryWon(winnerAddress, payout);
    }

    function getPrice(uint256 amount) internal view returns (uint256 payment) {
        if(amount > 99){
            payment = (amount * price * 80) / 100; // 20% discount; 
        } else if(amount > 49){
            payment = (amount * price * 85) / 100; // 15% discount; 
        } else if(amount > 9){
            payment = (amount * price * 90) / 100; // 10% discount; 
        } else {
            payment = amount * price;
        }
    }

    function getParticipants() external view returns (address[] memory _users) {
        uint256 entries = roundEntries();
        uint256 supply = totalSupply() - 1;
        _users = new address[](entries);

        for (uint256 i; i < entries; i++) {
            _users[i] = ownerOf(supply - i);
        }
    }

    function resultLog(uint256 startIndex, uint256 endIndex)
        external
        view
        returns (Results[] memory log)
    {
        if (winnerIndex == 0) {
            return log = new Results[](0);
        }

        if (endIndex >= winnerIndex) {
            endIndex = winnerIndex - 1;
        }

        uint256 arrayLength = endIndex - startIndex + 1;
        uint256 currentIndex;
        log = new Results[](arrayLength);

        for (uint256 i = startIndex; i <= endIndex; i++) {
            log[currentIndex] = roundResults[startIndex + i];
            currentIndex++;
        }
    }

    function walletOfOwner(address _owner)
        external
        view
        returns (uint256[] memory)
    {
        uint256 tokenCount = balanceOf(_owner);

        uint256[] memory tokensId = new uint256[](tokenCount);
        for (uint256 i = 0; i < tokenCount; i++) {
            tokensId[i] = tokenOfOwnerByIndex(_owner, i);
        }

        return tokensId;
    }

    function random(uint256 seed) internal view returns (uint256) {
        return
            uint256(
                keccak256(
                    abi.encodePacked(
                        seed,
                        block.timestamp,
                        gasleft(),
                        msg.sender,
                        roundEntries()
                    )
                )
            );
    }
}
