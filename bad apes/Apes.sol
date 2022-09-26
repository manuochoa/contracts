// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/cryptography/ECDSA.sol";
import "./Gold.sol";
import "./IMine.sol";
import "./IPancakeRouter.sol";

contract Apes is ERC721Enumerable, Ownable {
    using ECDSA for bytes32;
    using Strings for uint256;

    uint256 public constant MINT_PRICE = 0.69420 ether;
    uint256 public immutable MAX_TOKENS;
    uint256 public PAID_TOKENS;
    uint256 public minted;
    uint256 public sigmas;
    uint256 public alphas;
    uint256 public zetas;
    uint256 public betas;

    string public minersBaseURI;
    string public alphaBaseURI;
    string public sigmaBaseURI;
    string public zetaBaseURI;
    string public betaBaseURI;

    address private _signerAddress;
    address public BadApeToken = 0xC4F5424eF52499fa496a07f3fE9DaAb88553D4C3;
    address public WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;

    bool public _paused;

    IPancakeRouter01 public pancakeRouter;
    IMine public mine;
    Gold public gold;

    mapping(uint256 => MinerBadApe) public tokenInfo;
    mapping(uint256 => uint256) public alphaId;
    mapping(uint256 => uint256) public sigmaId;
    mapping(uint256 => uint256) public zetaId;
    mapping(uint256 => uint256) public betaId;
    mapping(bytes32 => bool) private hashClaimed;

    event tokenStoled(address BadApe, uint256 tokenId);
    event tokenMinted(address Minter, uint256 tokenId, uint256 timestamp);

    struct MinerBadApe {
        bool isMiner;
        uint256 mainMaterial;
        uint256 strengthIndex;
        uint256 intelligenceIndex;
    }

    constructor(
        address _gold,
        address _router,
        uint256 _maxTokens,
        address _newSigner
    ) ERC721("Land of the Apes", "$BAG") {
        gold = Gold(_gold);
        pancakeRouter = IPancakeRouter01(_router);
        MAX_TOKENS = _maxTokens;
        PAID_TOKENS = _maxTokens / 5;
        _signerAddress = _newSigner;
    }

    function regularMint(
        bool stake,
        bytes32 _hash,
        bytes memory _signature
    ) external payable whenNotPaused {
        if (totalSupply() <= PAID_TOKENS) {
            require(MINT_PRICE == msg.value, "INVALID_ETH_AMOUNT");
        }

        mint(stake, _hash, _signature);
    }

    function mintWithBAYCtoken(
        bool stake,
        bytes32 _hash,
        bytes memory _signature
    ) external whenNotPaused {
        if (totalSupply() <= PAID_TOKENS) {
            uint256 BAYCtoPay = BAYCcost();

            require(
                IERC20(BadApeToken).transferFrom(
                    msg.sender,
                    address(this),
                    BAYCtoPay
                ),
                "BAYC transfer fail"
            );
        }

        mint(stake, _hash, _signature);
    }

    function mint(
        bool stake,
        bytes32 _hash,
        bytes memory _signature
    ) internal {
        require(matchAddresSigner(_hash, _signature), "NO_DIRECT_MINT");
        require(!hashClaimed[_hash], "HASH_USED");
        require(totalSupply() <= MAX_TOKENS, "REACH_MAX_SUPPLY");

        address sender = msg.sender;

        if (totalSupply() <= 1000) {
            require(
                balanceOf(sender) + mine.getTokensForOwner(sender).length < 5,
                "5_APES_LIMIT_ACTIVE"
            );
        }

        hashClaimed[_hash] = true;

        uint256 tokenId = totalSupply() + 1;
        uint256 seed = uint256(_hash);
        tokenInfo[tokenId] = selectTraits(seed, tokenId);

        address recipient = selectRecipient(seed);

        if (!stake || recipient != sender) {
            _safeMint(recipient, tokenId);
            if (recipient != sender) {
                emit tokenStoled(recipient, tokenId);
            }
        } else {
            _safeMint(address(mine), tokenId);
        }

        emit tokenMinted(sender, tokenId, block.timestamp);

        uint256 totalGoldCost = mintCost(tokenId);

        if (totalGoldCost > 0) gold.burn(sender, totalGoldCost);
        if (stake) {
            uint256[] memory tokenIds = new uint256[](1);
            tokenIds[0] = tokenId;
            mine.addManyToMineAndPack(sender, tokenIds);
        }
    }

    function selectTraits(uint256 seed, uint256 tokenId)
        internal
        returns (MinerBadApe memory t)
    {
        t.isMiner = random(seed) % 10 != 0;
        t.strengthIndex = random(seed) % 4;
        t.intelligenceIndex = random(seed + t.strengthIndex) % 3;
        t.mainMaterial = random(seed + t.intelligenceIndex) % 5;

        if (!t.isMiner) {
            if (t.strengthIndex == 0) {
                sigmaId[tokenId] = sigmas;
                sigmas++;
            }
            if (t.strengthIndex == 1) {
                alphaId[tokenId] = alphas;
                alphas++;
            }
            if (t.strengthIndex == 2) {
                zetaId[tokenId] = zetas;
                zetas++;
            }
            if (t.strengthIndex == 3) {
                betaId[tokenId] = betas;
                betas++;
            }
        }
    }

    function mintCost(uint256 tokenId) public view returns (uint256) {
        if (tokenId <= PAID_TOKENS) return 0;
        if (tokenId <= (MAX_TOKENS * 2) / 5) return 20000 ether;
        if (tokenId <= (MAX_TOKENS * 4) / 5) return 40000 ether;
        return 80000 ether;
    }

    function isMiner(uint256 tokenId) public view returns (bool) {
        MinerBadApe memory ape = tokenInfo[tokenId];
        return ape.isMiner;
    }

    function BAYCcost() public view returns (uint256) {
        address[] memory path = new address[](2);
        path[0] = BadApeToken;
        path[1] = WBNB;
        uint256[] memory amounts = pancakeRouter.getAmountsIn(
            0.4165 ether,
            path
        );
        return amounts[0];
    }

    function selectRecipient(uint256 seed) internal view returns (address) {
        if (totalSupply() <= PAID_TOKENS || (seed % 10) != 0)
            return _msgSender();
        address thief = mine.randomBadApeOwner(seed);
        if (thief == address(0x0)) return _msgSender();
        return thief;
    }

    function matchAddresSigner(bytes32 hash, bytes memory signature)
        internal
        view
        returns (bool)
    {
        return _signerAddress == hash.recover(signature);
    }

    function random(uint256 seed) internal view returns (uint256) {
        return
            uint256(
                keccak256(
                    abi.encodePacked(
                        block.timestamp,
                        gasleft(),
                        msg.sender,
                        seed
                    )
                )
            );
    }

    function getTokenInfo(uint256 tokenId)
        external
        view
        returns (MinerBadApe memory)
    {
        return tokenInfo[tokenId];
    }

    function setPaused() external onlyOwner {
        _paused = !_paused;
    }

    modifier whenNotPaused() {
        require(!_paused, "PAUSED");
        _;
    }

    function setMine(address _mine) external onlyOwner {
        mine = IMine(_mine);
    }

    function setSigner(address _newSigner) external onlyOwner {
        _signerAddress = _newSigner;
    }

    function setURIS(
        string memory _minersBaseURI,
        string memory _alphaBaseURI,
        string memory _sigmaBaseURI,
        string memory _zetaBaseURI,
        string memory _betaBaseURI
    ) external onlyOwner {
        minersBaseURI = _minersBaseURI;
        alphaBaseURI = _alphaBaseURI;
        sigmaBaseURI = _sigmaBaseURI;
        zetaBaseURI = _zetaBaseURI;
        betaBaseURI = _betaBaseURI;
    }

    function withdraw() external onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }

    function withdrawBAYC() external onlyOwner {
        uint256 BAYCtoWithdraw = IERC20(BadApeToken).balanceOf(address(this));
        require(
            IERC20(BadApeToken).transfer(msg.sender, BAYCtoWithdraw),
            "BAYC transfer fail"
        );
    }

    function badApes() external view returns (uint256) {
        return sigmas + alphas + zetas + betas;
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721)
        returns (string memory)
    {
        require(_exists(tokenId), "Cannot query non-existent token");
        uint256 strength = tokenInfo[tokenId].strengthIndex;

        if (isMiner(tokenId)) {
            return string(abi.encodePacked(minersBaseURI, tokenId.toString()));
        } else if (strength == 0) {
            return
                string(
                    abi.encodePacked(sigmaBaseURI, sigmaId[tokenId].toString())
                );
        } else if (strength == 1) {
            return
                string(
                    abi.encodePacked(alphaBaseURI, alphaId[tokenId].toString())
                );
        } else if (strength == 2) {
            return
                string(
                    abi.encodePacked(zetaBaseURI, zetaId[tokenId].toString())
                );
        } else {
            return
                string(
                    abi.encodePacked(betaBaseURI, betaId[tokenId].toString())
                );
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
}
