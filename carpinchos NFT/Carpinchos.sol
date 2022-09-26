// SPDX-License-Identifier: GPL-3.0
// solhint-disable-next-line
pragma solidity 0.8.12;
import "./ERC721A.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract CryptoCarpinchos is ERC721A, Ownable {
    using Strings for uint256;

    uint256 public maxSupply = 10000;
    uint256 public mintPrice = 100 * 10**6; // USDT 6 decimals
    uint256 public mintMax = 5;
    uint256 public fundAmount = 0.05 ether;

    bool public open;

    string public baseURI;

    address public masterContract;
    address public secret;
    address public usdtAddress;
    address public treasuryWallet;

    IERC20 USDT;

    mapping(uint256 => uint256) public mintingDatetime;
    mapping(uint256 => uint256) public usdtAvailable;
    mapping(uint256 => uint256) public usdtLocked;
    mapping(string => bool) public isSecretMinted;

    event Received(address, uint256);

    constructor(address _usdtAddress, address _treasuryWallet)
        ERC721A("Crypto Carpinchos", "C.C.")
    {
        usdtAddress = _usdtAddress;
        treasuryWallet = _treasuryWallet;
        USDT = IERC20(_usdtAddress);
    }

    modifier onlyMasterContract() {
        require(
            masterContract == msg.sender,
            "Ownable: caller is not the Master Contract"
        );
        _;
    }

    modifier onlyAllowed() {
        require(
            owner() == msg.sender || secret == msg.sender,
            "Ownable: caller is not Allowed"
        );
        _;
    }

    receive() external payable {
        emit Received(msg.sender, msg.value);
    }

    function buy(uint256 amount) external {
        require(open, "Contract closed");
        require(maxSupply >= amount + _totalMinted(), "Supply limit");
        require(mintMax >= amount, "Too many tokens");

        USDT.transferFrom(msg.sender, address(this), amount * mintPrice);

        _buy(msg.sender, amount, mintPrice);
    }

    function buyWithCard(address user, uint256 amount, string memory _secret) external onlyAllowed {
        require(!isSecretMinted[_secret], "Secret is already minted");
        require(open, "Contract closed");
        if (amount > mintMax) {
            amount = mintMax;
        }       
        isSecretMinted[_secret] = true;

        require(maxSupply >= amount + _totalMinted(), "Supply limit");

        uint256 cardMintPrice = (mintPrice * 90) / 100;

        checkFunds(user);

        _buy(user, amount, cardMintPrice);
    }

    function refund(uint256 tokenId, uint256 amount) external {
        uint256 balance = usdtAvailable[tokenId] - usdtLocked[tokenId];
        require(balance >= amount, "Not enough USDT in your token");
        require(ownerOf(tokenId) == msg.sender, "Not the token owner");

        usdtAvailable[tokenId] -= amount;

        if (balance - amount == 0) {
            _burn(tokenId, false);
        }

        USDT.transfer(msg.sender, amount);
    }

    function lockUsdt(uint256 tokenId, uint256 amount)
        external
        onlyMasterContract
    {
        usdtLocked[tokenId] = amount;
    }

    function finishFight(
        uint256 tokenId,
        uint256 amount,
        bool wins
    ) external onlyMasterContract {
        if (wins) {
            usdtAvailable[tokenId] += amount;
        } else {
            usdtAvailable[tokenId] -= amount;
        }

        usdtLocked[tokenId] = 0;
    }

    function payFee() external onlyMasterContract {
        USDT.transfer(treasuryWallet, 1 * 10**6);
    }

    function checkFunds(address user) internal {
        uint256 currentBalance = address(user).balance;
        if (currentBalance == 0) {
            (bool success, ) = user.call{value: fundAmount}("");
        }
    }

    function _buy(
        address to,
        uint256 quantity,
        uint256 price
    ) internal {
        uint256 _totalTokens = _totalMinted();
        _safeMint(to, quantity);
        for (uint256 i = _totalTokens; i < _totalTokens + quantity; i++) {
            mintingDatetime[i] = block.timestamp;
            usdtAvailable[i] = price;
        }
    }

    function setSecret(address _secret) external onlyOwner {
        require(_secret != address(0), "cannot set zero address");
        secret = _secret;
    }

    function setOpen(bool _open) external onlyOwner {
        open = _open;
    }

    function setMultiple(
        uint256 _mintPrice,
        uint256 _mintMax,
        uint256 _fundAmount,
        string memory _newBaseURI,
        address _treasuryWallet
    ) external onlyOwner {
        mintPrice = _mintPrice;
        mintMax = _mintMax;
        fundAmount = _fundAmount;
        baseURI = _newBaseURI;
        treasuryWallet = _treasuryWallet;
    }

    function setMasterContract(address newMasterContract) external onlyOwner {
        require(newMasterContract != address(0), "cannot set zero address");
        masterContract = newMasterContract;
    }

    function usdtNotLocked(uint256 tokenId) external view returns (uint256) {
        return usdtAvailable[tokenId] - usdtLocked[tokenId];
    }

    function minted() external view returns (uint256) {
        return _totalMinted();
    }

    function tokenExist(uint256 id) external view returns (bool) {
        return _exists(id);
    }

    function tokenURI(uint256 tokenId)
        public
        view
        virtual
        override
        returns (string memory)
    {
        require(
            _exists(tokenId),
            "ERC721Metadata: URI query for nonexistent token"
        );

        return string(abi.encodePacked(baseURI, tokenId.toString()));
    }

    function walletOfOwner(address _owner)
        external
        view
        returns (uint256[] memory tokensId)
    {
        uint256 tokenCount = balanceOf(_owner);

        tokensId = new uint256[](tokenCount);

        for (uint256 i; i < tokenCount; i++) {
            tokensId[i] = ERC721A.tokenOfOwnerByIndex(_owner, i);
        }
    }
}
