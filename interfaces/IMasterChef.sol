// SPDX-License-Identifier: MIT
pragma experimental ABIEncoderV2;
pragma solidity =0.6.12;

import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

interface IMasterChef {
    using SafeERC20 for IERC20;
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
    }

    function userInfo(uint256 pid, address user) external view returns (IMasterChef.UserInfo memory);

    function poolInfo(uint256 pid) external view returns (IMasterChef.PoolInfo memory);

    function totalAllocPoint() external view returns (uint256);

    function burnPercent() external view returns (uint256);

    function ultiPerSecond() external view returns (uint256);

    function deposit(uint256 _pid, uint256 _amount) external;

    function withdraw(uint256 _pid, uint256 _amount) external;

    function emergencyWithdraw(uint256 _pid) external;
}