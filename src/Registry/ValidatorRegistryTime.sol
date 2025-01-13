// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import {ValidatorRegistryBase} from "./ValidatorRegistryBase.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";

contract ValidatorRegistryTime is ValidatorRegistryBase {
    function calculateEpochStartTime(
        uint48 epochNumber
    ) public view returns (uint48 startTimestamp) {
        return
            SYSTEM_INITIALIZATION_TIME +
            epochNumber *
            systemParameters.VALIDATOR_EPOCH_TIME();
    }

 function calculateEpochFromTimestamp(
    uint48 timestamp
) internal override view returns (uint48) {
    return (timestamp - SYSTEM_INITIALIZATION_TIME) /
        systemParameters.VALIDATOR_EPOCH_TIME();
}

    function fetchCurrentEpoch() public view returns (uint48 epochNumber) {
        return calculateEpochFromTimestamp(Time.timestamp());
    }

  
}