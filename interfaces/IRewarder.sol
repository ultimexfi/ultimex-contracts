// SPDX-License-Identifier: MIT
pragma solidity =0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IRewarder {
    function setRewardPerSecond(uint _rewardPerSecond) external;
    function onReward(address _user, uint _amount) external;
    function pendingReward(address _user, uint _amount) external view returns (uint);
}