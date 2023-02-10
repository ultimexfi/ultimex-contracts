// SPDX-License-Identifier: MIT
pragma solidity =0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "../interfaces/IRewarder.sol";

contract Rewarder is IRewarder, Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IERC20 public immutable rewardToken;
    IERC20 public immutable lpToken;
    address public immutable chef;

    // info of each MasterChef user
    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
    }

    // info of each MasterChef poolInfo
    struct PoolInfo {
        uint256 accRewardPerShare;
        uint256 lastRewardTime;
        uint256 totalLp;
    }

    // info of the poolInfo
    PoolInfo public poolInfo;
    // info of each user that stakes LP tokens
    mapping(address => UserInfo) public userInfo;

    uint256 public rewardPerSecond;
    uint256 private constant ACC_TOKEN_PRECISION = 1e18;

    event OnReward(address indexed user, uint256 amount);
    event SetRewardPerSecond(uint256 oldRate, uint256 newRate);

    modifier onlyMasterChef() {
        require(msg.sender == chef, "onlyMasterChef: only MasterChef can call this function");
        _;
    }

    constructor(
        IERC20 _rewardToken,
        IERC20 _lpToken,
        uint256 _rewardPerSecond,
        address _chef,
        uint256 _startTime
    ) public {
        rewardToken = _rewardToken;
        lpToken = _lpToken;
        rewardPerSecond = _rewardPerSecond;
        chef = _chef;
        poolInfo = PoolInfo({lastRewardTime: _startTime, accRewardPerShare: 0, totalLp: 0});

    }
    
    function setRewardPerSecond(uint256 _rewardPerSecond) external override onlyOwner {
        updatePool();

        uint256 oldRate = rewardPerSecond;
        rewardPerSecond = _rewardPerSecond;

        emit SetRewardPerSecond(oldRate, _rewardPerSecond);
    }

    function reclaimTokens(address token, uint256 amount, address payable to) public onlyOwner {
        if (token == address(0)) {
            to.transfer(amount);
        } else {
            IERC20(token).safeTransfer(to, amount);
        }
    }

    function updatePool() public returns (PoolInfo memory pool) {
        pool = poolInfo;

        if (block.timestamp > pool.lastRewardTime) {
            uint256 lpSupply = pool.totalLp;

            if (lpSupply > 0) {
                uint256 multiplier = block.timestamp.sub(pool.lastRewardTime);
                uint256 tokenReward = multiplier.mul(rewardPerSecond);
                pool.accRewardPerShare = pool.accRewardPerShare.add((tokenReward.mul(ACC_TOKEN_PRECISION).div(lpSupply)));
            }

            pool.lastRewardTime = block.timestamp;
            poolInfo = pool;
        }
    }

    function onReward(address _user, uint256 _amount) external override onlyMasterChef {
        updatePool();
        PoolInfo storage pool = poolInfo;
        UserInfo storage user = userInfo[_user];
        uint256 pendingBal;

        if (user.amount > 0) {
            pendingBal = (user.amount.mul(pool.accRewardPerShare).div(ACC_TOKEN_PRECISION)).sub(user.rewardDebt);
            uint256 rewardBal = rewardToken.balanceOf(address(this));
            if (pendingBal > rewardBal) {
                rewardToken.safeTransfer(_user, rewardBal);
            } else {
                rewardToken.safeTransfer(_user, pendingBal);
            }
        }

        pool.totalLp = pool.totalLp.add(_amount).sub(user.amount);
        user.amount = _amount;
        user.rewardDebt = user.amount.mul(pool.accRewardPerShare).div(ACC_TOKEN_PRECISION);

        emit OnReward(_user, pendingBal);
    }

    function pendingReward(address _user, uint256 _amount) external view override returns (uint256) {
        PoolInfo memory pool = poolInfo;
        UserInfo storage user = userInfo[_user];

        uint256 accRewardPerShare = pool.accRewardPerShare;
        uint256 lpSupply = pool.totalLp;

        if (block.timestamp > pool.lastRewardTime && lpSupply != 0) {
            uint256 multiplier = block.timestamp.sub(pool.lastRewardTime);
            uint256 tokenReward = multiplier.mul(rewardPerSecond);
            accRewardPerShare = accRewardPerShare.add(tokenReward.mul(ACC_TOKEN_PRECISION).div(lpSupply));
        }

        return (user.amount.mul(accRewardPerShare).div(ACC_TOKEN_PRECISION)).sub(user.rewardDebt);
    }
}