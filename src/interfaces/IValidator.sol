// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import {BLS} from "../lib/bls/BLS.sol";

/// @title IValidator
/// @notice Interface for managing validator registrations and related functionalities.
interface IValidator {
    /// @notice Represents information about a validator.
    struct ValidatorInfo {
        bytes20 pubkeyHash;              // Hash of the validator's BLS public key.
        uint32 maxCommittedGasLimit;    // Maximum gas limit the validator is allowed to commit.
        address authorizedOperator;     // Address of the operator authorized to manage the validator.
        address controller;             // Address of the controller responsible for the validator.
    }

    // Errors
    error InvalidBLSSignature();          // Thrown when a BLS signature is invalid.
    error InvalidAuthorizedOperator();   // Thrown when the authorized operator address is invalid.
    error UnsafeRegistrationNotAllowed(); // Thrown when attempting unsafe registration without permission.
    error UnauthorizedCaller();          // Thrown when a caller is not authorized to perform the action.
    error InvalidPubkey();               // Thrown when the provided BLS public key is invalid.

    /// @notice Retrieves all registered validators.
    /// @return An array of `ValidatorInfo` containing details of all registered validators.
    function getAllValidators() external view returns (ValidatorInfo[] memory);

    /// @notice Retrieves information about a validator using its BLS public key.
    /// @param pubkey The BLS public key of the validator.
    /// @return A `ValidatorInfo` struct containing the validator's details.
    function getValidatorByPubkey(BLS.G1Point calldata pubkey) external view returns (ValidatorInfo memory);

    /// @notice Retrieves information about a validator using its public key hash.
    /// @param pubkeyHash The hash of the validator's public key.
    /// @return A `ValidatorInfo` struct containing the validator's details.
    function getValidatorByPubkeyHash(bytes20 pubkeyHash) external view returns (ValidatorInfo memory);

    /// @notice Registers a validator without verifying its BLS signature (unsafe registration).
    /// @param pubkeyHash The hash of the validator's public key.
    /// @param maxCommittedGasLimit The maximum gas limit the validator can commit.
    /// @param authorizedOperator The address authorized to manage the validator.
    function registerValidatorUnsafe(
        bytes20 pubkeyHash,
        uint32 maxCommittedGasLimit,
        address authorizedOperator
    ) external;

    /// @notice Registers a validator after verifying its BLS signature.
    /// @param pubkey The BLS public key of the validator.
    /// @param signature The BLS signature proving ownership of the public key.
    /// @param maxCommittedGasLimit The maximum gas limit the validator can commit.
    /// @param authorizedOperator The address authorized to manage the validator.
    function registerValidator(
        BLS.G1Point calldata pubkey,
        BLS.G2Point calldata signature,
        uint32 maxCommittedGasLimit,
        address authorizedOperator
    ) external;

    /// @notice Registers multiple validators in a batch, with BLS signature verification.
    /// @param pubkeys An array of BLS public keys of the validators.
    /// @param signature A single BLS signature covering all public keys.
    /// @param maxCommittedGasLimit The maximum gas limit each validator can commit.
    /// @param authorizedOperator The address authorized to manage the validators.
    function batchRegisterValidators(
        BLS.G1Point[] calldata pubkeys,
        BLS.G2Point calldata signature,
        uint32 maxCommittedGasLimit,
        address authorizedOperator
    ) external;

    /// @notice Registers multiple validators in a batch without verifying their BLS signatures (unsafe registration).
    /// @param pubkeyHashes An array of public key hashes of the validators.
    /// @param maxCommittedGasLimit The maximum gas limit each validator can commit.
    /// @param authorizedOperator The address authorized to manage the validators.
    function batchRegisterValidatorsUnsafe(
        bytes20[] calldata pubkeyHashes,
        uint32 maxCommittedGasLimit,
        address authorizedOperator
    ) external;

    /// @notice Updates the maximum committed gas limit for a specific validator.
    /// @param pubkeyHash The hash of the validator's public key.
    /// @param maxCommittedGasLimit The new maximum gas limit for the validator.
    function updateMaxCommittedGasLimit(bytes20 pubkeyHash, uint32 maxCommittedGasLimit) external;

    /// @notice Computes the hash of a BLS public key.
    /// @param pubkey The BLS public key to hash.
    /// @return The hash of the given public key as `bytes20`.
    function hashPubkey(BLS.G1Point calldata pubkey) external pure returns (bytes20);
}
