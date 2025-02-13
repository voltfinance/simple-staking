// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script} from "forge-std/Script.sol";
import {SimpleRewarderPerSec} from "../src/rewarders/SimpleRewarderPerSec.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ISimpleStakingChef} from "../src/interfaces/ISimpleStakingChef.sol";

contract DeploySimpleRewarderPerSecScript is Script {
    function run(address lpToken, address rewardToken, address mcj, uint256 tokenPerSec)
        public
        returns (address implementation)
    {
        implementation = address(
            new SimpleRewarderPerSec(IERC20(rewardToken), IERC20(lpToken), tokenPerSec, ISimpleStakingChef(mcj), false)
        );

        return implementation;
    }
}
