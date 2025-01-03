// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

import {BLS12381} from "./lib/bls/BLS12381.sol";
import {BLSSignatureVerifier} from "./lib/bls/BLSSignatureVerifier.sol";
import {ValidatorsLib} from "./lib/ValidatorsLib.sol";
import {IValidator} from "./interfaces/IValidator.sol";
import {ISystemParameters} from "./interfaces/IParameters.sol";

contract Validators is
    IValidator,
    BLSSignatureVerifier,
    OwnableUpgradeable,
    UUPSUpgradeable
{
    using BLS12381 for BLS12381.G1Point;
    using ValidatorsLib for ValidatorsLib.ValidatorSet;

    // Storage variables
    ISystemParameters public systemParameters;
    ValidatorsLib.ValidatorSet internal VALIDATOR_SET;
    uint256[43] private __gap;

    // Events
    event NewValidatorRegistered(bytes32 indexed pubkeyHash);

    // Custom errors
    error InvalidOperatorAddress();
    error InvalidPublicKey();
    error UnauthorizedAccess();
    error UnsafeRegistrationDisabled();
    error InvalidBLSSignatureProvided();

    // Structs
    struct ValidatorDetails {
        bytes20 pubkeyHash;
        uint32 gasLimitMax;
        address operatorAddress;
        address controllerAddress;
    }

    // Initialization functions
    function initializeSystem(
        address _owner,
        address _parameters
    ) public initializer {
        __Ownable_init(_owner);
        systemParameters = ISystemParameters(_parameters);
    }

    function upgradeSystemToV2(
        address _owner,
        address _parameters
    ) public reinitializer(2) {
        __Ownable_init(_owner);
        systemParameters = ISystemParameters(_parameters);
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    // View functions
    function retrieveAllValidators()
        public
        view
        returns (ValidatorDetails[] memory)
    {
        ValidatorsLib._Validator[] memory _validators = VALIDATOR_SET.getAll();
        ValidatorDetails[] memory validatorList = new ValidatorDetails[](
            _validators.length
        );

        for (uint256 i = 0; i < _validators.length; i++) {
            validatorList[i] = _getValidatorDetails(_validators[i]);
        }
        return validatorList;
    }

    function findValidatorByPublicKey(
        BLS12381.G1Point calldata pubkey
    ) public view returns (ValidatorDetails memory) {
        return findValidatorByHash(generatePublicKeyHash(pubkey));
    }

    function findValidatorByHash(
        bytes20 pubkeyHash
    ) public view returns (ValidatorDetails memory) {
        ValidatorsLib._Validator memory _validator = VALIDATOR_SET.get(
            pubkeyHash
        );
        return _getValidatorDetails(_validator);
    }

    // Registration functions
    function quickRegisterValidator(
        bytes20 pubkeyHash,
        uint32 gasLimitMax,
        address operatorAddress
    ) public {
        if (!systemParameters.isUnsafeRegistrationAllowed()) {
            revert UnsafeRegistrationDisabled();
        }
        _processValidatorRegistration(pubkeyHash, operatorAddress, gasLimitMax);
    }

    function secureRegisterValidator(
        BLS12381.G1Point calldata pubkey,
        BLS12381.G2Point calldata signature,
        uint32 gasLimitMax,
        address operatorAddress
    ) public {
        uint32 sequence = uint32(VALIDATOR_SET.length() + 1);
        bytes memory messageData = abi.encodePacked(
            block.chainid,
            msg.sender,
            sequence
        );

        if (!_verifySignature(messageData, signature, pubkey)) {
            revert InvalidBLSSignatureProvided();
        }

        _processValidatorRegistration(
            generatePublicKeyHash(pubkey),
            operatorAddress,
            gasLimitMax
        );
    }

    function bulkRegisterValidators(
        BLS12381.G1Point[] calldata pubkeys,
        BLS12381.G2Point calldata signature,
        uint32 gasLimitMax,
        address operatorAddress
    ) public {
        uint32[] memory sequenceNumbers = new uint32[](pubkeys.length);
        uint32 startingSequence = uint32(VALIDATOR_SET.length() + 1);

        for (uint32 i = 0; i < pubkeys.length; i++) {
            sequenceNumbers[i] = startingSequence + i;
        }

        bytes memory messageData = abi.encodePacked(
            block.chainid,
            msg.sender,
            sequenceNumbers
        );
        BLS12381.G1Point memory aggregatedKey = _aggregatePubkeys(pubkeys);

        if (!_verifySignature(messageData, signature, aggregatedKey)) {
            revert InvalidBLSSignatureProvided();
        }

        bytes20[] memory hashedKeys = new bytes20[](pubkeys.length);
        for (uint256 i = 0; i < pubkeys.length; i++) {
            hashedKeys[i] = generatePublicKeyHash(pubkeys[i]);
        }

        _processBulkValidatorRegistration(
            hashedKeys,
            operatorAddress,
            gasLimitMax
        );
    }

    function quickBulkRegisterValidators(
        bytes20[] calldata hashedKeys,
        uint32 gasLimitMax,
        address operatorAddress
    ) public {
        if (!systemParameters.isUnsafeRegistrationAllowed()) {
            revert UnsafeRegistrationDisabled();
        }
        _processBulkValidatorRegistration(
            hashedKeys,
            operatorAddress,
            gasLimitMax
        );
    }

    // Update functions
    function updateValidatorGasLimit(
        bytes20 pubkeyHash,
        uint32 newGasLimit
    ) public {
        address controller = VALIDATOR_SET.getController(pubkeyHash);
        if (msg.sender != controller) {
            revert UnauthorizedAccess();
        }
        VALIDATOR_SET.updateMaxCommittedGasLimit(pubkeyHash, newGasLimit);
    }

    // Internal helper functions
    function _processValidatorRegistration(
        bytes20 pubkeyHash,
        address operatorAddress,
        uint32 gasLimitMax
    ) internal {
        if (operatorAddress == address(0)) {
            revert InvalidOperatorAddress();
        }
        if (pubkeyHash == bytes20(0)) {
            revert InvalidPublicKey();
        }

        VALIDATOR_SET.insert(
            pubkeyHash,
            gasLimitMax,
            VALIDATOR_SET.getOrInsertController(msg.sender),
            VALIDATOR_SET.getOrInsertAuthorizedOperator(operatorAddress)
        );
        emit NewValidatorRegistered(pubkeyHash);
    }

    function _processBulkValidatorRegistration(
        bytes20[] memory hashedKeys,
        address operatorAddress,
        uint32 gasLimitMax
    ) internal {
        if (operatorAddress == address(0)) {
            revert InvalidOperatorAddress();
        }

        uint32 operatorIndex = VALIDATOR_SET.getOrInsertAuthorizedOperator(
            operatorAddress
        );
        uint32 controllerIndex = VALIDATOR_SET.getOrInsertController(
            msg.sender
        );

        for (uint32 i = 0; i < hashedKeys.length; i++) {
            if (hashedKeys[i] == bytes20(0)) {
                revert InvalidPublicKey();
            }

            VALIDATOR_SET.insert(
                hashedKeys[i],
                gasLimitMax,
                controllerIndex,
                operatorIndex
            );
            emit NewValidatorRegistered(hashedKeys[i]);
        }
    }

    function _getValidatorDetails(
        ValidatorsLib._Validator memory _validator
    ) internal view returns (ValidatorDetails memory) {
        return
            ValidatorDetails({
                pubkeyHash: _validator.pubkeyHash,
                gasLimitMax: _validator.maxCommittedGasLimit,
                operatorAddress: VALIDATOR_SET.getAuthorizedOperator(
                    _validator.pubkeyHash
                ),
                controllerAddress: VALIDATOR_SET.getController(
                    _validator.pubkeyHash
                )
            });
    }

    function generatePublicKeyHash(
        BLS12381.G1Point memory pubkey
    ) public pure returns (bytes20) {
        uint256[2] memory compressed = pubkey.compress();
        bytes32 hash = keccak256(abi.encodePacked(compressed));
        return bytes20(uint160(uint256(hash)));
    }

    function getAllValidators()
        external
        view
        override
        returns (ValidatorInfo[] memory)
    {}

    function getValidatorByPubkey(
        BLS12381.G1Point calldata pubkey
    ) external view override returns (ValidatorInfo memory) {}

    function getValidatorByPubkeyHash(
        bytes20 pubkeyHash
    ) external view override returns (ValidatorInfo memory) {}

    function registerValidatorUnsafe(
        bytes20 pubkeyHash,
        uint32 maxCommittedGasLimit,
        address authorizedOperator
    ) external override {}

    function registerValidator(
        BLS12381.G1Point calldata pubkey,
        BLS12381.G2Point calldata signature,
        uint32 maxCommittedGasLimit,
        address authorizedOperator
    ) external override {}

    function batchRegisterValidators(
        BLS12381.G1Point[] calldata pubkeys,
        BLS12381.G2Point calldata signature,
        uint32 maxCommittedGasLimit,
        address authorizedOperator
    ) external override {}

    function batchRegisterValidatorsUnsafe(
        bytes20[] calldata pubkeyHashes,
        uint32 maxCommittedGasLimit,
        address authorizedOperator
    ) external override {}

    function updateMaxCommittedGasLimit(
        bytes20 pubkeyHash,
        uint32 maxCommittedGasLimit
    ) external override {}

    function hashPubkey(
        BLS12381.G1Point calldata pubkey
    ) external pure override returns (bytes20) {}
}