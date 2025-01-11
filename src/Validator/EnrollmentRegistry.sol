// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import "./BaseRegistry.sol";
import {BLS12381} from "../lib/bls/BLS12381.sol";
import {BLSSignatureVerifier} from "../lib/bls/BLSSignatureVerifier.sol";
import {QueryRegistry} from "./QueryRegistry.sol";

contract EnrollmentRegistry is BaseRegistry, BLSSignatureVerifier , QueryRegistry {
    using BLS12381 for BLS12381.G1Point;
    using ValidatorsLib for ValidatorsLib.ValidatorSet;

    function _registerNode(
        bytes20 nodeIdentityHash,
        address operatorAddress,
        uint32 maxGasCommitment
    ) internal {
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

    function _batchRegisterNodes(
        bytes20[] memory keyHashes,
        address operatorAddress,
        uint32 maxGasCommitment
    ) internal {
        if (operatorAddress == address(0)) {
            revert INodeRegistrationSystem.InvalidOperatorAssignment();
        }

        uint32 operatorIndex = NODES.getOrInsertAuthorizedOperator(
            operatorAddress
        );
        uint32 controllerIndex = NODES.getOrInsertController(msg.sender);

        for (uint32 i; i < keyHashes.length; i++) {
            bytes20 nodeIdentityHash = keyHashes[i];
            if (nodeIdentityHash == bytes20(0)) {
                revert INodeRegistrationSystem.InvalidNodeIdentity();
            }

            NODES.insert(
                nodeIdentityHash,
                maxGasCommitment,
                controllerIndex,
                operatorIndex
            );
            emit ConsensusNodeRegistered(nodeIdentityHash);
        }
    }


}

