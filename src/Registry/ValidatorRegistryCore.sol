// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IParameters} from "../interfaces/IParameters.sol";
import {IValidatorRegistrySystem} from "../interfaces/IRegistry.sol";
import {INodeRegistrationSystem} from "../interfaces/IValidators.sol";
import {IConsensusRestaking} from "../interfaces/IRestaking.sol";
import {EnumerableMap} from "../library/EnumerableMap.sol";
import {OperatorMapWithTime} from "../library/OperatorMapWithTime.sol";

import {ValidatorRegistryBase} from "./ValidatorRegistryBase.sol";
import {ValidatorRegistryTime} from "./ValidatorRegistryTime.sol";
 



contract ValidatorRegistryCore is
    ValidatorRegistryTime

{
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableMap for EnumerableMap.OperatorMap;
    using OperatorMapWithTime for EnumerableMap.OperatorMap;


    EnumerableMap.OperatorMap private nodeOperatorRegistry;

    uint256[45] private __gap;

 

    function fetchNodeCollateralAmount(
        address nodeOperator,
        address collateralToken
    ) public view returns (uint256) {
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
        if (!nodeOperatorRegistry.contains(nodeAddress)) {
            revert ValidatorNodeNotFound();
        }

        (uint48 activationTime, uint48 deactivationTime) = nodeOperatorRegistry
            .getTimes(nodeAddress);
        return activationTime != 0 && deactivationTime == 0;
    }
}