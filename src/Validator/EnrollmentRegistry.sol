// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "./BaseRegistry.sol";
import {BLS12381} from "../library/bls/BLS12381.sol";
import {BLSSignatureVerifier} from "../library/bls/BLSSignatureVerifier.sol";
import {QueryRegistry} from "./QueryRegistry.sol";
import {INodeRegistrationSystem} from "../interfaces/IValidators.sol";
import {ValidatorsLib} from "../library/ValidatorsLib.sol";

contract EnrollmentRegistry is BLSSignatureVerifier, QueryRegistry, INodeRegistrationSystem {
    using BLS12381 for BLS12381.G1Point;
    using ValidatorsLib for ValidatorsLib.ValidatorSet;

    ValidatorsLib.ValidatorSet internal NODES;

    event ConsensusNodeRegistered(bytes32 indexed nodeIdentityHash);

    function fetchAllValidatorNodes() public view returns (ValidatorNodeDetails[] memory) {
        ValidatorsLib._Validator[] memory _nodes = NODES.getAll();
        ValidatorNodeDetails[] memory nodes = new ValidatorNodeDetails[](_nodes.length);
        for (uint256 i = 0; i < _nodes.length; i++) {
            nodes[i] = _getNodeInfo(_nodes[i]);
        }
        return nodes;
    }

    function updateNodeCapacity(bytes20 nodeIdentityHash, uint32 maxGasCommitment) public {
        address controller = NODES.getController(nodeIdentityHash);
        if (msg.sender != controller) {
            revert UnauthorizedAccessAttempt();
        }

        NODES.updateMaxCommittedGasLimit(nodeIdentityHash, maxGasCommitment);
    }

    function fetchNodeByIdentityHash(bytes20 nodeIdentityHash) public view returns (ValidatorNodeDetails memory) {
        ValidatorsLib._Validator memory _node = NODES.get(nodeIdentityHash);
        return _getNodeInfo(_node);
    }

    function _getNodeInfo(ValidatorsLib._Validator memory _node)
        internal
        view
        returns (INodeRegistrationSystem.ValidatorNodeDetails memory)
    {
        return INodeRegistrationSystem.ValidatorNodeDetails({
            nodeIdentityHash: _node.pubkeyHash,
            gasCapacityLimit: _node.maxCommittedGasLimit,
            assignedOperatorAddress: NODES.getAuthorizedOperator(_node.pubkeyHash),
            controllerAddress: NODES.getController(_node.pubkeyHash)
        });
    }

    function _registerNode(bytes20 nodeIdentityHash, address operatorAddress, uint32 maxGasCommitment) internal {
        if (operatorAddress == address(0)) {
            revert INodeRegistrationSystem.InvalidOperatorAssignment();
        }
        if (nodeIdentityHash == bytes20(0)) {
            revert INodeRegistrationSystem.InvalidNodeIdentity();
        }

        NODES.insert(
            nodeIdentityHash,
            maxGasCommitment,
            NODES.getOrInsertController(msg.sender),
            NODES.getOrInsertAuthorizedOperator(operatorAddress)
        );
        emit ConsensusNodeRegistered(nodeIdentityHash);
    }

    function _batchRegisterNodes(bytes20[] memory keyHashes, address operatorAddress, uint32 maxGasCommitment)
        internal
    {
        if (operatorAddress == address(0)) {
            revert INodeRegistrationSystem.InvalidOperatorAssignment();
        }

        uint32 operatorIndex = NODES.getOrInsertAuthorizedOperator(operatorAddress);
        uint32 controllerIndex = NODES.getOrInsertController(msg.sender);

        for (uint32 i; i < keyHashes.length; i++) {
            bytes20 nodeIdentityHash = keyHashes[i];
            if (nodeIdentityHash == bytes20(0)) {
                revert INodeRegistrationSystem.InvalidNodeIdentity();
            }

            NODES.insert(nodeIdentityHash, maxGasCommitment, controllerIndex, operatorIndex);
            emit ConsensusNodeRegistered(nodeIdentityHash);
        }
    }
}
