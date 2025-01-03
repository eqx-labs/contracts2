// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

import {BLS} from "../lib/bls/BLS.sol";
import {BLSSignatureVerifier} from "../lib/bls/BLSSignatureVerifier.sol";
import {ValidatorsLib} from "../lib/ValidatorsLib.sol";
import {IValidators} from "../interfaces/IValidators.sol";
import {IParameters} from "../interfaces/IParameters.sol";

contract Validators is IValidators, BLSSignatureVerifier, OwnableUpgradeable, UUPSUpgradeable {
    using BLS for BLS.G1Point;
    using ValidatorsLib for ValidatorsLib.ValidatorSet;

    IParameters public parameters;

    /// @notice Validators (aka Blockspace providers)
    /// @dev This struct occupies 6 storage slots.
    ValidatorsLib.ValidatorSet internal VALIDATORS;

    uint256[43] private __gap;

    // ========= EVENTS =========

    /// @notice Emitted when a validator is registered
    /// @param addressHash BLS public key hash of the validator
    event ValidatorRegistered(bytes32 indexed addressHash);

    // ========= INITIALIZER =========

    /// @notice Initializer
    /// @param _owner Address of the owner of the contract
    /// @param _parameters Address of the Bolt Parameters contract
    function initialize(address _owner, address _parameters) public initializer {
        __Ownable_init(_owner);

        parameters = IBoltParametersV1(_parameters);
    }

    function initializeV2(address _owner, address _parameters) public reinitializer(2) {
        __Ownable_init(_owner);

        parameters = IBoltParametersV1(_parameters);
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    // ========= VIEW FUNCTIONS =========

    /// @notice Get all validators in the system
    /// @dev This function should be used with caution as it can return a large amount of data.
    /// @return ValidatorState[] Array of validator info structs
    function getAllValidators() public view returns (ValidatorState[] memory) {
        ValidatorsLib._Validator[] memory _vals = VALIDATORS.getAll();
        ValidatorState[] memory vals = new ValidatorState[](_vals.length);
        for (uint256 i = 0; i < _vals.length; i++) {
            vals[i] = _getValidatorState(_vals[i]);
        }
        return vals;
    }

    /// @notice Get a validator by its BLS public key
    /// @param pubkey BLS public key of the validator
    /// @return ValidatorState struct
    function getValidatorByPubkey(
        BLS.G1Point calldata pubkey
    ) public view returns (ValidatorState memory) {
        return getValidatorByaddressHash(addressPubkey(pubkey));
    }

    /// @notice Get a validator by its BLS public key hash
    /// @param addressHash BLS public key hash of the validator
    /// @return ValidatorState struct
    function getValidatorByaddressHash(
        bytes20 addressHash
    ) public view returns (ValidatorState memory) {
        ValidatorsLib._Validator memory _val = VALIDATORS.get(addressHash);
        return _getValidatorState(_val);
    }

    // ========= REGISTRATION LOGIC =========

    /// @notice Register a single Validator and authorize a Collateral Provider and Operator for it
    /// @dev This function allows anyone to register a single Validator. We do not perform any checks.
    /// @param addressHash BLS public key hash for the Validator to be registered
    /// @param maxCommittedGasLimit The maximum gas that the Validator can commit for preconfirmations
    /// @param authorizedOperator The address of the authorized operator
    function registerValidatorUnsafe(
        bytes20 addressHash,
        uint32 maxCommittedGasLimit,
        address authorizedOperator
    ) public {
        if (!parameters.ALLOW_UNSAFE_REGISTRATION()) {
            revert UnsafeRegistrationNotAllowed();
        }

        _registerValidator(addressHash, authorizedOperator, maxCommittedGasLimit);
    }

    /// @notice Register a single Validator and authorize an Operator for it.
    /// @dev This function allows anyone to register a single Validator. We perform an important check:
    /// The owner of the Validator (controller) must have signed the message with its BLS private key.
    ///
    /// Message format: `chainId || controller || sequenceNumber`
    /// @param pubkey BLS public key for the Validator to be registered
    /// @param signature BLS signature of the registration message for the Validator
    /// @param maxCommittedGasLimit The maximum gas that the Validator can commit for preconfirmations
    /// @param authorizedOperator The address of the authorized operator
    function registerValidator(
        BLS.G1Point calldata pubkey,
        BLS.G2Point calldata signature,
        uint32 maxCommittedGasLimit,
        address authorizedOperator
    ) public {
        uint32 sequenceNumber = uint32(VALIDATORS.length() + 1);
        bytes memory message = abi.encodePacked(block.chainid, msg.sender, sequenceNumber);
        if (!_verifySignature(message, signature, pubkey)) {
            revert InvalidBLSSignature();
        }

        _registerValidator(addressPubkey(pubkey), authorizedOperator, maxCommittedGasLimit);
    }

    /// @notice Register a batch of Validators and authorize a Collateral Provider and Operator for them
    /// @dev This function allows anyone to register a list of Validators.
    /// @param pubkeys List of BLS public keys for the Validators to be registered
    /// @param signature BLS aggregated signature of the registration message for this batch of Validators
    /// @param maxCommittedGasLimit The maximum gas that the Validator can commit for preconfirmations
    /// @param authorizedOperator The address of the authorized operator
    function batchRegisterValidators(
        BLS.G1Point[] calldata pubkeys,
        BLS.G2Point calldata signature,
        uint32 maxCommittedGasLimit,
        address authorizedOperator
    ) public {
        uint32[] memory expectedValidatorSequenceNumbers = new uint32[](pubkeys.length);
        uint32 nextValidatorSequenceNumber = uint32(VALIDATORS.length() + 1);
        for (uint32 i = 0; i < pubkeys.length; i++) {
            expectedValidatorSequenceNumbers[i] = nextValidatorSequenceNumber + i;
        }

        // Reconstruct the unique message for which we expect an aggregated signature.
        // We need the msg.sender to prevent a front-running attack by an EOA that may
        // try to register the same validators
        bytes memory message = abi.encodePacked(block.chainid, msg.sender, expectedValidatorSequenceNumbers);

        // Aggregate the pubkeys into a single pubkey to verify the aggregated signature once
        BLS.G1Point memory aggPubkey = _aggregatePubkeys(pubkeys);

        if (!_verifySignature(message, signature, aggPubkey)) {
            revert InvalidBLSSignature();
        }

        bytes20[] memory addressHashes = new bytes20[](pubkeys.length);
        for (uint256 i = 0; i < pubkeys.length; i++) {
            addressHashes[i] = addressPubkey(pubkeys[i]);
        }

        _batchRegisterValidators(addressHashes, authorizedOperator, maxCommittedGasLimit);
    }

    /// @notice Register a batch of Validators and authorize a Collateral Provider and Operator for them
    /// @dev This function allows anyone to register a list of Validators.
    /// @param addressHashes List of BLS public key hashes for the Validators to be registered
    /// @param maxCommittedGasLimit The maximum gas that the Validator can commit for preconfirmations
    /// @param authorizedOperator The address of the authorized operator
    function batchRegisterValidatorsUnsafe(
        bytes20[] calldata addressHashes,
        uint32 maxCommittedGasLimit,
        address authorizedOperator
    ) public {
        if (!parameters.ALLOW_UNSAFE_REGISTRATION()) {
            revert UnsafeRegistrationNotAllowed();
        }

        _batchRegisterValidators(addressHashes, authorizedOperator, maxCommittedGasLimit);
    }

    // ========= UPDATE FUNCTIONS =========

    /// @notice Update the maximum gas limit that a validator can commit for preconfirmations
    /// @dev Only the `controller` of the validator can update this value.
    /// @param addressHash The hash of the BLS public key of the validator
    /// @param maxCommittedGasLimit The new maximum gas limit
    function updateMaxCommittedGasLimit(bytes20 addressHash, uint32 maxCommittedGasLimit) public {
        address controller = VALIDATORS.getController(addressHash);
        if (msg.sender != controller) {
            revert UnauthorizedCaller();
        }

        VALIDATORS.updateMaxCommittedGasLimit(addressHash, maxCommittedGasLimit);
    }

    // ========= HELPERS =========

    /// @notice Internal helper to register a single validator
    /// @param addressHash BLS public key hash of the validator
    /// @param authorizedOperator Address of the authorized operator
    /// @param maxCommittedGasLimit Maximum gas limit that the validator can commit for preconfirmations
    function _registerValidator(bytes20 addressHash, address authorizedOperator, uint32 maxCommittedGasLimit) internal {
        if (authorizedOperator == address(0)) {
            revert InvalidAuthorizedOperator();
        }
        if (addressHash == bytes20(0)) {
            revert InvalidPubkey();
        }

        VALIDATORS.insert(
            addressHash,
            maxCommittedGasLimit,
            VALIDATORS.getOrInsertController(msg.sender),
            VALIDATORS.getOrInsertAuthorizedOperator(authorizedOperator)
        );
        emit ValidatorRegistered(addressHash);
    }

    /// @notice Internal helper to register a batch of validators
    /// @param addressHashes List of BLS public key hashes of the validators
    /// @param authorizedOperator Address of the authorized operator
    /// @param maxCommittedGasLimit Maximum gas limit that the validators can commit for preconfirmations
    function _batchRegisterValidators(
        bytes20[] memory addressHashes,
        address authorizedOperator,
        uint32 maxCommittedGasLimit
    ) internal {
        if (authorizedOperator == address(0)) {
            revert InvalidAuthorizedOperator();
        }

        uint32 authorizedOperatorIndex = VALIDATORS.getOrInsertAuthorizedOperator(authorizedOperator);
        uint32 controllerIndex = VALIDATORS.getOrInsertController(msg.sender);
        uint256 pubkeysLength = addressHashes.length;

        for (uint32 i; i < pubkeysLength; i++) {
            bytes20 addressHash = addressHashes[i];

            if (addressHash == bytes20(0)) {
                revert InvalidPubkey();
            }

            VALIDATORS.insert(addressHash, maxCommittedGasLimit, controllerIndex, authorizedOperatorIndex);
            emit ValidatorRegistered(addressHash);
        }
    }

    /// @notice Internal helper to get the ValidatorState struct from a _Validator struct
    /// @param _val Validator struct
    /// @return ValidatorState struct
    function _getValidatorState(
        ValidatorsLib._Validator memory _val
    ) internal view returns (ValidatorState memory) {
        return ValidatorState({
            addressHash: _val.addressHash,
            maxCommittedGasLimit: _val.maxCommittedGasLimit,
            authorizedOperator: VALIDATORS.getAuthorizedOperator(_val.addressHash),
            controller: VALIDATORS.getController(_val.addressHash)
        });
    }

    function addressPubkey(
        BLS.G1Point memory pubkey
    ) public pure returns (bytes20) {
        uint256[2] memory compressedPubKey = pubkey.compress();
        bytes32 fullHash = keccak256(abi.encodePacked(compressedPubKey));
        // take the leftmost 20 bytes of the keccak256 hash
        return bytes20(uint160(uint256(fullHash)));
    }
}