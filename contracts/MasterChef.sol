// SPDX-License-Identifier: MIT
pragma experimental ABIEncoderV2;
pragma solidity =0.6.12;

import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../interfaces/IRewarder.sol";
import "./Ulti.sol";

contract MasterChef is Ownable, ReentrancyGuard {
    string public constant name = "MasterChef";
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using SafeERC20 for Ulti;

    struct TrackedUserInfo {
        address addr;
        uint256 depositTxs;
        uint256 withdrawTxs;
        uint256 lastActionBlock;
    }

    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
    }

    struct PoolInfo {
        IERC20 lpToken;
        uint256 allocPoint;
        uint256 lastRewardTime;
        uint256 accUltiPerShare;
        uint256 totalLp;
        address rewarder; // bonus other tokens
    }

    uint256 public depositTxs;
    uint256 public withdrawTxs;
    mapping(address => uint256) public trackedUserIndex;
    TrackedUserInfo[] public trackedUserInfo;

    Ulti public immutable ulti;
    uint256 public immutable startTime;
    address public constant burnAddress = address(0x000000000000000000000000000000000000dEaD);
    uint256 public burnPercent;
    uint256 public ultiPerSecond;

    PoolInfo[] public poolInfo;
    mapping (uint256 => mapping (address => UserInfo)) public userInfo;
    uint256 public totalAllocPoint;

    event SetEmissionRate(uint256 ultiPerSecond);
    event SetBonusEmissionRate(uint256 indexed pid, uint256 rewardPerSecond);
    event SetPercent(uint256 burnPercent);
    event AddPool(uint256 allocPoint, address lpToken, address rewarder);
    event SetPool(uint256 indexed pid, uint256 allocPoint, address rewarder);
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event FailedToNotifyRewarder(address indexed user, uint256 indexed pid);

    constructor(
        Ulti _ulti,
        uint256 _ultiPerSecond,
        uint256 _burnPercent,
        uint256 _startTime
    ) public {
        ulti = _ulti;
        ultiPerSecond = _ultiPerSecond;
        burnPercent = _burnPercent;
        startTime = _startTime;
    }

    function setEmissionRate(uint256 _ultiPerSecond) external onlyOwner {
        updateAllPools();
        ultiPerSecond = _ultiPerSecond;

        emit SetEmissionRate(_ultiPerSecond);
    }

    function setBonusEmissionRate(uint _pid, uint _rewardPerSecond) external onlyOwner {
        require(_pid < poolInfo.length, "setBonusEmissionRate: The pool does not exist");
        PoolInfo storage pool = poolInfo[_pid];

        updatePool(_pid);

        address rewarder = pool.rewarder;
        if (rewarder != address(0)) {
            IRewarder(rewarder).setRewardPerSecond(_rewardPerSecond);
        }

        emit SetBonusEmissionRate(_pid, _rewardPerSecond);
    }

    function setPercent(
        uint256 _burnPercent) external onlyOwner {
        require(_burnPercent < 100e18, "setPercent: Percent cannot exceed 100");
        updateAllPools();
        burnPercent = _burnPercent;

        emit SetPercent(_burnPercent);
    }

    function _updateTrackedUserInfo(address _user) internal {
        uint256 id = trackedUserIndex[_user];
        if (id > 0) {
            trackedUserInfo[id - 1].lastActionBlock = block.number;
            return;
        }
        trackedUserInfo.push(TrackedUserInfo({
            addr: _user,
            depositTxs: 0,
            withdrawTxs: 0,
            lastActionBlock: block.number
        }));
        trackedUserIndex[_user] = trackedUserInfo.length;
    }

    function _updateDepositTx(address _user) internal {
        _updateTrackedUserInfo(_user);
        TrackedUserInfo storage user = trackedUserInfo[trackedUserIndex[_user] - 1];
        user.depositTxs = user.depositTxs + 1;
        depositTxs = depositTxs + 1;
    }

    function _updateWithdrawTx(address _user) internal {
        _updateTrackedUserInfo(_user);
        TrackedUserInfo storage user = trackedUserInfo[trackedUserIndex[_user] - 1];
        user.withdrawTxs = user.withdrawTxs + 1;
        withdrawTxs = withdrawTxs + 1;
    }

    function totalUsers() external view returns (uint256) {
        return trackedUserInfo.length;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    function addPool(uint256 _allocPoint, IERC20 _lpToken, address _rewarder) external onlyOwner {
        updateAllPools();

        uint256 lastRewardTime = block.timestamp > startTime ? block.timestamp : startTime;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(PoolInfo({
            lpToken: _lpToken,
            allocPoint: _allocPoint,
            lastRewardTime: lastRewardTime,
            accUltiPerShare: 0,
            totalLp: 0,
            rewarder: _rewarder
        }));

        emit AddPool(_allocPoint, address(_lpToken), _rewarder);
    }

    function setPool(uint256 _pid, uint256 _allocPoint, address _rewarder) external onlyOwner {
        require(_pid < poolInfo.length, "setPool: The pool does not exist");
        updateAllPools();

        totalAllocPoint = totalAllocPoint.add(_allocPoint).sub(poolInfo[_pid].allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
        poolInfo[_pid].rewarder = _rewarder;

        emit SetPool(_pid, _allocPoint, _rewarder);
    }

    function getMultiplier(uint256 _from, uint256 _to) private view returns (uint256) {
        return _to.sub(_from);
    }

    function pendingReward(uint256 _pid, address _user) external view returns (uint256 pendingUlti, uint256 pendingBonus) {
        require(_pid < poolInfo.length, "pendingReward: The pool does not exist");
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accUltiPerShare = pool.accUltiPerShare;
        uint256 lpSupply = pool.totalLp;
        uint256 lastRewardTime = pool.lastRewardTime;
        if (block.timestamp > lastRewardTime && lpSupply != 0) {
            uint256 multiplier = getMultiplier(lastRewardTime, block.timestamp);
            uint256 ultiReward = multiplier.mul(ultiPerSecond).mul(pool.allocPoint).div(totalAllocPoint);

            ( , uint256 farmUlti) = calculate(ultiReward);

            accUltiPerShare = accUltiPerShare.add(farmUlti.mul(1e18).div(lpSupply));
        }
        pendingUlti = user.amount.mul(accUltiPerShare).div(1e18).sub(user.rewardDebt);
        address rewarder = pool.rewarder;
        if (rewarder != address(0)) {
            pendingBonus = IRewarder(rewarder).pendingReward(_user, user.amount);
        }
    }

    function updateAllPools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; pid++) {
            updatePool(pid);
        }
    }

    function updateMultiplePools(uint256[] memory pids) external {
        for (uint256 i = 0; i < pids.length; i++) {
            updatePool(pids[i]);
        }
    }

    function calculate(uint256 _reward) private view returns (uint256 burnUlti, uint256 farmUlti) {
        uint256 totalSupply = ulti.totalSupply();
        uint256 maxSupply = ulti.maxSupply();
        if (maxSupply < totalSupply.add(_reward)) {
            _reward = maxSupply.sub(totalSupply);
        }
        
        burnUlti = _reward.mul(burnPercent).div(100e18);
        farmUlti = _reward.sub(burnUlti);
    }

    function updatePool(uint256 _pid) public {
        require(_pid < poolInfo.length, "updatePool: The pool does not exist");
        PoolInfo storage pool = poolInfo[_pid];
        uint256 lastRewardTime = pool.lastRewardTime;
        if (block.timestamp <= lastRewardTime) {
            return;
        }
        uint256 lpSupply = pool.totalLp;
        if (lpSupply == 0 || pool.allocPoint == 0) {
            pool.lastRewardTime = block.timestamp;
            return;
        }

        uint256 multiplier = getMultiplier(lastRewardTime, block.timestamp);
        uint256 ultiReward = multiplier.mul(ultiPerSecond).mul(pool.allocPoint).div(totalAllocPoint);

        (uint256 burnUlti, uint256 farmUlti) = calculate(ultiReward);

        ulti.mint(address(this), burnUlti.add(farmUlti));
        if (burnUlti > 0) {
            ulti.transfer(burnAddress, burnUlti);
        }

        pool.accUltiPerShare = pool.accUltiPerShare.add(farmUlti.mul(1e18).div(lpSupply));
        pool.lastRewardTime = block.timestamp;
    }

    function deposit(uint256 _pid, uint256 _amount) external nonReentrant {
        require(_pid < poolInfo.length, "deposit: The pool does not exist");
        _updateDepositTx(msg.sender);
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        updatePool(_pid);
        uint256 amount = user.amount;
        uint256 accUltiPerShare = pool.accUltiPerShare;
        uint lpSupply = pool.totalLp;
        if (amount > 0) {
            uint256 pending = amount.mul(accUltiPerShare).div(1e18).sub(user.rewardDebt);
            ulti.safeTransfer(address(msg.sender), pending);
        }

        if(_amount > 0) {
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            user.amount = amount.add(_amount);
            pool.totalLp = lpSupply.add(_amount);
        }
        
        amount = user.amount;
        address rewarder = pool.rewarder;
        if (rewarder != address(0)) {
            IRewarder(rewarder).onReward(address(msg.sender), amount);
        }
        user.rewardDebt = amount.mul(accUltiPerShare).div(1e18);

        emit Deposit(msg.sender, _pid, _amount);
    }

    function withdraw(uint256 _pid, uint256 _amount) external nonReentrant {
        require(_pid < poolInfo.length, "withdraw: BAD POOL");
        _updateWithdrawTx(msg.sender);
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 amount = user.amount;
        require(amount >= _amount, "withdraw: Exceeded user's amount");

        updatePool(_pid);
        uint256 accUltiPerShare = pool.accUltiPerShare;
        uint lpSupply = pool.totalLp;
        if (amount > 0) {
            uint256 pending = amount.mul(accUltiPerShare).div(1e18).sub(user.rewardDebt);
            ulti.safeTransfer(address(msg.sender), pending);
        }

        if(_amount > 0) {
            user.amount = amount.sub(_amount);
            pool.totalLp = lpSupply.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
            
        amount = user.amount;
        address rewarder = pool.rewarder;
        if (rewarder != address(0)) {
            IRewarder(rewarder).onReward(address(msg.sender), amount);
        }
        user.rewardDebt = amount.mul(accUltiPerShare).div(1e18);

        emit Withdraw(msg.sender, _pid, _amount);
    }

    // only for emergency case and users do not care about reward
    function emergencyWithdraw(uint256 _pid) external nonReentrant {
        _updateWithdrawTx(msg.sender);
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 amount = user.amount;
        user.amount = 0;
        address rewarder = pool.rewarder;
        pool.totalLp = pool.totalLp.sub(amount);
        user.rewardDebt = 0;
        pool.lpToken.safeTransfer(address(msg.sender), amount);
        emit EmergencyWithdraw(msg.sender, _pid, amount);

        uint256 size;
        assembly {
            size := extcodesize(rewarder)
        }
        if (rewarder != address(0) && size > 0) {
            try IRewarder(rewarder).onReward(address(msg.sender), 0) {} catch {
                emit FailedToNotifyRewarder(msg.sender, _pid);
            }
        }
    }
}
