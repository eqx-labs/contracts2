// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {ValidatorRegistry} from "../src/ValidatorRegistry.sol";

contract ValidatorRegistryScript is Script {
    ValidatorRegistry public counter;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        counter = new ValidatorRegistry();

        vm.stopBroadcast();
    }
}
