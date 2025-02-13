// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script, console2} from "forge-std/Script.sol";
import {DeploySimpleStakingChefScript} from "./DeploySimpleStakingChef.s.sol";
import {DeploySimpleRewarderPerSecScript} from "./DeploySimpleRewarderPerSec.s.sol";
import {ISimpleStakingChef} from "../src/interfaces/ISimpleStakingChef.sol";
import {ISimpleRewarderPerSec} from "../src/interfaces/ISimpleRewarderPerSec.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DeployScript is Script {
    string public forkUrl;
    uint256 public fork;

    function run() public {
        forkUrl = vm.envString("TEST_RPC_URL");
        fork = vm.createFork(forkUrl);
        vm.selectFork(fork);

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Get parameters from environment
        address lpToken = vm.envAddress("LP_TOKEN");
        address rewardToken = vm.envAddress("REWARD_TOKEN");
        uint256 tokenPerSec = vm.envUint("TOKEN_PER_SEC");

        // Deploy staking chef first
        DeploySimpleStakingChefScript stakingDeployer = new DeploySimpleStakingChefScript();
        (address chefImplementation, address stakingChefProxy) = stakingDeployer.run();
        console2.log("SimpleStakingChef Proxy:", stakingChefProxy);
        console2.log("SimpleStakingChef Implementation:", chefImplementation);

        // Deploy rewarder with staking chef address
        DeploySimpleRewarderPerSecScript rewarderDeployer = new DeploySimpleRewarderPerSecScript();
        address rewarderImplementation = rewarderDeployer.run(lpToken, rewardToken, stakingChefProxy, tokenPerSec);
        console2.log("SimpleRewarderPerSec Implementation:", rewarderImplementation);

        // Set up the pool in staking chef
        ISimpleStakingChef(stakingChefProxy).add(0, IERC20(lpToken), ISimpleRewarderPerSec(rewarderImplementation));

        vm.stopBroadcast();
    }
}
