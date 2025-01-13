// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

interface IValidatorNodeTypes {
    struct ValidatorNodeDetails {
        bytes20 nodeIdentityHash;
        uint32 gasCapacityLimit;
        address assignedOperatorAddress;
        address controllerAddress;
    }
}