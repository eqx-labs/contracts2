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

    function fetchAllValidatorNodes() 
        external 
        view 
        returns (ValidatorNodeDetails[] memory);

    function fetchNodeByPublicKey(
        BLS12381.G1Point calldata nodePublicKey
    ) external view returns (ValidatorNodeDetails memory);

    function fetchNodeByIdentityHash(
        bytes20 nodeIdentityHash
    ) external view returns (ValidatorNodeDetails memory);

    function enrollNodeWithoutVerification(
        bytes20 nodeIdentityHash,
        uint32 gasCapacityLimit,
        address assignedOperatorAddress
    ) external;

    function enrollNodeWithVerification(
        BLS12381.G1Point calldata nodePublicKey,
        BLS12381.G2Point calldata cryptographicSignature,
        uint32 gasCapacityLimit,
        address assignedOperatorAddress
    ) external;

    function bulkEnrollNodesWithVerification(
        BLS12381.G1Point[] calldata nodePublicKeys,
        BLS12381.G2Point calldata cryptographicSignature,
        uint32 gasCapacityLimit,
        address assignedOperatorAddress
    ) external;

    function bulkEnrollNodesWithoutVerification(
        bytes20[] calldata nodeIdentityHashes,
        uint32 gasCapacityLimit,
        address assignedOperatorAddress
    ) external;

    // function updateNodeCapacity(
    //     bytes20 nodeIdentityHash, 
    //     uint32 gasCapacityLimit
    // ) external;

}