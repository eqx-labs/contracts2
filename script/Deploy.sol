// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "../src/Middleware/ConsensusEigenLayerRestaking.sol";
import "../src/Registry/ValidatorRegistryBase.sol";
import "../src/Parameters.sol";
import "../src/Validator/BaseRegistry.sol";
import "../src/Slashing/ValidatorSlashingCore.sol";



contract Deploy is Script {
    function run() external {
        // uint256 deployerPrivateKey = vm.envUint("2cb26dcd8b503c3a708448fb27ebd2f725ef1a1305014ec0e44a9f89d204ee0e");
        // vm.startBroadcast(deployerPrivateKey);

        // Deploy Parameters contract
        Parameters parameters = new Parameters();
        console.log("Parameters contract deployed to:", address(parameters));


        // Deploy ValidatorSlashingCore contract
        ValidatorSlashingCore validatorSlashingCore = new ValidatorSlashingCore();
        console.log("ValidatorSlashingCore contract deployed to:", address(validatorSlashingCore));

        // Deploy BaseRegistry contract
        BaseRegistry baseRegistry = new BaseRegistry();
        console.log("BaseRegistry contract deployed to:", address(baseRegistry));

        // Deploy ConsensusEigenLayerRestaking contract
        ConsensusEigenLayerRestaking consensusEigenLayerRestaking = new ConsensusEigenLayerRestaking();
        console.log("ConsensusEigenLayerRestaking contract deployed to:", address(consensusEigenLayerRestaking));

        // Deploy ValidatorRegistryBase contract
        ValidatorRegistryBase validatorRegistryBase = new ValidatorRegistryBase();
        console.log("ValidatorRegistryBase contract deployed to:", address(validatorRegistryBase));


        // vm.stopBroadcast();
    }
}

