// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ISimpleRewarderPerSec} from "./interfaces/ISimpleRewarderPerSec.sol";

/// @notice The (older) MasterChefVoltV2 contract gives out a constant number of VOLT tokens per block.
/// It is the only address with minting rights for VOLT.
/// The idea for this MasterChefVoltV3 (MCJV3) contract is therefore to be the owner of a dummy token
/// that is deposited into the MasterChefVoltV2 (MCJV2) contract.
/// The allocation point for this pool on MCJV3 is the total allocation point for all pools that receive double incentives.
contract SimpleStakingChef is OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @notice Info of each MCJV3 user.
    /// `amount` LP token amount the user has provided.
    /// `rewardDebt` The amount of VOLT entitled to the user.
    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
    }

    /// @notice Info of each MCJV3 pool.
    /// `allocPoint` The amount of allocation points assigned to the pool.
    /// Also known as the amount of VOLT to distribute per block.
    struct PoolInfo {
        IERC20 lpToken;
        uint256 accVoltPerShare;
        uint256 lastRewardTimestamp;
        uint256 allocPoint;
        ISimpleRewarderPerSec rewarder;
    }

    PoolInfo[] public poolInfo;
    // Set of all LP tokens that have been added as pools
    EnumerableSet.AddressSet private lpTokens;
    /// @notice Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    uint256 private constant ACC_TOKEN_PRECISION = 1e18;

    event Add(uint256 indexed pid, uint256 allocPoint, IERC20 indexed lpToken, ISimpleRewarderPerSec indexed rewarder);
    event Set(uint256 indexed pid, uint256 allocPoint, ISimpleRewarderPerSec indexed rewarder, bool overwrite);
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event UpdatePool(uint256 indexed pid, uint256 lastRewardTimestamp, uint256 lpSupply, uint256 accVoltPerShare);
    event Harvest(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event Init();

    error LPAlreadyAdded();

    function initialize() external initializer {
        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();
    }

    /// @notice Returns the number of MCJV3 pools.
    function poolLength() external view returns (uint256 pools) {
        pools = poolInfo.length;
    }

    /// @notice Add a new LP to the pool. Can only be called by the owner.
    /// DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    /// @param _allocPoint AP of the new pool.
    /// @param _lpToken Address of the LP ERC-20 token.
    /// @param _rewarder Address of the rewarder delegate.
    function add(uint256 _allocPoint, IERC20 _lpToken, ISimpleRewarderPerSec _rewarder) external onlyOwner {
        if (lpTokens.contains(address(_lpToken))) revert LPAlreadyAdded();
        // Sanity check to ensure _lpToken is an ERC20 token
        _lpToken.balanceOf(address(this));
        // Sanity check if we add a rewarder
        if (address(_rewarder) != address(0)) {
            _rewarder.onVoltReward(address(0), 0);
        }

        uint256 lastRewardTimestamp = block.timestamp;

        poolInfo.push(
            PoolInfo({
                lpToken: _lpToken,
                allocPoint: _allocPoint,
                lastRewardTimestamp: lastRewardTimestamp,
                accVoltPerShare: 0,
                rewarder: _rewarder
            })
        );
        lpTokens.add(address(_lpToken));
        emit Add(poolInfo.length - 1, _allocPoint, _lpToken, _rewarder);
    }

    /// @notice Update the given pool's VOLT allocation point and `IRewarder` contract. Can only be called by the owner.
    /// @param _pid The index of the pool. See `poolInfo`.
    /// @param _allocPoint New AP of the pool.
    /// @param _rewarder Address of the rewarder delegate.
    /// @param overwrite True if _rewarder should be `set`. Otherwise `_rewarder` is ignored.
    function set(uint256 _pid, uint256 _allocPoint, ISimpleRewarderPerSec _rewarder, bool overwrite)
        external
        onlyOwner
    {
        PoolInfo memory pool = poolInfo[_pid];
        pool.allocPoint = _allocPoint;
        if (overwrite) {
            _rewarder.onVoltReward(address(0), 0); // sanity check
            pool.rewarder = _rewarder;
        }
        poolInfo[_pid] = pool;
        emit Set(_pid, _allocPoint, overwrite ? _rewarder : pool.rewarder, overwrite);
    }

    /// @notice View function to see pending VOLT on frontend.
    /// @param _pid The index of the pool. See `poolInfo`.
    /// @param _user Address of user.
    /// @return pendingVolt VOLT reward for a given user.
    //          bonusTokenAddress The address of the bonus reward.
    //          bonusTokenSymbol The symbol of the bonus token.
    //          pendingBonusToken The amount of bonus rewards pending.
    function pendingTokens(uint256 _pid, address _user)
        external
        view
        returns (
            uint256 pendingVolt,
            address bonusTokenAddress,
            string memory bonusTokenSymbol,
            uint256 pendingBonusToken
        )
    {
        PoolInfo memory pool = poolInfo[_pid];
        // If it's a double reward farm, we return info about the bonus token
        if (address(pool.rewarder) != address(0)) {
            bonusTokenAddress = address(pool.rewarder.rewardToken());
            bonusTokenSymbol = IERC20Metadata(bonusTokenAddress).symbol();
            pendingBonusToken = pool.rewarder.pendingTokens(_user);
        }
    }

    /// @notice Update reward variables of the given pool.
    /// @param pid The index of the pool. See `poolInfo`.
    function updatePool(uint256 pid) public {
        PoolInfo memory pool = poolInfo[pid];
        if (block.timestamp > pool.lastRewardTimestamp) {
            uint256 lpSupply = pool.lpToken.balanceOf(address(this));
            pool.lastRewardTimestamp = block.timestamp;
            poolInfo[pid] = pool;
            emit UpdatePool(pid, pool.lastRewardTimestamp, lpSupply, pool.accVoltPerShare);
        }
    }

    /// @notice Deposit LP tokens to MCJV3 for VOLT allocation.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param amount LP token amount to deposit.
    function deposit(uint256 pid, uint256 amount) external nonReentrant {
        updatePool(pid);
        PoolInfo memory pool = poolInfo[pid];
        UserInfo storage user = userInfo[pid][msg.sender];

        uint256 balanceBefore = pool.lpToken.balanceOf(address(this));
        pool.lpToken.safeTransferFrom(msg.sender, address(this), amount);
        uint256 receivedAmount = pool.lpToken.balanceOf(address(this)) - balanceBefore;

        // Effects
        user.amount = user.amount + receivedAmount;
        user.rewardDebt = user.amount * pool.accVoltPerShare / ACC_TOKEN_PRECISION;

        // Interactions
        ISimpleRewarderPerSec _rewarder = pool.rewarder;
        if (address(_rewarder) != address(0)) {
            _rewarder.onVoltReward(msg.sender, user.amount);
        }

        emit Deposit(msg.sender, pid, receivedAmount);
    }

    /// @notice Withdraw LP tokens from MCJV3.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param amount LP token amount to withdraw.
    function withdraw(uint256 pid, uint256 amount) external nonReentrant {
        updatePool(pid);
        PoolInfo memory pool = poolInfo[pid];
        UserInfo storage user = userInfo[pid][msg.sender];

        // Effects
        user.amount = user.amount - amount;
        user.rewardDebt = user.amount * pool.accVoltPerShare / ACC_TOKEN_PRECISION;

        // Interactions
        ISimpleRewarderPerSec _rewarder = pool.rewarder;
        if (address(_rewarder) != address(0)) {
            _rewarder.onVoltReward(msg.sender, user.amount);
        }

        pool.lpToken.safeTransfer(msg.sender, amount);

        emit Withdraw(msg.sender, pid, amount);
    }

    /// @notice Withdraw without caring about rewards. EMERGENCY ONLY.
    /// @param pid The index of the pool. See `poolInfo`.
    function emergencyWithdraw(uint256 pid) external nonReentrant {
        PoolInfo memory pool = poolInfo[pid];
        UserInfo storage user = userInfo[pid][msg.sender];
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;

        ISimpleRewarderPerSec _rewarder = pool.rewarder;
        if (address(_rewarder) != address(0)) {
            _rewarder.onVoltReward(msg.sender, 0);
        }

        // Note: transfer can fail or succeed if `amount` is zero.
        pool.lpToken.safeTransfer(msg.sender, amount);
        emit EmergencyWithdraw(msg.sender, pid, amount);
    }
}
