// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/Parameters.sol";
import "../src/Validator/BaseRegistry.sol";
import "../src/Registry/ValidatorRegistryBase.sol";
import "../src/Middleware/Middleware.sol";
import "../src/Slashing/ValidatorSlashingCore.sol";

contract Deploy is Script {
    function run() external {
        vm.startBroadcast();

        Parameters parameter = new Parameters();
        console.log("Parameter deployed at:", address(parameter));

        BaseRegistry baseRegistry = new BaseRegistry();
        console.log("BaseRegistry deployed at:", address(baseRegistry));

        ValidatorRegistryBase validatorRegistryBase = new ValidatorRegistryBase();
        console.log("ValidatorRegistryBase deployed at:", address(validatorRegistryBase));

        ConsensusEigenLayerMiddleware middleware = new ConsensusEigenLayerMiddleware();
        console.log("Middleware deployed at:", address(middleware));

        ValidatorSlashingCore validatorSlashingCore = new ValidatorSlashingCore();
        console.log("ValidatorSlashingCore deployed at:", address(validatorSlashingCore));

        vm.stopBroadcast();
    }
}