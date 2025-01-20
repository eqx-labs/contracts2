// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IValidatorRegistrySystem} from "../interfaces/IRegistry.sol";
import {INodeRegistrationSystem} from "../interfaces/IValidators.sol";
import {IConsensusRestaking} from "../interfaces/IRestaking.sol";
import {EnumerableMap} from "../library/EnumerableMap.sol";
import {OperatorMapWithTime} from "../library/OperatorMapWithTime.sol";




contract ValidatorRegistryCore is IValidatorRegistrySystem {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableMap for EnumerableMap.OperatorMap;
    using OperatorMapWithTime for EnumerableMap.OperatorMap;
    //  error ValidatorNodeNotFound();

    EnumerableMap.OperatorMap private nodeOperatorRegistry;

    uint256[45] private __gap;

    function fetchOperatorCollateralAmount(
        address nodeOperator,
        address collateralToken
    ) public view returns (uint256) {
        // Check if nodeOperator is a valid address
        if (nodeOperator == address(0)) {
            revert InvalidNodeOperatorAddress();
        }

        // Check if collateralToken is a valid address
        if (collateralToken == address(0)) {
            revert InvalidCollateralTokenAddress();
        }
        EnumerableMap.Operator memory operatorInfo = nodeOperatorRegistry.get(
            nodeOperator
        );

        return
            IConsensusRestaking(operatorInfo.middleware).getProviderCollateral(
                nodeOperator,
                collateralToken
            );
    }

    function calculateTotalCollateral(
        address collateralToken
    ) public view returns (uint256 totalAmount) {
        // Check if collateralToken is a valid address
        if (collateralToken == address(0)) {
            revert InvalidCollateralTokenAddress();
        }

        for (uint256 i = 0; i < nodeOperatorRegistry.length(); ++i) {
            (
                address nodeOperator,
                EnumerableMap.Operator memory operatorInfo
            ) = nodeOperatorRegistry.at(i);
            totalAmount += IConsensusRestaking(operatorInfo.middleware)
                .getProviderCollateral(nodeOperator, collateralToken);
        }
        return totalAmount;
    }

    function checkNodeOperationalStatus(
        address nodeAddress
    ) public view returns (bool) {
        if (nodeAddress == address(0)) {
            revert InvalidNodeAddress();
        }

        if (!nodeOperatorRegistry.contains(nodeAddress)) {
            revert ValidatorNodeNotFound();
        }

        (uint48 activationTime, uint48 deactivationTime) = nodeOperatorRegistry
            .getTimes(nodeAddress);
        return activationTime != 0 && deactivationTime == 0;
    }

    function validateNodeRegistration(
        address nodeAddress
    ) external view virtual override returns (bool) {}

    function enrollOperatorNode(
        address nodeAddress,
 string calldata endpointUrl,
        string calldata endpointUrl1,
        string calldata endpointUrl2
    ) external virtual {}

    function removeOperatorNode(address nodeAddress) external virtual {}

    function suspendOperatorNode(address nodeAddress) external virtual {}

    function reactivateOperatorNode(address nodeAddress) external virtual {}

  
}