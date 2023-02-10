// SPDX-License-Identifier: MIT

pragma solidity =0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Vesting is Ownable {
    using SafeMath for uint256;

    address public ulti;
    address public recipient;
    uint256 public vestingAmount;
    uint256 public begin;
    uint256 public cliff;
    uint256 public end;

    uint256 public lastUpdate;

    constructor(
        address _ulti,
        address _recipient,
        uint256 _vestingAmount,
        uint256 _begin,
        uint256 _cliff,
        uint256 _end
    ) public {
        require(_begin >= block.timestamp, "Vesting: BAD BEGIN");
        require(_cliff >= _begin, "Vesting: BAD CLIFF");
        require(_end > _cliff, "Vesting: BAD END");

        ulti = _ulti;
        recipient = _recipient;
        vestingAmount = _vestingAmount;
        begin = _begin;
        cliff = _cliff;
        end = _end;

        lastUpdate = _begin;
    }

    function setRecipient(address _recipient) external onlyOwner {
        recipient = _recipient;
    }

    function claim() external {
        require(block.timestamp >= cliff, "Vesting: NOT NOW");
        uint256 amount;
        uint256 balance = IERC20(ulti).balanceOf(address(this));

        amount = vestingAmount.mul(block.timestamp - lastUpdate).div(
            end - begin
        );

        if (amount > balance) {
            amount = balance;
            lastUpdate =
                lastUpdate +
                balance.mul(end - begin).div(vestingAmount);
        } else {
            lastUpdate = block.timestamp;
        }

        IERC20(ulti).transfer(recipient, amount);
    }
}
