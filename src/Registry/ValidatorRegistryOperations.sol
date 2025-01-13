// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ValidatorRegistryTime} from "./ValidatorRegistryTime.sol";
import {EnumerableMap} from "../library/EnumerableMap.sol";
import {OperatorMapWithTime} from "../library/OperatorMapWithTime.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";

contract ValidatorRegistryOperations is ValidatorRegistryTime {
    using EnumerableMap for EnumerableMap.OperatorMap;
    using OperatorMapWithTime for EnumerableMap.OperatorMap;

    EnumerableMap.OperatorMap internal nodeOperatorRegistry;

    function enrollValidatorNode(
        address nodeAddress,
        string calldata endpointUrl
    ) external override onlyRegisteredProtocol {
        if (nodeOperatorRegistry.contains(nodeAddress)) {
            revert ValidatorNodeAlreadyExists();
        }

        EnumerableMap.Operator memory nodeOperator = EnumerableMap.Operator(
            endpointUrl,
            msg.sender,
            Time.timestamp()
        );

        nodeOperatorRegistry.set(nodeAddress, nodeOperator);
    }

    function removeValidatorNode(
        address nodeAddress
    ) public override onlyRegisteredProtocol {
        nodeOperatorRegistry.remove(nodeAddress);
    }

    function suspendValidatorNode(
        address nodeAddress
    ) external override onlyRegisteredProtocol {
        nodeOperatorRegistry.disable(nodeAddress);
    }

    function reactivateValidatorNode(
        address nodeAddress
    ) external override onlyRegisteredProtocol {
        nodeOperatorRegistry.enable(nodeAddress);
    }

    function validateNodeRegistration(
        address nodeAddress
    ) public view virtual override returns (bool) {
        return nodeOperatorRegistry.contains(nodeAddress);
    }

    function checkNodeOperationalStatus(
        address nodeAddress
    ) public view returns (bool) {
        if (!nodeOperatorRegistry.contains(nodeAddress)) {
            revert ValidatorNodeNotFound();
        }

        (uint48 activationTime, uint48 deactivationTime) = nodeOperatorRegistry
            .getTimes(nodeAddress);
        return activationTime != 0 && deactivationTime == 0;
    }
}
