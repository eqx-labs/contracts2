// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {BLS12381} from "../library/bls/BLS12381.sol";
import {BLSSignatureVerifier} from "../library/bls/BLSSignatureVerifier.sol";
import {ValidatorsLib} from "../library/ValidatorsLib.sol";
import {INodeRegistrationSystem} from "../interfaces/IValidators.sol";
import {IParameters} from "../interfaces/IParameters.sol";
import {EnrollmentRegistry} from "./EnrollmentRegistry.sol";


contract NodeRegistry is 
EnrollmentRegistry,
INodeRegistrationSystem

{
    using BLS12381 for BLS12381.G1Point;
    using ValidatorsLib for ValidatorsLib.ValidatorSet;


    uint256 public validatorCount;
    uint256[42] private __gap;



    // Query Functions
    function fetchAllValidatorNodes()
        public
        view
        returns (ValidatorNodeDetails[] memory)
    {
             ValidatorsLib._Validator[] memory _nodes = NODES.getAll();
        ValidatorNodeDetails[] memory nodes = new ValidatorNodeDetails[](
            _nodes.length
        );
        for (uint256 i = 0; i < _nodes.length; i++) {
            nodes[i] = _getNodeInfo(_nodes[i]);
        }
        return nodes;

    }

    function fetchNodeByPublicKey(
        BLS12381.G1Point calldata pubkey
    ) public view returns (ValidatorNodeDetails memory) {
        return fetchNodeByIdentityHash(computeNodeIdentityHash(pubkey));
    }

    function fetchNodeByIdentityHash(
        bytes20 nodeIdentityHash
    ) public view returns (ValidatorNodeDetails memory) {
        ValidatorsLib._Validator memory _node = NODES.get(nodeIdentityHash);
        return _getNodeInfo(_node);
    }

    // Enrollment Functions
    function enrollNodeWithoutVerification(
        bytes20 nodeIdentityHash,
        uint32 maxGasCommitment,
        address operatorAddress
    ) public {
        if (!protocolParameters.SKIP_SIGNATURE_VALIDATION()) {
            revert SecureRegistrationRequired();
        }

        _registerNode(nodeIdentityHash, operatorAddress, maxGasCommitment);
    }

    function enrollNodeWithVerification(
        BLS12381.G1Point calldata pubkey,
        BLS12381.G2Point calldata signature,
        uint32 maxGasCommitment,
        address operatorAddress
    ) public {
        uint32 sequenceNumber = uint32(validatorCount + 1);
        
        bytes memory message = abi.encodePacked(
            block.chainid,
            msg.sender,
            sequenceNumber
        );
        
        if (!_verifySignature(message, signature, pubkey)) {
            revert SignatureVerificationFailed();
        }

        _registerNode(
            computeNodeIdentityHash(pubkey),
            operatorAddress,
            maxGasCommitment
        );
    }

    function bulkEnrollNodesWithVerification(
        BLS12381.G1Point[] calldata pubkeys,
        BLS12381.G2Point calldata signature,
        uint32 maxGasCommitment,
        address operatorAddress
    ) public {
        uint32 nextSequenceNumber = uint32(validatorCount + 1);
        
        uint32[] memory sequenceNumbers = new uint32[](pubkeys.length);
        for (uint32 i = 0; i < pubkeys.length; i++) {
            sequenceNumbers[i] = nextSequenceNumber + i;
        }

        bytes memory message = abi.encodePacked(
            block.chainid,
            msg.sender,
            sequenceNumbers
        );
        
        BLS12381.G1Point memory aggregatedPubkey = _aggregatePubkeys(pubkeys);

        if (!_verifySignature(message, signature, aggregatedPubkey)) {
            revert SignatureVerificationFailed();
        }

        bytes20[] memory keyHashes = new bytes20[](pubkeys.length);
        for (uint256 i = 0; i < pubkeys.length; i++) {
            keyHashes[i] = computeNodeIdentityHash(pubkeys[i]);
        }

        _batchRegisterNodes(keyHashes, operatorAddress, maxGasCommitment);
    }

    function bulkEnrollNodesWithoutVerification(
        bytes20[] calldata keyHashes,
        uint32 maxGasCommitment,
        address operatorAddress
    ) public {
        if (!protocolParameters.SKIP_SIGNATURE_VALIDATION()) {
            revert SecureRegistrationRequired();
        }

        _batchRegisterNodes(keyHashes, operatorAddress, maxGasCommitment);
    }




}