// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script} from "forge-std/Script.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {SimpleRewarderPerSec} from "../src/rewarders/SimpleRewarderPerSec.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ISimpleStakingChef} from "../src/interfaces/ISimpleStakingChef.sol";
import {Options} from "openzeppelin-foundry-upgrades/Options.sol";

contract DeploySimpleRewarderPerSecScript is Script {
    function run(address lpToken, address rewardToken, address mcj, uint256 tokenPerSec)
        external
        returns (address implementation, address proxy)
    {
        bytes memory constructorArgs = abi.encode(
            IERC20(rewardToken),
            IERC20(lpToken),
            tokenPerSec,
            ISimpleStakingChef(mcj),
            false // isNative
        );

        Options memory opts;
        opts.constructorData = constructorArgs;
        opts.unsafeSkipProxyAdminCheck = true;
        opts.unsafeSkipAllChecks = true;

        proxy = Upgrades.deployTransparentProxy(
            "SimpleRewarderPerSec.sol", msg.sender, abi.encodeCall(SimpleRewarderPerSec.initialize, ()), opts
        );

        address implementationAddress = Upgrades.getImplementationAddress(proxy);

        return (implementationAddress, proxy);
    }
}
