// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {BLS} from "../lib/bls/BLS.sol";

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
        BLS.G1Point calldata pubkey
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
        BLS.G1Point calldata pubkey,
        BLS.G2Point calldata signature,
        uint32 maxCommittedGasLimit,
        address authorizedOperator
    ) external;

    function batchRegisterValidators(
        BLS.G1Point[] calldata pubkeys,
        BLS.G2Point calldata signature,
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
        BLS.G1Point calldata pubkey
    ) external pure returns (bytes20);
}