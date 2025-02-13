// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script} from "forge-std/Script.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {SimpleStakingChef} from "../src/SimpleStakingChef.sol";

contract DeploySimpleStakingChefScript is Script {
    function run() public returns (address implementation, address proxy) {
        // Deploy the upgradeable contract
        proxy = Upgrades.deployTransparentProxy(
            "SimpleStakingChef.sol", msg.sender, abi.encodeCall(SimpleStakingChef.initialize, ())
        );

        implementation = Upgrades.getImplementationAddress(proxy);

        return (implementation, proxy);
    }
}
