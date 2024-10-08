// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
// import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

// import "hardhat/console.sol";

contract RCCStake is 
    Initializable, 
    UUPSUpgradeable, 
    PausableUpgradeable, 
    AccessControlUpgradeable 
{

    using Math for uint256;
    using Address for address;
    using SafeERC20 for IERC20;

    bytes32 public constant ADMIN_ROLE = keccak256("admin_role");
    bytes32 public constant UPGRADE_ROLE = keccak256("upgrade_role");

    uint256 public constant nativeCurrency_PID = 0;

    struct Pool {
        address sTokenAddress;//质押代币的地址。
        uint256 poolWeight;//质押池的权重，影响奖励分配。
        uint256 lastRewardBlock;//最后一次计算奖励的区块号。
        uint256 accRCCPerST;//每个质押代币累积的 RCC 数量。
        uint256 minDepositAmount;//最小质押金额。
        uint256 unstakeLockedBlocks;//解除质押的锁定区块数。
        uint256 stTokenAmount;//总的质押代币数量
    }

    struct UnstakeRequest {
        uint256 amount;//解质押数量
        uint256 unlockBlock;//解锁区块
    }

    struct User{
        uint256 stAmount;//用户质押的代币数量。
        uint256 finishRCC;//已分配的 RCC 数量
        uint256 pendingRCC;//待领取的 RCC 数量
        UnstakeRequest[] requests;//解质押请求列表，每个请求包含解质押数量和解锁区块。
    }

    uint256 public totalPoolWeight;//总的质押池集合的权重
    Pool[] public pools;//质押池集合
    mapping(uint256 => mapping (address => User)) public users;
    
    uint256 public startBlock;
    uint256 public endBlock;
    uint256 public RCCPerBlock;

    bool public withdrawPaused;
    bool public claimPaused;

    IERC20 public RCC;

    // ************************************** EVENT **************************************
    event SetRCC(IERC20 indexed RCC);

    event PauseWithdraw();

    event UnpauseWithdraw();

    event PauseClaim();

    event UnpauseClaim();

    event SetStartBlock(uint256 indexed startBlock);

    event SetEndBlock(uint256 indexed endBlock);

    event SetRCCPerBlock(uint256 indexed RCCPerBlock);

    event AddPool(address indexed _stTokenAddress, uint256 indexed _poolWeight, uint256 indexed lastRewardBlock, uint256 _minDepositAmount, uint256 _unstakeLockedBlocks);

    event UpdatePool(uint256 indexed _pid, uint256 indexed _lastRewardBlock, uint256 indexed _RCCReward);

    event Deposit(address indexed user, uint256 indexed poolId, uint256 amount);

    event SetPoolWeight(uint256 indexed poolId, uint256 indexed poolWeight, uint256 indexed totalPoolWeight);

    event UpdatePoolInfo(uint256 indexed pid, uint256 indexed minDepositAmount, uint256 indexed unstakeLockedBlocks);

    event Claim(address indexed user, uint256 indexed poolId, uint256 RCCReward);

    event Withdraw(address indexed user, uint256 indexed poolId, uint256 amount, uint256 indexed blockNumber);

    event RequestUnstake(address indexed user, uint256 indexed poolId, uint256 amount);

    // ************************************** MODIFIER **************************************
    modifier checkPid(uint256 _pid){
        require(_pid < pools.length, "invalid pid");
        _;
    }

    modifier whenNotWithdrawPaused() {
        require(!withdrawPaused, "withdraw is paused");
        _;
    }

    modifier whenNotClaimPaused() {
        require(!claimPaused, "claim is paused");
        _;
    }

    function initialize(
        IERC20 _RCC,
        uint256 _startBlock,
        uint256 _endBlock,
        uint256 _RCCPerBlock
    ) public initializer {
        require(_startBlock <= _endBlock && _RCCPerBlock > 0, "invalid parameters");

        __AccessControl_init();
        __UUPSUpgradeable_init();
        __Pausable_init();
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(UPGRADE_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);

        setRCC(_RCC);

        startBlock = _startBlock;
        endBlock = _endBlock;
        RCCPerBlock = _RCCPerBlock;
    }

    function _authorizeUpgrade(address newImplementation) internal onlyRole(UPGRADE_ROLE) override{

    }
    // ************************************** QUERY FUNCTION **************************************
    function poolLength() external view returns (uint256) {
        return pools.length;
    } 

    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256 multiplier) {
        require(_from <= _to, "invalid block range");
        if(_from < startBlock){
            _from = startBlock;
        }
        if(_to > endBlock){
            _to = endBlock;
        }

        require(_from <= _to, "end block must be greater than start block");
        bool success;
        (success, multiplier) = Math.tryMul((_to - _from), RCCPerBlock);
        require(success, "multiplier overflow");
    }

    function pendingRCC(uint256 _pid, address _user) external checkPid(_pid) view returns(uint256){
        return pendingRCCByBlockNumber(_pid, _user, block.number);
    }

    function pendingRCCByBlockNumber(uint256 _pid, address _user, uint256 _blockNumber) public checkPid(_pid) view returns(uint256){
        Pool storage pool = pools[_pid];
        User storage user = users[_pid][_user];
        uint256 accPerST = pool.accRCCPerST;
        uint256 stSupply = pool.stTokenAmount;

        if(_blockNumber > pool.lastRewardBlock && stSupply > 0){
            uint256 multiper = getMultiplier(_blockNumber, pool.lastRewardBlock);
            uint256 RCCForPool = multiper * pool.poolWeight / totalPoolWeight;
            accPerST = accPerST + RCCForPool * (1 ether) / stSupply;
        }
        
        return user.stAmount * accPerST / (1 ether) - user.finishRCC + user.pendingRCC;
    }

    function stakingBalance(uint256 _pid, address _user) external checkPid(_pid) view returns(uint256){
        return users[_pid][_user].stAmount;
    }

    function withdrawAmount(uint256 _pid, address _user) public checkPid(_pid) view returns(uint256 requestAmount, uint256 pendingWithdrawAmount){
        User storage user = users[_pid][_user];

        for(uint256 i = 0; i < user.requests.length; i ++){
            UnstakeRequest memory request = user.requests[i];
            if(block.number >= request.unlockBlock){
                pendingWithdrawAmount = pendingWithdrawAmount + request.amount;
            }
            requestAmount = requestAmount + request.amount;
        }
    }
    // ************************************** ADMIN FUNCTION **************************************
    function setRCC(IERC20 _RCC) public onlyRole(ADMIN_ROLE){
        RCC = _RCC;

        emit SetRCC(RCC);
    }

    function pauseWithdraw() public onlyRole(ADMIN_ROLE){
        require(!withdrawPaused, "withdraw has been already paused");

        withdrawPaused = true;

        emit PauseWithdraw();
    }

    function unpauseWithdraw() public onlyRole(ADMIN_ROLE){
        require(withdrawPaused, "withdraw has been already unpaused");

        withdrawPaused = false;

        emit UnpauseWithdraw();
    }

    function pauseClaim() public onlyRole(ADMIN_ROLE){
        require(!claimPaused, "claim has been already paused");

        claimPaused = true;

        emit PauseClaim();
    }

    function unpauseClaim() public onlyRole(ADMIN_ROLE){
        require(claimPaused, "claim has been already unpaused");

        claimPaused = false;

        emit UnpauseClaim();
    }

    function setStartBlock(uint256 _startBlock) public onlyRole(ADMIN_ROLE){
        require(_startBlock <= endBlock, "start block must be smaller than end block");

        startBlock = _startBlock;
        emit SetStartBlock(_startBlock);
    }

    function setEndBlock(uint256 _endBlock) public onlyRole(ADMIN_ROLE){
        require(startBlock <= _endBlock, "start block must be smaller than end block");

        endBlock = _endBlock;
        emit SetEndBlock(_endBlock);
    }

    function setRCCPerBlock(uint256 _RCCPerBlock) public onlyRole(ADMIN_ROLE){
        require(_RCCPerBlock > 0, "rccperblock must > 0");

        RCCPerBlock = _RCCPerBlock;
        emit SetRCCPerBlock(_RCCPerBlock);
    }

    function addPool(address _stTokenAddress, uint256 _poolWeight, uint256 _minDepositAmount, uint256 _unstakeLockedBlocks, bool _withUpdate) public onlyRole(ADMIN_ROLE){
        if(pools.length > 0){
            require(_stTokenAddress != address(0x0), "! first token address invalid address = 0x0!");
        }
        else{
            require(_stTokenAddress == address(0x0), "first token address must 0x0!");
        }

        require(_unstakeLockedBlocks > 0, "invalid withdraw locked blocks");
        require(block.number < endBlock, "Already ended");

        if(_withUpdate){
            massUpdatePools();
        }

        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalPoolWeight = totalPoolWeight + _poolWeight;
        Pool memory _pool = Pool({sTokenAddress:_stTokenAddress, poolWeight:_poolWeight, lastRewardBlock:lastRewardBlock, stTokenAmount:0, accRCCPerST:0, minDepositAmount:_minDepositAmount, unstakeLockedBlocks:_unstakeLockedBlocks});
        
        pools.push(_pool);

        emit AddPool(_stTokenAddress, _poolWeight, lastRewardBlock, _minDepositAmount, _unstakeLockedBlocks);
    }

    function updatePool(uint256 _pid, uint256 _minDepositAmount, uint256 _unstakeLockedBlocks) public onlyRole(ADMIN_ROLE) checkPid(_pid) {
        pools[_pid].minDepositAmount = _minDepositAmount;
        pools[_pid].unstakeLockedBlocks = _unstakeLockedBlocks;

        emit UpdatePoolInfo(_pid, _minDepositAmount, _unstakeLockedBlocks);
    }

    function setPoolWeight(uint256 _pid, uint256 _poolWeight, bool _withUpdate) public onlyRole(ADMIN_ROLE) checkPid(_pid) {
        require(_poolWeight > 0, "invalid pool weight");

        if(_withUpdate){
            massUpdatePools();
        }

        totalPoolWeight = totalPoolWeight - pools[_pid].poolWeight + _poolWeight;
        pools[_pid].poolWeight = _poolWeight;

        emit SetPoolWeight(_pid, _poolWeight, totalPoolWeight);
    }

    // ************************************** PUBLIC FUNCTION **************************************
    //从钱包存入token 到 合约质押池，获取RCC奖励
    function deposit(uint256 _pid, uint256 _amount) public checkPid(_pid) whenNotPaused() {
        require(_pid != 0, "deposit not support nativeCurrency staking");
        Pool storage pool_ = pools[_pid];
        require(_amount > pool_.minDepositAmount, "amount < minDepositAmount");

        if(_amount > 0) {
            IERC20(pool_.sTokenAddress).safeTransferFrom(msg.sender, address(this), _amount);
        }
        
        _deposit(_pid, _amount);
    }

    //解除质押，不再获得RCC奖励
    function unstake(uint256 _pid, uint256 _amount) public checkPid(_pid) whenNotPaused() whenNotWithdrawPaused() {
        Pool storage pool = pools[_pid];
        User storage user = users[_pid][msg.sender];

        require(user.stAmount >= _amount, "user token must bigger than _amount");

        updatePool(_pid);

        uint256 pendingRCC_ = user.stAmount * pool.accRCCPerST / (1 ether) - user.finishRCC;
        if(pendingRCC_ > 0){
            user.pendingRCC = user.pendingRCC + pendingRCC_;
        }
        if(_amount > 0){
            user.stAmount = user.stAmount - _amount;
            user.requests.push(UnstakeRequest({amount:_amount, unlockBlock:block.number + pool.unstakeLockedBlocks}));
        }

        user.finishRCC = user.stAmount * pool.accRCCPerST / (1 ether);
        pool.stTokenAmount = pool.stTokenAmount - _amount;

        emit RequestUnstake(msg.sender, _pid, _amount);
    }

    //将token提取到钱包
    function withdraw(uint256 _pid) public checkPid(_pid) whenNotPaused() whenNotWithdrawPaused() {
        Pool storage pool = pools[_pid];
        User storage user = users[_pid][msg.sender];

        uint256 popNum_;
        uint256 pendingWithdrawRCC;

        for(uint256 i = 0; i < user.requests.length; i ++){
            if(block.number < user.requests[i].unlockBlock){
                break;
            }

            popNum_ ++;
            pendingWithdrawRCC = pendingWithdrawRCC + user.requests[i].amount;
        }

        for(uint256 i = 0; i < user.requests.length - popNum_; i ++){
            user.requests[i] = user.requests[i + popNum_];
        }

        for(uint256 i = 0; i < popNum_; i ++){
            user.requests.pop();
        }

        if(pendingWithdrawRCC > 0){
            if(pool.sTokenAddress == address(0x0)){
                _safenativeCurrencyTransfer(msg.sender, pendingWithdrawRCC);
            }
            else{
                IERC20(pool.sTokenAddress).safeTransfer(msg.sender, pendingWithdrawRCC);
            }
        }

        emit Withdraw(msg.sender, _pid, pendingWithdrawRCC, block.number);
    }

    //领取 RCC奖励
    function claim(uint256 _pid) public checkPid(_pid) whenNotPaused() whenNotClaimPaused() {
        Pool storage pool = pools[_pid];
        User storage user = users[_pid][msg.sender];

        updatePool(_pid);

        uint256 userTotalRCC = user.stAmount * pool.accRCCPerST / (1 ether);

        uint256 pendingRCC_ = userTotalRCC - user.finishRCC + user.pendingRCC;

        if(pendingRCC_ > 0) {
            user.pendingRCC = 0;
            _safeRCCTrasfer(msg.sender, pendingRCC_);
        }

        user.finishRCC = userTotalRCC;
        
        emit Claim(msg.sender, _pid, pendingRCC_);
    }


    function updatePool(uint256 _pid) public checkPid(_pid) {
        Pool storage pool_ = pools[_pid];
        if(block.number <= pool_.lastRewardBlock){
            return;
        }

        /**
         * 1、计算当前质押池总的RCC（代币）奖励：  
         * 奖励公式： 奖励总和 = （（当前区块号 - 上一次获取奖励的区块号）X 当前质押池的权重）/ 总的权重
         */
        (bool succ1, uint256 totalRCC) = getMultiplier(pool_.lastRewardBlock, block.number).tryMul(pool_.poolWeight); 
        require(succ1, "totalRCC mul poolWeight overflow");

        (succ1, totalRCC) = totalRCC.tryDiv(totalPoolWeight);
        require(succ1, "totalRCC div totalPoolWeight overflow");

        /**
         * 2、计算当前质押池每个质押的代币奖励的RCC数量：  
         * 公式： 每个质押的代币奖励的RCC数量 = （（奖励总和 X 1 eth）/ 总的质押代币数量） + 当前质押池每个代币奖励的数量  （每个代币质押的RCC奖励是一直累积的）
         */
        uint256 stSupply = pool_.stTokenAmount;
        if(stSupply > 0){
            (bool succ2, uint256 totalRCC_) = totalRCC.tryMul(1 ether);
            require(succ2, "totalRCC mul 1 ether overflow");

            (succ2, totalRCC_) = totalRCC_.tryDiv(stSupply);
            require(succ2, "totalRCC div stSupply overflow");

            (bool succ3, uint256 accRCCPerST) = totalRCC_.tryAdd(pool_.accRCCPerST);
            require(succ3, "pool accRCCPerST overflow");

            pool_.accRCCPerST = accRCCPerST;
        }

        /**
         * 3、更新当前质押池的上一次获取奖励区块号 为 当前区块号
         */
        pool_.lastRewardBlock = block.number;

        /**
         * 4、广播更新质押池的事件 包含 质押池ID、此次更新到的区块号ID、当前质押池产生的代币奖励
         */
        emit UpdatePool(_pid, pool_.lastRewardBlock, totalRCC);
    }

    function massUpdatePools() public {
        uint256 length = pools.length;
        for(uint256 i = 0; i < length; i ++){ 
            updatePool(i);
        }
    }

    function depositnativeCurrency()public whenNotPaused() payable {
        Pool storage pool_ = pools[nativeCurrency_PID];
        require(pool_.sTokenAddress == address(0x0), "invalid staking token address");

        uint256 amount = msg.value;
        require(amount > pool_.minDepositAmount, "deposit amout is too small");

        _deposit(nativeCurrency_PID, amount);
    }

    // ************************************** INTERNAL FUNCTION **************************************
    function _deposit(uint256 _pid, uint256 _amount) internal{
        Pool storage pool_ = pools[_pid];
        User storage user_ = users[_pid][msg.sender];

        updatePool(_pid);

        if(user_.stAmount > 0){
            (bool succ1, uint256 accST) = user_.stAmount.tryMul(pool_.accRCCPerST);
            require(succ1, "user stAmount mul accRCCPerST overflow!");

            (succ1, accST) = accST.tryDiv(1 ether);
            require(succ1, "accST div 1 ether overflow");

            (bool succ2, uint256 pendingRCC_) = accST.trySub(user_.pendingRCC);
            require(succ2, "accST sub pending overflow");

            if(pendingRCC_ > 0){
                (bool succ3, uint256 _pendingRCC) = user_.pendingRCC.tryAdd(pendingRCC_);
                require(succ3, "accST sub pending overflow");

                user_.pendingRCC = _pendingRCC;
            }
        }

        if(_amount > 0){
            (bool succ4, uint256 stAmount) = pool_.stTokenAmount.tryAdd(_amount);
            require(succ4, "stAmount add overflow");
            pool_.stTokenAmount = stAmount;

            (bool succ5, uint256 tkAmount) = user_.stAmount.tryAdd(_amount);
            require(succ5, "tkAmount add overflow");
            user_.stAmount = tkAmount;

            (bool succ6, uint256 finishRCC) = user_.stAmount.tryMul(pool_.accRCCPerST);
            require(succ6, "finishRCC mul overflow");
            (succ6, finishRCC) = finishRCC.tryDiv(1 ether);
            require(succ6, "finishRCC div overflow");

            user_.finishRCC = finishRCC;

        }

        emit Deposit(msg.sender, _pid, _amount);
    }

    function _safeRCCTrasfer(address _to, uint256 _amount) internal {
        uint256 balance = RCC.balanceOf(address(this));

        if(_amount > balance){
            RCC.transfer(_to, balance);
        }
        else{
            RCC.transfer(_to, _amount);
        }
    }

    function _safenativeCurrencyTransfer(address _to, uint256 _amount) internal {
        (bool succ,) = address(_to).call{value: _amount}("");
        require(succ, "nativeCurrency transfer call failed");
        // Remove the if statement checking data.length
    }

}