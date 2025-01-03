// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {BLS12381} from "../lib/bls/BLS12381.sol";

interface IValidators {
    struct ValidatorState {
        bytes20 addressHash;
        uint32 maxCommittedGasLimit;
        address authorizedOperator;
        address controller;
    }

    error InvalidBLSSignature();
    error InvalidAuthorizedOperator();
    error UnsafeRegistrationNotAllowed();
    error UnauthorizedCaller();
    error InvalidPubkey();

    function getAllValidators() external view returns (ValidatorState[] memory);

    function getValidatorByPubkey(
        BLS12381.G1Point calldata pubkey
    ) external view returns (ValidatorState memory);

    function getValidatorByaddressHash(
        bytes20 addressHash
    ) external view returns (ValidatorState memory);

    function registerValidatorUnsafe(
        bytes20 addressHash,
        uint32 maxCommittedGasLimit,
        address authorizedOperator
    ) external;

    function registerValidator(
        BLS12381.G1Point calldata pubkey,
        BLS12381.G2Point calldata signature,
        uint32 maxCommittedGasLimit,
        address authorizedOperator
    ) external;

    function batchRegisterValidators(
        BLS12381.G1Point[] calldata pubkeys,
        BLS12381.G2Point calldata signature,
        uint32 maxCommittedGasLimit,
        address authorizedOperator
    ) external;

    function batchRegisterValidatorsUnsafe(
        bytes20[] calldata addressHashes,
        uint32 maxCommittedGasLimit,
        address authorizedOperator
    ) external;

    function updateMaxCommittedGasLimit(bytes20 addressHash, uint32 maxCommittedGasLimit) external;

    function addressPubkey(
        BLS12381.G1Point calldata pubkey
    ) external pure returns (bytes20);
}