// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ISimpleRewarderPerSec} from "./ISimpleRewarderPerSec.sol";

interface ISimpleStakingChef {
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
    }

    struct PoolInfo {
        IERC20 lpToken; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. VOLT to distribute per block.
        uint256 lastRewardTimestamp; // Last block number that VOLT distribution occurs.
        uint256 accVoltPerShare; // Accumulated VOLT per share, times 1e12. See below.
    }

    function poolInfo(uint256 pid) external view returns (ISimpleStakingChef.PoolInfo memory);

    function totalAllocPoint() external view returns (uint256);

    function deposit(uint256 _pid, uint256 _amount) external;

    function add(uint256 _allocPoint, IERC20 _lpToken, ISimpleRewarderPerSec _rewarder) external;
}
