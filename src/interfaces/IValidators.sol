// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import {BLS12381} from "../lib/bls/BLS12381.sol";

interface INodeRegistrationSystem {
    struct ValidatorNodeDetails {
        bytes20 nodeIdentityHash;
        uint32 gasCapacityLimit;
        address assignedOperatorAddress;
        address controllerAddress;
    }

    error SignatureVerificationFailed();
    error InvalidOperatorAssignment();
    error SecureRegistrationRequired();

    error InvalidNodeIdentity();


    function fetchNodeByIdentityHash(
        bytes20 nodeIdentityHash
    ) external view returns (ValidatorNodeDetails memory);

  

}