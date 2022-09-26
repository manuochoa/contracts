// SPDX-License-Identifier:MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract OneEarthNFT is ERC721Enumerable, Ownable {
    using Strings for uint256;

    uint256 public constant MINT_PRICE = 0.2 ether;
    uint256 public immutable MAX_TOKENS = 2763;
    uint256 public minted;
    uint256 public totalRewards;
    uint256 public tokenReflectionRewards;
    uint256 public nonDeliveredReflections;

    uint256[] public tierMaxMint = [0, 1500, 500, 500, 250, 13];

    struct TokenDetails {
        uint256 tier;
        uint256 lastClaim;
        uint256 tierIndex;
        uint256 lastReflection;
    }

    mapping(uint256 => string) public tierBaseUri;
    mapping(uint256 => uint256) public tierMinted;
    mapping(uint256 => uint256) public rewardsByTier;
    mapping(uint256 => TokenDetails) public detailsByTokenId;

    address earthToken;
    address public treasuryWallet = 0xfe0EcA73E518eB32C9A69cFEB5423E235Aa3c398;

    event rewardsClaimed(uint256 amount, uint256 timestamp, address user);
    event reflectionsClaimed(uint256 amount, uint256 timestamp, address user);

    constructor() ERC721("OneEarth Nicaragua", "OneEarth1") {}

    function mint(uint256 amount) external payable {
        require(msg.value == MINT_PRICE * amount, "WRONG_AVAX_AMOUNT");
        require(minted + amount < MAX_TOKENS, "MAX_SUPPLY_REACHED");
        require(amount <= 20 && amount > 0, "INVALID_AMOUNT");

        uint256 tokenId = totalSupply();
        uint256 distributed;

        for (uint256 i; i < amount; i++) {
            uint256 tier = getRandomNumber();

            distributed += distributeRewards(tier);

            detailsByTokenId[tokenId + i] = TokenDetails({
                tier: tier,
                lastClaim: getRewardsByTier(tier),
                tierIndex: tierMinted[tier],
                lastReflection: tokenReflectionRewards
            });

            minted++;
            tierMinted[tier]++;

            _safeMint(msg.sender, tokenId + i);
        }

        payable(treasuryWallet).transfer(msg.value - distributed);
    }

    function checkTier(uint256 num) internal view returns (bool) {
        return tierMinted[num] < tierMaxMint[num];
    }

    function getRandomNumber() internal view returns (uint256) {
        uint256 random = uint256(
            keccak256(abi.encodePacked(block.timestamp, gasleft(), msg.sender))
        ) % 100;
        if (random < 54) {
            random = 1;
        } else if (random < 72) {
            random = 2;
        } else if (random < 90) {
            random = 3;
        } else if (random < 99) {
            random = 4;
        } else {
            random = 5;
        }

        if (checkTier(random)) {
            return random;
        } else {
            if (checkTier(1)) {
                return 1;
            } else if (checkTier(2)) {
                return 2;
            } else if (checkTier(3)) {
                return 3;
            } else if (checkTier(4)) {
                return 4;
            }
            return 5;
        }
    }

    function distributeRewards(uint256 tier) internal returns (uint256 total) {
        if (minted == 0) {
            return 0;
        }
        uint256 rewards2;
        uint256 rewards3;
        uint256 rewards4;
        uint256 rewards5;
        total = (MINT_PRICE * 2500) / 10000;
        uint256 tier2Mint = tierMinted[2];
        uint256 tier3Mint = tierMinted[3];
        uint256 tier4Mint = tierMinted[4];
        uint256 tier5Mint = tierMinted[5];

        if (tier != 1) {
            uint256 tiersMinted = tier2Mint + tier3Mint + tier4Mint + tier5Mint;
            if (tiersMinted != 0) {
                uint256 reward = ((MINT_PRICE * 300) / 10000) / tiersMinted;
                total += (MINT_PRICE * 300) / 10000;

                rewards2 += reward;
                rewards3 += reward;
                rewards4 += reward;
                rewards5 += reward;
            }
        }

        if (tier >= 4) {
            uint256 tiersMinted = tier4Mint + tier5Mint;
            if (tiersMinted != 0) {
                uint256 reward = ((MINT_PRICE * 200) / 10000) / tiersMinted;
                rewards5 += reward;
                total += (MINT_PRICE * 200) / 10000;

                rewards4 += reward;
            }
        }

        if (tier == 5) {
            if (tier5Mint != 0) {
                uint256 reward = ((MINT_PRICE * 300) / 10000) / tier5Mint;
                total += (MINT_PRICE * 300) / 10000;

                rewards5 += reward;
            }
        }

        rewardsByTier[1] += ((MINT_PRICE * 2500) / 10000) / minted;
        rewardsByTier[2] += rewards2;
        rewardsByTier[3] += rewards3;
        rewardsByTier[4] += rewards4;
        rewardsByTier[5] += rewards5;
        totalRewards += total;
    }

    function claimSingleReward(uint256 tokenId) external {
        require(ownerOf(tokenId) == msg.sender, "NOT_TOKEN_OWNER");

        (uint256 amount, uint256 tierRewards) = getRewards(tokenId);

        detailsByTokenId[tokenId].lastClaim = tierRewards;

        require(amount > 0, "NO_REWARDS_AVAILABLE");

        payable(msg.sender).transfer(amount);

        emit rewardsClaimed(amount, block.timestamp, msg.sender);
    }

    function claimSingleReflection(uint256 tokenId) external {
        require(ownerOf(tokenId) == msg.sender, "NOT_TOKEN_OWNER");

        uint256 amount = getReflections(tokenId);

        require(amount > 0, "NO_REWARDS_AVAILABLE");

        detailsByTokenId[tokenId].lastReflection = tokenReflectionRewards;

        IERC20(earthToken).transfer(msg.sender, amount);

        emit reflectionsClaimed(amount, block.timestamp, msg.sender);
    }

    function claimReflections(uint256[] memory tokensIds) external {
        uint256 amount;

        for (uint256 i; i < tokensIds.length; i++) {
            require(ownerOf(tokensIds[i]) == msg.sender, "NOT_TOKEN_OWNER");

            amount += getReflections(tokensIds[i]);

            detailsByTokenId[tokensIds[i]]
                .lastReflection = tokenReflectionRewards;
        }

        require(amount > 0, "NO_REWARDS_AVAILABLE");

        IERC20(earthToken).transfer(msg.sender, amount);

        emit reflectionsClaimed(amount, block.timestamp, msg.sender);
    }

    function claimRewards(uint256[] memory tokensIds) external {
        uint256 owed;

        for (uint256 i; i < tokensIds.length; i++) {
            require(ownerOf(tokensIds[i]) == msg.sender, "NOT_TOKEN_OWNER");

            (uint256 amount, uint256 tierRewards) = getRewards(tokensIds[i]);

            owed += amount;

            detailsByTokenId[tokensIds[i]].lastClaim = tierRewards;
        }

        require(owed > 0, "NO_REWARDS_AVAILABLE");

        payable(msg.sender).transfer(owed);

        emit rewardsClaimed(owed, block.timestamp, msg.sender);
    }

    function getReflections(uint256 tokenId)
        public
        view
        returns (uint256 amount)
    {
        amount =
            tokenReflectionRewards -
            detailsByTokenId[tokenId].lastReflection;
    }

    function getRewards(uint256 tokenId)
        public
        view
        returns (uint256 amount, uint256 tierRewards)
    {
        uint256 tier = detailsByTokenId[tokenId].tier;
        tierRewards = getRewardsByTier(tier);

        amount = tierRewards - detailsByTokenId[tokenId].lastClaim;
    }

    function getRewardsByTier(uint256 tier)
        internal
        view
        returns (uint256 amount)
    {
        amount = rewardsByTier[1];

        if (tier != 1) {
            amount += rewardsByTier[tier];
        }

        return amount;
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

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721)
        returns (string memory)
    {
        require(_exists(tokenId), "Cannot query non-existent token");
        uint256 tier = detailsByTokenId[tokenId].tier;
        uint256 tierIndex = detailsByTokenId[tokenId].tierIndex;

        return
            string(abi.encodePacked(tierBaseUri[tier], tierIndex.toString()));
    }

    // function withdraw() external onlyOwner {
    //     payable(owner()).transfer(address(this).balance);
    // }

    function setUris(
        string memory _tier1,
        string memory _tier2,
        string memory _tier3,
        string memory _tier4,
        string memory _tier5
    ) external onlyOwner {
        tierBaseUri[1] = _tier1;
        tierBaseUri[2] = _tier2;
        tierBaseUri[3] = _tier3;
        tierBaseUri[4] = _tier4;
        tierBaseUri[5] = _tier5;
    }

    function setEarthToken(address _token) external onlyOwner {
        earthToken = _token;
    }

    function tokenReflections(uint256 amount) external {
        require(msg.sender == earthToken, "ONLY_$1EARTH_ALLOWED");
        if (totalSupply() == 0) {
            nonDeliveredReflections += amount;
        } else {
            tokenReflectionRewards +=
                (amount + nonDeliveredReflections) /
                totalSupply();
            nonDeliveredReflections = 0;
        }
    }
}
