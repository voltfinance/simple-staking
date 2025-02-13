// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.25;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ISimpleStakingChef} from "../interfaces/ISimpleStakingChef.sol";

/**
 * This is a sample contract to be used in the MasterChefVolt contract for partners to reward
 * stakers with their native token alongside VOLT.
 *
 * It assumes no minting rights, so requires a set amount of YOUR_TOKEN to be transferred to this contract prior.
 * E.g. say you've allocated 100,000 XYZ to the VOLT-XYZ farm over 30 days. Then you would need to transfer
 * 100,000 XYZ and set the block reward accordingly so it's fully distributed after 30 days.
 *
 */
contract SimpleRewarderPerSec is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable REWARD_TOKEN;
    IERC20 public immutable LP_TOKEN;
    bool public immutable IS_NATIVE;
    ISimpleStakingChef public immutable MCJ;

    /// @notice Info of each MCJ user.
    /// `amount` LP token amount the user has provided.
    /// `rewardDebt` The amount of YOUR_TOKEN entitled to the user.
    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
        uint256 unpaidRewards;
    }

    /// @notice Info of each MCJ poolInfo.
    /// `accTokenPerShare` Amount of YOUR_TOKEN each LP token is worth.
    /// `lastRewardTimestamp` The last timestamp YOUR_TOKEN was rewarded to the poolInfo.
    struct PoolInfo {
        uint256 accTokenPerShare;
        uint256 lastRewardTimestamp;
    }

    /// @notice Info of the poolInfo.
    PoolInfo public poolInfo;
    /// @notice Info of each user that stakes LP tokens.
    mapping(address => UserInfo) public userInfo;

    uint256 public tokenPerSec;
    uint256 private constant ACC_TOKEN_PRECISION = 1e12;

    event OnReward(address indexed user, uint256 amount);
    event RewardRateUpdated(uint256 oldRate, uint256 newRate);

    error OnlyMCJ();
    error InvalidRewardToken();
    error InvalidLPToken();
    error InvalidMCJ();
    error TransferFailed();

    modifier onlyMCJ() {
        if (msg.sender != address(MCJ)) revert OnlyMCJ();
        _;
    }

    constructor(IERC20 _rewardToken, IERC20 _lpToken, uint256 _tokenPerSec, ISimpleStakingChef _mcj, bool _isNative)
        Ownable(msg.sender)
    {
        if (address(_rewardToken) == address(0)) revert InvalidRewardToken();
        if (address(_lpToken) == address(0)) revert InvalidLPToken();
        if (address(_mcj) == address(0)) revert InvalidMCJ();

        REWARD_TOKEN = _rewardToken;
        LP_TOKEN = _lpToken;
        tokenPerSec = _tokenPerSec;
        MCJ = _mcj;
        IS_NATIVE = _isNative;
        poolInfo = PoolInfo({lastRewardTimestamp: block.timestamp, accTokenPerShare: 0});
    }

    /// @notice Update reward variables of the given poolInfo.
    /// @return pool Returns the pool that was updated.
    function updatePool() public returns (PoolInfo memory pool) {
        pool = poolInfo;

        if (block.timestamp > pool.lastRewardTimestamp) {
            uint256 lpSupply = LP_TOKEN.balanceOf(address(MCJ));

            if (lpSupply > 0) {
                uint256 timeElapsed = block.timestamp - pool.lastRewardTimestamp;
                uint256 tokenReward = timeElapsed * tokenPerSec;
                pool.accTokenPerShare = pool.accTokenPerShare + (tokenReward * ACC_TOKEN_PRECISION / lpSupply);
            }

            pool.lastRewardTimestamp = block.timestamp;
            poolInfo = pool;
        }
    }

    /// @notice Sets the distribution reward rate. This will also update the poolInfo.
    /// @param _tokenPerSec The number of tokens to distribute per second
    function setRewardRate(uint256 _tokenPerSec) external onlyOwner {
        updatePool();

        uint256 oldRate = tokenPerSec;
        tokenPerSec = _tokenPerSec;

        emit RewardRateUpdated(oldRate, _tokenPerSec);
    }

    /// @notice Function called by MasterChefVolt whenever staker claims VOLT harvest. Allows staker to also receive a 2nd reward token.
    /// @param _user Address of user
    /// @param _lpAmount Number of LP tokens the user has
    function onVoltReward(address _user, uint256 _lpAmount) external onlyMCJ nonReentrant {
        updatePool();
        PoolInfo memory pool = poolInfo;
        UserInfo storage user = userInfo[_user];
        uint256 pending;
        if (user.amount > 0) {
            pending = (user.amount * pool.accTokenPerShare / ACC_TOKEN_PRECISION) - user.rewardDebt + user.unpaidRewards;

            if (IS_NATIVE) {
                uint256 bal = address(this).balance;
                if (pending > bal) {
                    (bool success,) = _user.call{value: bal}("");
                    if (!success) revert TransferFailed();
                    user.unpaidRewards = pending - bal;
                } else {
                    (bool success,) = _user.call{value: pending}("");
                    if (!success) revert TransferFailed();
                    user.unpaidRewards = 0;
                }
            } else {
                uint256 bal = REWARD_TOKEN.balanceOf(address(this));
                if (pending > bal) {
                    REWARD_TOKEN.safeTransfer(_user, bal);
                    user.unpaidRewards = pending - bal;
                } else {
                    REWARD_TOKEN.safeTransfer(_user, pending);
                    user.unpaidRewards = 0;
                }
            }
        }

        user.amount = _lpAmount;
        user.rewardDebt = user.amount * pool.accTokenPerShare / ACC_TOKEN_PRECISION;
        emit OnReward(_user, pending - user.unpaidRewards);
    }

    /// @notice View function to see pending tokens
    /// @param _user Address of user.
    /// @return pending reward for a given user.
    function pendingTokens(address _user) external view returns (uint256 pending) {
        PoolInfo memory pool = poolInfo;
        UserInfo storage user = userInfo[_user];

        uint256 accTokenPerShare = pool.accTokenPerShare;
        uint256 lpSupply = LP_TOKEN.balanceOf(address(MCJ));

        if (block.timestamp > pool.lastRewardTimestamp && lpSupply != 0) {
            uint256 timeElapsed = block.timestamp - pool.lastRewardTimestamp;
            uint256 tokenReward = timeElapsed * tokenPerSec;
            accTokenPerShare = accTokenPerShare + (tokenReward * ACC_TOKEN_PRECISION / lpSupply);
        }

        pending = (user.amount * accTokenPerShare / ACC_TOKEN_PRECISION) - user.rewardDebt + user.unpaidRewards;
    }

    /// @notice In case rewarder is stopped before emissions finished, this function allows
    /// withdrawal of remaining tokens.
    function emergencyWithdraw() public onlyOwner {
        if (IS_NATIVE) {
            (bool success,) = msg.sender.call{value: address(this).balance}("");
            if (!success) revert TransferFailed();
        } else {
            REWARD_TOKEN.safeTransfer(address(msg.sender), REWARD_TOKEN.balanceOf(address(this)));
        }
    }

    /// @notice View function to see balance of reward token.
    function balance() external view returns (uint256) {
        if (IS_NATIVE) {
            return address(this).balance;
        } else {
            return REWARD_TOKEN.balanceOf(address(this));
        }
    }

    /// @notice payable function needed to receive AVAX
    receive() external payable {}
}
