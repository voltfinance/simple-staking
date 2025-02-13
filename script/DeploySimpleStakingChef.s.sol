// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script} from "forge-std/Script.sol";
import {SimpleStakingChef} from "../src/SimpleStakingChef.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

contract DeploySimpleStakingChefScript is Script {
    function run() external returns (address, address) {
        //we need to declare the sender's private key here to sign the deploy transaction
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Deploy the upgradeable contract
        address _proxyAddress = Upgrades.deployTransparentProxy(
            "SimpleStakingChef.sol", msg.sender, abi.encodeCall(SimpleStakingChef.initialize, ())
        );

        // Get the implementation address
        address implementationAddress = Upgrades.getImplementationAddress(_proxyAddress);

        vm.stopBroadcast();

        return (implementationAddress, _proxyAddress);
    }
}
