// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

interface IToken {
    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external returns (bool);

    function transfer(address to, uint256 value) external returns (bool);

    function balanceOf(address who) external view returns (uint256);

    function allowance(address owner, address spender)
        external
        view
        returns (uint256);

    function approve(address spender, uint256 value) external returns (bool);
}

interface IHuchaVault {
    function withdraw(uint256 tokenAmount) external;
}

contract HuchaFaucet is OwnableUpgradeable {
    using SafeMath for uint256;

    struct User {
        //Referral Info
        address upline;
        uint256 referrals;
        uint256 total_structure;
        //Long-term Referral Accounting
        uint256 direct_bonus;
        uint256 match_bonus;
        //Deposit Accounting
        uint256 deposits;
        uint256 deposit_time;
        //Payout and Roll Accounting
        uint256 payouts;
        uint256 rolls;
        //Upline Round Robin tracking
        uint256 ref_claim_pos;
        uint256 accumulatedDiv;
    }

    struct Airdrop {
        //Airdrop tracking
        uint256 airdrops;
        uint256 airdrops_received;
        uint256 last_airdrop;
    }

    struct Custody {
        address manager;
        address beneficiary;
        uint256 last_heartbeat;
        uint256 last_checkin;
        uint256 heartbeat_interval;
    }

    address public huchaVaultAddress;

    IToken private huchaToken;
    IHuchaVault private huchaVault;

    mapping(address => User) public users;
    mapping(address => Airdrop) public airdrops;
    mapping(address => Custody) public custody;

    uint256 public CompoundTax;
    uint256 public ExitTax;
    uint256 public BurnTax;
    uint256 public withdrawTax;
    uint256 public entryTax;

    uint256 private payoutRate;
    uint256 private ref_depth;
    uint256 private ref_bonus;
    uint256 public unlock_date;
    uint256 public lock_date;
    uint256 public unlock_period = 1 days;
    uint256 public lock_period = 25 days;

    uint256 private minimumInitial;
    uint256 private minimumAmount;

    uint256 public deposit_bracket_size; // @BB 5% increase whale tax per 10000 tokens... 10 below cuts it at 50% since 5 * 10
    uint256 public max_payout_cap; 
    uint256 private deposit_bracket_max; // sustainability fee is (bracket * 5)

    uint256[] public ref_balances;

    uint256 public total_airdrops;
    uint256 public total_users;
    uint256 public total_deposited;
    uint256 public total_withdraw;
    uint256 public total_bnb;
    uint256 public total_txs;

    uint256 public constant MAX_UINT = 2**256 - 1;

    event Upline(address indexed addr, address indexed upline);
    event NewDeposit(address indexed addr, uint256 amount);
    event Leaderboard(
        address indexed addr,
        uint256 referrals,
        uint256 total_deposits,
        uint256 total_payouts,
        uint256 total_structure
    );
    event DirectPayout(
        address indexed addr,
        address indexed from,
        uint256 amount
    );
    event MatchPayout(
        address indexed addr,
        address indexed from,
        uint256 amount
    );
    event BalanceTransfer(
        address indexed _src,
        address indexed _dest,
        uint256 _deposits,
        uint256 _payouts
    );
    event Withdraw(address indexed addr, uint256 amount);
    event LimitReached(address indexed addr, uint256 amount);
    event NewAirdrop(
        address indexed from,
        address indexed to,
        uint256 amount,
        uint256 timestamp
    );
    event ManagerUpdate(
        address indexed addr,
        address indexed manager,
        uint256 timestamp
    );
    event BeneficiaryUpdate(address indexed addr, address indexed beneficiary);
    event HeartBeatIntervalUpdate(address indexed addr, uint256 interval);
    event HeartBeat(address indexed addr, uint256 timestamp);
    event Checkin(address indexed addr, uint256 timestamp);

    /* ========== INITIALIZER ========== */

    function initialize() external initializer {
        __Ownable_init();
    }

    function initialize(
        address _huchaTokenAddress,
        address _vaultAddress
    ) external initializer {
        __Ownable_init();

        total_users = 1;
        deposit_bracket_size = 10000e18; // @BB 5% increase whale tax per 10000 tokens... 10 below cuts it at 50% since 5 * 10
        max_payout_cap = 100000e18; 
        minimumInitial = 1e18;
        minimumAmount = 1e18;

        payoutRate = 2;
        ref_depth = 15;
        ref_bonus = 10;
        deposit_bracket_max = 10; // sustainability fee is (bracket * 5)
        unlock_date = block.timestamp + lock_period;
        lock_date = block.timestamp + lock_period + unlock_period;

        CompoundTax = 0;
        ExitTax = 0;
        BurnTax = 0;
        withdrawTax = 10;
        entryTax = 10;

        huchaToken = IToken(_huchaTokenAddress);
        //IHuchaVault
        huchaVaultAddress = _vaultAddress;
        huchaVault = IHuchaVault(_vaultAddress);

        //Referral Balances
        ref_balances.push(2e8);
        ref_balances.push(3e8);
        ref_balances.push(5e8);
        ref_balances.push(8e8);
        ref_balances.push(13e8);
        ref_balances.push(21e8);
        ref_balances.push(34e8);
        ref_balances.push(55e8);
        ref_balances.push(89e8);
        ref_balances.push(144e8);
        ref_balances.push(233e8);
        ref_balances.push(377e8);
        ref_balances.push(610e8);
        ref_balances.push(987e8);
        ref_balances.push(1597e8);
    }

    //@dev Default payable is empty since Faucet executes trades and recieves BNB
    receive() external payable {
        //Do nothing, BNB will be sent to contract when selling tokens
    }

    /****** Administrative Functions *******/
    function updatePayoutRate(uint256 _newPayoutRate) public onlyOwner {
        payoutRate = _newPayoutRate;
    }

    function updateLockPeriods(uint256 _newUnlock_period, uint256 _newLock_period) public onlyOwner {
        unlock_period = _newUnlock_period;
        lock_period = _newLock_period;
    }

    function setLockDate(uint256 _newUnlock_date, uint256 _newLock_date) public onlyOwner {
        unlock_date = _newUnlock_date;
        lock_date = _newLock_date;
    }

    function updateRefDepth(uint256 _newRefDepth) public onlyOwner {
        ref_depth = _newRefDepth;
    }

    function updateRefBonus(uint256 _newRefBonus) public onlyOwner {
        ref_bonus = _newRefBonus;
    }

    function updateInitialDeposit(uint256 _newInitialDeposit) public onlyOwner {
        minimumInitial = _newInitialDeposit;
    }

    function updateCompoundTax(uint256 _newCompoundTax) public onlyOwner {
        require(_newCompoundTax >= 0 && _newCompoundTax <= 20);
        CompoundTax = _newCompoundTax;
    }

    function updateExitTax(uint256 _newExitTax, uint256 _BurnTax, uint256 _withdrawTax, uint256 _entryTax)
        public
        onlyOwner
    {
        require(_newExitTax >= 0 && _newExitTax <= 20);
        ExitTax = _newExitTax;
        BurnTax = _BurnTax;
        withdrawTax = _withdrawTax;
        entryTax = _entryTax;
    }

    function updateDepositBracketSize(uint256 _newBracketSize)
        public
        onlyOwner
    {
        deposit_bracket_size = _newBracketSize;
    }

    function updateMaxPayoutCap(uint256 _newPayoutCap) public onlyOwner {
        max_payout_cap = _newPayoutCap;
    }

    function updateHoldRequirements(uint256[] memory _newRefBalances)
        public
        onlyOwner
    {
        require(_newRefBalances.length == ref_depth);
        delete ref_balances;
        for (uint8 i = 0; i < ref_depth; i++) {
            ref_balances.push(_newRefBalances[i]);
        }
    }

    /********** User Fuctions **************************************************/
    function checkin() public {
        address _addr = msg.sender;
        custody[_addr].last_checkin = block.timestamp;
        updateLockTime();
        emit Checkin(_addr, custody[_addr].last_checkin);
    }

    //@dev Deposit specified amount supplying an upline referral
    function deposit(address _upline, uint256 _amount) external {
        address _addr = msg.sender;

        uint256 _total_amount = _amount;

        checkin();

        require(_total_amount >= minimumAmount, "Minimum deposit");

        //If fresh account require a minimal amount
        if (users[_addr].deposits == 0) {
            require(_total_amount >= minimumInitial, "Initial deposit too low");

            _total_amount -= _amount.mul(entryTax).div(100);

            _setUpline(_addr, _upline);

            _refPayout(_addr, _amount, ref_bonus);
        }

        require(
            huchaToken.transferFrom(_addr, address(huchaVaultAddress), _amount),
            "hucha token transfer failed"
        );

        _deposit(_addr, _total_amount);       

        emit Leaderboard(
            _addr,
            users[_addr].referrals,
            users[_addr].deposits,
            users[_addr].payouts,
            users[_addr].total_structure
        );
        total_txs++;
    }

    //@dev Claim, transfer, withdraw from vault
    function claim() external {
        //Checkin for custody management.  If a user rolls for themselves they are active
        checkin();

        address _addr = msg.sender;

        _claim_out(_addr);
    }

    //@dev Claim and deposit;
    function roll() public {
        //Checkin for custody management.  If a user rolls for themselves they are active
        checkin();

        address _addr = msg.sender;

        _roll(_addr);
    }

    function withdraw (uint256 _amount) external {
        address _addr = msg.sender;
        checkin();
        require(users[_addr].deposits >= _amount, "Not enough deposit");
        require(canWithdraw(), "Withdraw not ready");

        users[_addr].deposits -= _amount;
        total_deposited -= _amount;

        uint256 withdrawFee = _amount.mul(withdrawTax).div(100);
        uint256 withdrawAmount = _amount - withdrawFee;

        uint256 vaultBalance = huchaToken.balanceOf(huchaVaultAddress);
        require(vaultBalance >= withdrawAmount, "Vault run out of funds");

        huchaVault.withdraw(withdrawAmount);

        require(huchaToken.transfer(address(msg.sender), withdrawAmount));
    }

    function changeUpline(address _upline) public {
        require(_upline != address(0), "can't set null address as referral");
        require(
            users[msg.sender].upline != _upline,
            "This address is already your referral"
        );

        address oldUpline = users[msg.sender].upline;
        users[msg.sender].upline = _upline;
        users[_upline].referrals++;
        users[oldUpline].referrals--;

        emit Upline(msg.sender, _upline);

        total_users++;

        for (uint8 i = 0; i < ref_depth; i++) {
            if (_upline == address(0)) break;

            users[_upline].total_structure++;

            _upline = users[_upline].upline;
        }
    }

    /********** Internal Fuctions **************************************************/

    function canWithdraw () internal view returns (bool){
        if(unlock_date < lock_date){
            return block.timestamp > unlock_date && block.timestamp < lock_date; 
        } else if (unlock_date > lock_date){
            return block.timestamp < lock_date;
        } else {
            return false;
        }
    }

    function updateLockTime () public {
        if (block.timestamp > unlock_date){
            uint256 newUnlockDate = lock_date + lock_period;
            unlock_date = newUnlockDate;
        } 
        if(block.timestamp > lock_date){
            lock_date = unlock_date + unlock_period;
        }
    }

    //@dev Add direct referral and update team structure of upline
    function _setUpline(address _addr, address _upline) internal {
        /*
        1) User must not have existing up-line
        2) Up-line argument must not be equal to senders own address
        3) Senders address must not be equal to the owner
        4) Up-lined user must have a existing deposit
        */
        if (
            users[_addr].upline == address(0) &&
            _upline != _addr &&
            _addr != owner() &&
            (users[_upline].deposit_time > 0 || _upline == owner())
        ) {
            users[_addr].upline = _upline;
            users[_upline].referrals++;

            emit Upline(_addr, _upline);

            total_users++;

            for (uint8 i = 0; i < ref_depth; i++) {
                if (_upline == address(0)) break;

                users[_upline].total_structure++;

                _upline = users[_upline].upline;
            }
        }
    }

    function _deposit(address _addr, uint256 _amount) internal {
        require(
            users[_addr].upline != address(0) || _addr == owner(),
            "Referral address not valid"
        );

        users[_addr].deposits += _amount;
        users[_addr].deposit_time = block.timestamp;
       
        total_deposited += _amount;

        emit NewDeposit(_addr, _amount);
    }

    function _refPayout(
        address _addr,
        uint256 _amount,
        uint256 _refBonus
    ) internal {
        address _up = users[_addr].upline;
        uint256 _bonus = (_amount * _refBonus) / 100;

        (uint256 gross_payout, , , ) = payoutOf(_up);
        users[_up].accumulatedDiv = gross_payout;
        users[_up].deposits += _bonus;
        users[_up].deposit_time = block.timestamp;

        users[_up].match_bonus += _bonus;

        emit NewDeposit(_up, _bonus);
        emit MatchPayout(_up, _addr, _bonus);
    }

    //@dev General purpose heartbeat in the system used for custody/management planning
    function _heart(address _addr) internal {
        custody[_addr].last_heartbeat = block.timestamp;
        emit HeartBeat(_addr, custody[_addr].last_heartbeat);
    }

    //@dev Claim and deposit;
    function _roll(address _addr) internal {
        uint256 to_payout = _claim(_addr, false);

        uint256 payout_taxed = to_payout
            .mul(SafeMath.sub(100, CompoundTax))
            .div(100); 
      
        _deposit(_addr, payout_taxed);

        users[_addr].rolls += payout_taxed;

        emit Leaderboard(
            _addr,
            users[_addr].referrals,
            users[_addr].deposits,
            users[_addr].payouts,
            users[_addr].total_structure
        );
        total_txs++;
    }

    //@dev Claim, transfer, and topoff
    function _claim_out(address _addr) internal {
        uint256 to_payout = _claim(_addr, true);

        uint256 vaultBalance = huchaToken.balanceOf(huchaVaultAddress);
        require(vaultBalance >= to_payout, "Vault run out of funds");

        uint256 realizedPayout = to_payout.mul(SafeMath.sub(100, ExitTax)).div(
            100
        ); 
        uint256 burnAmount = to_payout.mul(BurnTax).div(100);

        huchaVault.withdraw(realizedPayout + burnAmount);

        require(huchaToken.transfer(address(msg.sender), realizedPayout));
        require(
            huchaToken.transfer(
                0x000000000000000000000000000000000000dEaD,
                burnAmount
            )
        );

        emit Leaderboard(
            _addr,
            users[_addr].referrals,
            users[_addr].deposits,
            users[_addr].payouts,
            users[_addr].total_structure
        );
        total_txs++;
    }

    //@dev Claim current payouts
    function _claim(address _addr, bool isClaimedOut)
        internal
        returns (uint256)
    {
        (
            uint256 _gross_payout,
            uint256 _max_payout,
            uint256 _to_payout,

        ) = payoutOf(_addr);
        require(users[_addr].payouts < _max_payout, "Full payouts");

        // Deposit payout
        if (_to_payout > 0) {
            // payout remaining allowable divs if exceeds
            if (users[_addr].payouts + _to_payout > _max_payout) {
                _to_payout = _max_payout.safeSub(users[_addr].payouts);
            }

            users[_addr].payouts += _gross_payout;

            if (!isClaimedOut) {
                //Payout referrals
                uint256 compoundTaxedPayout = _to_payout
                    .mul(SafeMath.sub(100, CompoundTax))
                    .div(100); // 5% tax on compounding
                _refPayout(_addr, compoundTaxedPayout, 5);
            }
        }

        require(_to_payout > 0, "Zero payout");

        //Update the payouts
        total_withdraw += _to_payout;

        //Update time!
        users[_addr].deposit_time = block.timestamp;
        users[_addr].accumulatedDiv = 0;

        emit Withdraw(_addr, _to_payout);

        if (users[_addr].payouts >= _max_payout) {
            emit LimitReached(_addr, users[_addr].payouts);
        }

        return _to_payout;
    }

    /********* Views ***************************************/

    //@dev Returns true if the address is net positive
    function isNetPositive(address _addr) public view returns (bool) {
        (uint256 _credits, uint256 _debits) = creditsAndDebits(_addr);

        return _credits > _debits;
    }

    //@dev Returns the total credits and debits for a given address
    function creditsAndDebits(address _addr)
        public
        view
        returns (uint256 _credits, uint256 _debits)
    {
        User memory _user = users[_addr];
        Airdrop memory _airdrop = airdrops[_addr];

        _credits = _airdrop.airdrops + _user.rolls + _user.deposits;
        _debits = _user.payouts;
    }


    //@dev Returns custody info of _addr
    function getCustody(address _addr)
        public
        view
        returns (
            address _beneficiary,
            uint256 _heartbeat_interval,
            address _manager
        )
    {
        return (
            custody[_addr].beneficiary,
            custody[_addr].heartbeat_interval,
            custody[_addr].manager
        );
    }

    //@dev Returns account activity timestamps
    function lastActivity(address _addr)
        public
        view
        returns (
            uint256 _heartbeat,
            uint256 _lapsed_heartbeat,
            uint256 _checkin,
            uint256 _lapsed_checkin
        )
    {
        _heartbeat = custody[_addr].last_heartbeat;
        _lapsed_heartbeat = block.timestamp.safeSub(_heartbeat);
        _checkin = custody[_addr].last_checkin;
        _lapsed_checkin = block.timestamp.safeSub(_checkin);
    }

    //@dev Returns amount of claims available for sender
    function claimsAvailable(address _addr) public view returns (uint256) {
        (, , uint256 _to_payout, ) = payoutOf(_addr);
        return _to_payout;
    }

    //@dev Maxpayout of 3.65 of deposit
    function maxPayoutOf(uint256 _amount) public pure returns (uint256) {
        return (_amount * 365) / 100;
    }

    function sustainabilityFeeV2(address _addr, uint256 _pendingDiv)
        public
        view
        returns (uint256)
    {
        uint256 _bracket = users[_addr].payouts.add(_pendingDiv).div(
            deposit_bracket_size
        );
        _bracket = SafeMath.min(_bracket, deposit_bracket_max);
        return _bracket * 5;
    }

    //@dev Calculate the current payout and maxpayout of a given address
    function payoutOf(address _addr)
        public
        view
        returns (
            uint256 payout,
            uint256 max_payout,
            uint256 net_payout,
            uint256 sustainability_fee
        )
    {
        //The max_payout is capped so that we can also cap available rewards daily
        max_payout = maxPayoutOf(users[_addr].deposits).min(max_payout_cap);

        uint256 share;

        if (users[_addr].payouts < max_payout) {
            //Using 1e18 we capture all significant digits when calculating available divs
            share = users[_addr]
                .deposits
                .mul(payoutRate * 1e18)
                .div(100e18)
                .div(24 hours); //divide the profit by payout rate and seconds in the day

            payout = share * block.timestamp.safeSub(users[_addr].deposit_time);

            payout += users[_addr].accumulatedDiv;

            // payout remaining allowable divs if exceeds
            if (users[_addr].payouts + payout > max_payout) {
                payout = max_payout.safeSub(users[_addr].payouts);
            }

            uint256 _fee = sustainabilityFeeV2(_addr, payout);

            sustainability_fee = (payout * _fee) / 100;

            net_payout = payout.safeSub(sustainability_fee);
        }
    }

    //@dev Get current user snapshot
    function userInfo(address _addr)
        external
        view
        returns (
            address upline,
            uint256 deposit_time,
            uint256 deposits,
            uint256 payouts,
            uint256 direct_bonus,
            uint256 match_bonus
        )
    {
        return (
            users[_addr].upline,
            users[_addr].deposit_time,
            users[_addr].deposits,
            users[_addr].payouts,
            users[_addr].direct_bonus,
            users[_addr].match_bonus
        );
    }

    //@dev Get user totals
    function userInfoTotals(address _addr)
        external
        view
        returns (
            uint256 referrals,
            uint256 total_deposits,
            uint256 total_payouts,
            uint256 total_structure,
            uint256 airdrops_total,
            uint256 airdrops_received
        )
    {
        return (
            users[_addr].referrals,
            users[_addr].deposits,
            users[_addr].payouts,
            users[_addr].total_structure,
            airdrops[_addr].airdrops,
            airdrops[_addr].airdrops_received
        );
    }

    function getUserInfo(address _user) external view returns(User memory user, uint256 max_payout, uint256 net_payout, uint256 tokenBalance){
        user = users[_user];
        (,max_payout,net_payout,) = payoutOf(_user);
        tokenBalance = huchaToken.balanceOf(_user);
    }

    //@dev Get contract snapshot
    function contractInfo()
        external
        view
        returns (
            uint256 _total_users,
            uint256 _total_deposited,
            uint256 _total_withdraw,
            uint256 _total_bnb,
            uint256 _total_txs,
            uint256 _unlock_date,
            uint256 _lock_date,           
            uint256 _unlock_period,
            uint256 _lock_period          
        )
    {
        return (
            total_users,
            total_deposited,
            total_withdraw,
            total_bnb,
            total_txs,
            unlock_date,
            lock_date,
            unlock_period,
            lock_period
        );
    }
}

/**
 * @title SafeMath
 * @dev Math operations with safety checks that throw on error
 */
library SafeMath {
    /**
     * @dev Multiplies two numbers, throws on overflow.
     */
    function mul(uint256 a, uint256 b) internal pure returns (uint256 c) {
        if (a == 0) {
            return 0;
        }
        c = a * b;
        assert(c / a == b);
        return c;
    }

    /**
     * @dev Integer division of two numbers, truncating the quotient.
     */
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        // assert(b > 0); // Solidity automatically throws when dividing by 0
        // uint256 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold
        return a / b;
    }

    /**
     * @dev Subtracts two numbers, throws on overflow (i.e. if subtrahend is greater than minuend).
     */
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        assert(b <= a);
        return a - b;
    }

    /* @dev Subtracts two numbers, else returns zero */
    function safeSub(uint256 a, uint256 b) internal pure returns (uint256) {
        if (b > a) {
            return 0;
        } else {
            return a - b;
        }
    }

    /**
     * @dev Adds two numbers, throws on overflow.
     */
    function add(uint256 a, uint256 b) internal pure returns (uint256 c) {
        c = a + b;
        assert(c >= a);
        return c;
    }

    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a >= b ? a : b;
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}
