// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script, console2} from "forge-std/Script.sol";
import {DeploySimpleStakingChefScript} from "./DeploySimpleStakingChef.s.sol";
import {DeploySimpleRewarderPerSecScript} from "./DeploySimpleRewarderPerSec.s.sol";
import {ISimpleStakingChef} from "../src/interfaces/ISimpleStakingChef.sol";
import {ISimpleRewarderPerSec} from "../src/interfaces/ISimpleRewarderPerSec.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DeployScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Get parameters from environment
        address lpToken = vm.envAddress("LP_TOKEN");
        address rewardToken = vm.envAddress("REWARD_TOKEN");
        uint256 tokenPerSec = vm.envUint("TOKEN_PER_SEC");

        // Deploy staking chef first
        DeploySimpleStakingChefScript stakingDeployer = new DeploySimpleStakingChefScript();
        (, address stakingChefProxy) = stakingDeployer.run();

        // Deploy rewarder with staking chef address
        DeploySimpleRewarderPerSecScript rewarderDeployer = new DeploySimpleRewarderPerSecScript();
        (, address rewarderProxy) = rewarderDeployer.run(lpToken, rewardToken, stakingChefProxy, tokenPerSec);

        // Set up the pool in staking chef
        ISimpleStakingChef(stakingChefProxy).add(0, IERC20(lpToken), ISimpleRewarderPerSec(rewarderProxy));

        vm.stopBroadcast();

        console2.log("Deployment Addresses:");
        console2.log("SimpleStakingChef Proxy:", stakingChefProxy);
        console2.log("SimpleRewarderPerSec Proxy:", rewarderProxy);
    }
}
