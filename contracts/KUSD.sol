pragma solidity 0.7.6;

import "./SafeMath.sol";
import "./Ownable.sol";
import "./ERC20Detailed.sol";

import "./SafeMathInt.sol";

contract KUSD is ERC20Detailed, Ownable {
    
    using SafeMath for uint256;
    using SafeMathInt for int256;

    event LogRedemption(uint256 indexed epoch, uint256 indexed totalSupply);
    event LogMonetaryPolicyUpdated(address monetaryPolicy);
    event LogOracleRate(uint indexed OracleRate, uint indexed Time);
    event LogCurrentTargetPrice(uint indexed TargetPrice, uint indexed Time);
    event LogTotalSupply(uint indexed TotalSupply, uint indexed Time);
    

    // Used for authentication
    address public monetaryPolicy;

    modifier onlyMonetaryPolicy() {
        require(msg.sender == monetaryPolicy);
        _;
    }

    modifier validRecipient(address to) {
        require(to != address(0x0));
        require(to != address(this));
        _;
    }

    uint256 private constant DECIMALS = 18;
    uint256 public constant MAX_UINT256 = type(uint256).max;
    uint256 private constant INITIAL_SHARES_SUPPLY = 12 * 10**6 * 10**DECIMALS;

    // TOTAL_KONS is a multiple of INITIAL_SHARES_SUPPLY so that _konsPerShare is an integer.
    // Using the highest value that fits in a uint256 for max granularity.
    uint256 private constant TOTAL_KONS = MAX_UINT256 - (MAX_UINT256 % INITIAL_SHARES_SUPPLY);

   
    uint256 public constant MAX_SUPPLY = type(uint128).max; // (2^128) - 1

    uint256 private _totalSupply;
    uint256 private _konsPerShare;
    mapping(address => uint256) private _konBalances;

    // This is denominated in Shares, because the kons-shares conversion might change before
    // it's fully paid.
    mapping(address => mapping(address => uint256)) private _allowedShares;
    
    uint256 EPOCH_INTERVAL = 1 days;
    uint256 next_epoch = 0;
    uint256 epoch=0;


    /**
     * @param monetaryPolicy_ The address of the monetary policy contract to use for authentication.
     */
    function setMonetaryPolicy(address monetaryPolicy_) external onlyOwner {
        monetaryPolicy = monetaryPolicy_;
        emit LogMonetaryPolicyUpdated(monetaryPolicy_);
    }
    
    /**
     * @param interval The new interval for Epoch Propogation.
     */
    function changeEpochInterval(uint256 interval) public onlyOwner {
        EPOCH_INTERVAL = interval;
    }

    /**
     * @dev Notifies Shares contract about a new redemption cycle.
     * @param supplyDelta The number of new shares tokens to add into circulation via expansion.
     * @return The total number of shares after the supply adjustment.
     */
    function redemption(int256 supplyDelta, uint OracleRate, uint TargetPrice)
        external
        onlyMonetaryPolicy
        returns (uint256)
    {
        if (supplyDelta == 0) {
            emit LogRedemption(epoch, _totalSupply);
            emit LogOracleRate(OracleRate,block.timestamp);
            emit LogCurrentTargetPrice(TargetPrice,block.timestamp);
            emit LogTotalSupply(_totalSupply,block.timestamp);
            epoch++;
            next_epoch = block.timestamp + EPOCH_INTERVAL;
            return _totalSupply;
        }

        if (supplyDelta < 0) {
            _totalSupply = _totalSupply.sub(uint256(supplyDelta.abs()));
        } else {
            _totalSupply = _totalSupply.add(uint256(supplyDelta));
        }

        if (_totalSupply > MAX_SUPPLY) {
            _totalSupply = MAX_SUPPLY;
        }

        _konsPerShare = TOTAL_KONS.div(_totalSupply);

        emit LogRedemption(epoch, _totalSupply);
        emit LogOracleRate(OracleRate,block.timestamp);
        emit LogCurrentTargetPrice(TargetPrice,block.timestamp);
        emit LogTotalSupply(_totalSupply,block.timestamp);
        epoch++;
        next_epoch = block.timestamp + EPOCH_INTERVAL;
        return _totalSupply;
    }

    function initialize(address owner_) public override initializer {
        ERC20Detailed.initialize("Konstant Stable USD", "KUSD", uint8(DECIMALS));
        Ownable.initialize(owner_);

        _totalSupply = INITIAL_SHARES_SUPPLY;
        _konBalances[owner_] = TOTAL_KONS;
        _konsPerShare = TOTAL_KONS.div(_totalSupply);
        
        next_epoch = block.timestamp + EPOCH_INTERVAL;

        emit Transfer(address(0x0), owner_, _totalSupply);
    }
    
    function next_epoch_time() public view returns(uint256){
        return next_epoch;
    }

    /**
     * @return The total number of shares.
     */
    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }

    /**
     * @param who The address to query.
     * @return The balance of the specified address.
     */
    function balanceOf(address who) external view override returns (uint256) {
        return _konBalances[who].div(_konsPerShare);
    }

    /**
     * @param who The address to query.
     * @return The kon balance of the specified address.
     */
    function scaledBalanceOf(address who) external view returns (uint256) {
        return _konBalances[who];
    }

    /**
     * @return the total number of kons.
     */
    function scaledTotalSupply() external pure returns (uint256) {
        return TOTAL_KONS;
    }

   
    /**
     * @dev Transfer tokens to a specified address.
     * @param to The address to transfer to.
     * @param value The amount to be transferred.
     * @return True on success, false otherwise.
     */
    function transfer(address to, uint256 value)
        external
        override
        validRecipient(to)
        returns (bool)
    {
        uint256 konValue = value.mul(_konsPerShare);

        _konBalances[msg.sender] = _konBalances[msg.sender].sub(konValue);
        _konBalances[to] = _konBalances[to].add(konValue);

        emit Transfer(msg.sender, to, value);
        return true;
    }
    

    /**
     * @dev Function to check the amount of tokens that an owner has allowed to a spender.
     * @param owner_ The address which owns the funds.
     * @param spender The address which will spend the funds.
     * @return The number of tokens still available for the spender.
     */
    function allowance(address owner_, address spender) external view override returns (uint256) {
        return _allowedShares[owner_][spender];
    }

    /**
     * @dev Transfer tokens from one address to another.
     * @param from The address you want to send tokens from.
     * @param to The address you want to transfer to.
     * @param value The amount of tokens to be transferred.
     */
    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external override validRecipient(to) returns (bool) {
        _allowedShares[from][msg.sender] = _allowedShares[from][msg.sender].sub(value);

        uint256 konValue = value.mul(_konsPerShare);
        _konBalances[from] = _konBalances[from].sub(konValue);
        _konBalances[to] = _konBalances[to].add(konValue);

        emit Transfer(from, to, value);
        return true;
    }


    /**
     * @dev Approve the passed address to spend the specified amount of tokens on behalf of
     * msg.sender. 
     * increaseAllowance and decreaseAllowance should be used instead.
     * Changing an allowance with this method brings the risk that someone may transfer both
     * the old and the new allowance - if they are both greater than zero - if a transfer
     * transaction is mined before the later approve() call is mined.
     *
     * @param spender The address which will spend the funds.
     * @param value The amount of tokens to be spent.
     */
    function approve(address spender, uint256 value) external override returns (bool) {
        _allowedShares[msg.sender][spender] = value;

        emit Approval(msg.sender, spender, value);
        return true;
    }

    /**
     * @dev Increase the amount of tokens that an owner has allowed to a spender.
     * This method should be used instead of approve() to avoid the double approval vulnerability
     * described above.
     * @param spender The address which will spend the funds.
     * @param addedValue The amount of tokens to increase the allowance by.
     */
    function increaseAllowance(address spender, uint256 addedValue) public returns (bool) {
        _allowedShares[msg.sender][spender] = _allowedShares[msg.sender][spender].add(
            addedValue
        );

        emit Approval(msg.sender, spender, _allowedShares[msg.sender][spender]);
        return true;
    }

    /**
     * @dev Decrease the amount of tokens that an owner has allowed to a spender.
     *
     * @param spender The address which will spend the funds.
     * @param subtractedValue The amount of tokens to decrease the allowance by.
     */
    function decreaseAllowance(address spender, uint256 subtractedValue) external returns (bool) {
        uint256 oldValue = _allowedShares[msg.sender][spender];
        _allowedShares[msg.sender][spender] = (subtractedValue >= oldValue)
            ? 0
            : oldValue.sub(subtractedValue);

        emit Approval(msg.sender, spender, _allowedShares[msg.sender][spender]);
        return true;
    }

}