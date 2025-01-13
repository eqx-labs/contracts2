// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import {ISignatureUtils} from "@eigenlayer/src/contracts/interfaces/ISignatureUtils.sol";
import {IAVSDirectory} from "@eigenlayer/src/contracts/interfaces/IAVSDirectory.sol";
import {DelegationManagerStorage} from "@eigenlayer/src/contracts/core/DelegationManagerStorage.sol";
import {IValidatorRegistrySystem} from "../interfaces/IRegistry.sol";

library OperatorManager {
    error ParticipantExists();
    error ParticipantNotFound();
    error NodeProviderNotActive();
    error OperationForbidden();

    function enrollValidatorNode(
        IValidatorRegistrySystem registry,
        DelegationManagerStorage delegationManager,
        IAVSDirectory avsDirectory,
        address operator,
        string calldata serviceEndpoint,
        ISignatureUtils.SignatureWithSaltAndExpiry calldata providerSignature
    ) internal {
        if (registry.validateNodeRegistration(operator)) {
            revert ParticipantExists();
        }

        if (!delegationManager.isOperator(operator)) {
            revert NodeProviderNotActive();
        }

        avsDirectory.registerOperatorToAVS(operator, providerSignature);
        registry.enrollValidatorNode(operator, serviceEndpoint);
    }

    function removeValidatorNode(
        IValidatorRegistrySystem registry,
        IAVSDirectory avsDirectory,
        address operator
    ) internal {
        if (!registry.validateNodeRegistration(operator)) {
            revert ParticipantNotFound();
        }

        avsDirectory.deregisterOperatorFromAVS(operator);
        registry.removeValidatorNode(operator);
    }
}