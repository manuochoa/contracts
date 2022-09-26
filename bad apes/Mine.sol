// SPDX-License-Identifier: MIT LICENSE

pragma solidity ^0.8.0;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC721/IERC721Receiver.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/security/Pausable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/security/ReentrancyGuard.sol";
import "./Apes.sol";
import "./Gold.sol";

contract Mine is Ownable, IERC721Receiver, Pausable, ReentrancyGuard {
    uint8 public constant MAX_ALPHA = 8;

    struct Stake {
        uint256 tokenId;
        uint256 value;
        address owner;
    }

    event TokenStaked(address owner, uint256[] tokenId);
    event ApeClaimed(uint256 tokenId, uint256 earned, bool unstaked);
    event BadApeClaimed(uint256 tokenId, uint256 earned, bool unstaked);
    event goldStolen(uint256 amount);

    Apes apes;
    Gold gold;

    mapping(uint256 => Stake) public mine;
    mapping(uint256 => Stake[]) public pack;
    mapping(uint256 => uint256) public packIndices;
    mapping(address => uint256[]) public ownerTokens;
    mapping(uint256 => uint256) public ownerTokensIndices;

    uint256 public totalAlphaStaked = 0;
    uint256 public unaccountedRewards = 0;
    uint256 public goldPerAlpha = 0;
    uint256 public constant DAILY_GOLD_RATE = 10000 ether;
    uint256 public constant MINIMUM_TO_EXIT = 2 days;
    uint256 public constant GOLD_CLAIM_TAX_PERCENTAGE = 20;
    uint256 public constant MAXIMUM_GLOBAL_Gold = 2400000000 ether;
    uint256 public totalGoldEarned;
    uint256 public totalApesMining;
    uint256 public totalBadApes;
    uint256 public lastClaimTimestamp;

    bool public rescueEnabled = false;

    constructor(address _ape, address _gold) {
        apes = Apes(_ape);
        gold = Gold(_gold);
    }

    function addManyToMineAndPack(address account, uint256[] calldata tokenIds)
        external
        nonReentrant
        whenNotPaused
    {
        require(
            account == _msgSender() || _msgSender() == address(apes),
            "DONT GIVE YOUR TOKENS AWAY"
        );
        for (uint256 i = 0; i < tokenIds.length; i++) {
            ownerTokensIndices[tokenIds[i]] = ownerTokens[account].length;
            ownerTokens[account].push(tokenIds[i]);

            if (_msgSender() != address(apes)) {
                require(
                    apes.ownerOf(tokenIds[i]) == _msgSender(),
                    "AINT YO TOKEN"
                );
                apes.transferFrom(_msgSender(), address(this), tokenIds[i]);
            } else if (tokenIds[i] == 0) {
                continue;
            }

            if (isMiner(tokenIds[i])) _addApeToMine(account, tokenIds[i]);
            else _addBadApeToPack(account, tokenIds[i]);
        }
        emit TokenStaked(account, tokenIds);
    }

    function _addApeToMine(address account, uint256 tokenId)
        internal
        whenNotPaused
        _updateEarnings
    {
        mine[tokenId] = Stake({
            owner: account,
            tokenId: tokenId,
            value: block.timestamp
        });
        totalApesMining += 1;
    }

    function _addBadApeToPack(address account, uint256 tokenId) internal {
        uint256 alpha = _alphaForBadApe(tokenId);
        totalAlphaStaked += alpha;
        packIndices[tokenId] = pack[alpha].length;
        pack[alpha].push(
            Stake({owner: account, tokenId: tokenId, value: goldPerAlpha})
        );
        totalBadApes += 1;
    }

    function claimManyFromMineAndPack(uint256[] calldata tokenIds, bool unstake)
        external
        nonReentrant
        whenNotPaused
        _updateEarnings
    {
        uint256 owed = 0;
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            if (isMiner(tokenId)) {
                owed += _claimApeFromMine(tokenId, unstake);
            } else {
                owed += _claimBadApeFromPack(tokenId, unstake);
            }
            if (unstake) {
                uint256 lastTokenId = ownerTokens[_msgSender()][
                    ownerTokens[_msgSender()].length - 1
                ];
                ownerTokens[_msgSender()][
                    ownerTokensIndices[tokenId]
                ] = lastTokenId;
                ownerTokensIndices[lastTokenId] = ownerTokensIndices[tokenId];
                ownerTokens[_msgSender()].pop();
                delete ownerTokensIndices[tokenId];
            }
        }
        if (owed == 0) return;
        gold.mint(_msgSender(), owed);
    }

    function _claimApeFromMine(uint256 tokenId, bool unstake)
        internal
        returns (uint256 owed)
    {
        Stake memory stake = mine[tokenId];
        require(stake.owner == _msgSender(), "SWIPER, NO SWIPING");
        require(
            !(unstake && block.timestamp - stake.value < MINIMUM_TO_EXIT),
            "NEED TWO DAY'S $GLD FOR THE JOURNEY"
        );
        if (totalGoldEarned < MAXIMUM_GLOBAL_Gold) {
            owed = ((block.timestamp - stake.value) * DAILY_GOLD_RATE) / 1 days;
        } else if (stake.value > lastClaimTimestamp) {
            owed = 0;
        } else {
            owed =
                ((lastClaimTimestamp - stake.value) * DAILY_GOLD_RATE) /
                1 days;
        }
        if (unstake) {
            if (random(tokenId) % 1 == 1) {
                _payBadApeTax(owed);
                emit goldStolen(owed);
                owed = 0;
            }
            delete mine[tokenId];
            totalApesMining -= 1;
            apes.safeTransferFrom(address(this), _msgSender(), tokenId, "");
        } else {
            _payBadApeTax((owed * GOLD_CLAIM_TAX_PERCENTAGE) / 100);
            owed = (owed * (100 - GOLD_CLAIM_TAX_PERCENTAGE)) / 100;
            mine[tokenId] = Stake({
                owner: _msgSender(),
                tokenId: tokenId,
                value: block.timestamp
            });
        }
        emit ApeClaimed(tokenId, owed, unstake);
    }

    function _claimBadApeFromPack(uint256 tokenId, bool unstake)
        internal
        returns (uint256 owed)
    {
        require(
            apes.ownerOf(tokenId) == address(this),
            "AINT A PART OF THE PACK"
        );
        uint256 alpha = _alphaForBadApe(tokenId);
        Stake memory stake = pack[alpha][packIndices[tokenId]];
        require(stake.owner == _msgSender(), "SWIPER, NO SWIPING");
        owed = (alpha) * (goldPerAlpha - stake.value);
        if (unstake) {
            totalAlphaStaked -= alpha;
            apes.safeTransferFrom(address(this), _msgSender(), tokenId, "");
            Stake memory lastStake = pack[alpha][pack[alpha].length - 1];
            pack[alpha][packIndices[tokenId]] = lastStake;
            packIndices[lastStake.tokenId] = packIndices[tokenId];
            pack[alpha].pop();
            delete packIndices[tokenId];
            totalBadApes -= 1;
        } else {
            pack[alpha][packIndices[tokenId]] = Stake({
                owner: _msgSender(),
                tokenId: tokenId,
                value: goldPerAlpha
            });
        }
        emit BadApeClaimed(tokenId, owed, unstake);
    }

    function rescue(uint256[] calldata tokenIds) external {
        require(rescueEnabled, "RESCUE DISABLED");
        uint256 tokenId;
        Stake memory stake;
        Stake memory lastStake;
        uint256 alpha;
        for (uint256 i = 0; i < tokenIds.length; i++) {
            tokenId = tokenIds[i];
            if (isMiner(tokenId)) {
                stake = mine[tokenId];
                require(stake.owner == _msgSender(), "SWIPER, NO SWIPING");
                apes.safeTransferFrom(address(this), _msgSender(), tokenId, "");
                delete mine[tokenId];
                totalApesMining -= 1;
                emit ApeClaimed(tokenId, 0, true);
            } else {
                alpha = _alphaForBadApe(tokenId);
                stake = pack[alpha][packIndices[tokenId]];
                require(stake.owner == _msgSender(), "SWIPER, NO SWIPING");
                totalAlphaStaked -= alpha;
                apes.safeTransferFrom(address(this), _msgSender(), tokenId, "");
                lastStake = pack[alpha][pack[alpha].length - 1];
                pack[alpha][packIndices[tokenId]] = lastStake;
                packIndices[lastStake.tokenId] = packIndices[tokenId];
                pack[alpha].pop();
                delete packIndices[tokenId];
                emit BadApeClaimed(tokenId, 0, true);
            }
        }
    }

    function _payBadApeTax(uint256 amount) internal {
        if (totalAlphaStaked == 0) {
            unaccountedRewards += amount;
            return;
        }

        goldPerAlpha += (amount + unaccountedRewards) / totalAlphaStaked;
        unaccountedRewards = 0;
    }

    modifier _updateEarnings() {
        if (totalGoldEarned < MAXIMUM_GLOBAL_Gold) {
            totalGoldEarned +=
                ((block.timestamp - lastClaimTimestamp) *
                    totalApesMining *
                    DAILY_GOLD_RATE) /
                1 days;
            lastClaimTimestamp = block.timestamp;
        }
        _;
    }

    function setRescueEnabled(bool _enabled) external onlyOwner {
        rescueEnabled = _enabled;
    }

    function setPaused(bool _paused) external onlyOwner {
        if (_paused) _pause();
        else _unpause();
    }

    function isMiner(uint256 tokenId) public view returns (bool) {
        return apes.getTokenInfo(tokenId).isMiner;
    }

    function _alphaForBadApe(uint256 tokenId) internal view returns (uint256) {
        return MAX_ALPHA - apes.getTokenInfo(tokenId).strengthIndex;
    }

    function randomBadApeOwner(uint256 seed) external view returns (address) {
        if (totalAlphaStaked == 0) return address(0x0);
        uint256 bucket = seed % totalAlphaStaked;
        uint256 cumulative;

        for (uint256 i = MAX_ALPHA - 3; i <= MAX_ALPHA; i++) {
            cumulative += pack[i].length * i;

            if (bucket >= cumulative) continue;

            return pack[i][seed % pack[i].length].owner;
        }
        return address(0x0);
    }

    function random(uint256 seed) internal view returns (uint256) {
        return
            uint256(
                keccak256(
                    abi.encodePacked(
                        tx.origin,
                        blockhash(block.number - 1),
                        block.timestamp,
                        seed
                    )
                )
            );
    }

    function getTokensForOwner(address owner)
        external
        view
        returns (uint256[] memory)
    {
        return ownerTokens[owner];
    }

    function onERC721Received(
        address,
        address from,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        require(from == address(0x0), "Cannot send tokens to Mine directly");
        return IERC721Receiver.onERC721Received.selector;
    }
}
