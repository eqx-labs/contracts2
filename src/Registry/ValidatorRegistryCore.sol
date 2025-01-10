// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IParameters} from "../interfaces/IParameters.sol";
import {IValidatorRegistrySystem} from "../interfaces/IRegistry.sol";
import {INodeRegistrationSystem} from "../interfaces/IValidators.sol";
import {IConsensusMiddleware} from "../interfaces/IMiddleware.sol";
import {EnumerableMap} from "../lib/EnumerableMap.sol";
import {OperatorMapWithTime} from "../lib/OperatorMapWithTime.sol";
import {IValidatorNodeTypes} from "./IValidatorNodeTypes.sol";

contract ValidatorRegistryCore is
    IValidatorRegistrySystem,
    OwnableUpgradeable,
    UUPSUpgradeable
{
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableMap for EnumerableMap.OperatorMap;
    using OperatorMapWithTime for EnumerableMap.OperatorMap;

    uint48 public SYSTEM_INITIALIZATION_TIME;
    IParameters public systemParameters;
    INodeRegistrationSystem public validatorNodes;
    EnumerableSet.AddressSet internal protocolRegistry;
    EnumerableMap.OperatorMap private nodeOperatorRegistry;

    uint256[45] private __gap;

    modifier onlyRegisteredProtocol() {
        if (!protocolRegistry.contains(msg.sender)) {
            revert UnauthorizedProtocolAccess();
        }
        _;
    }

    function initializeSystem(
        address systemAdmin,
        address parametersContract,
        address validatorContract
    ) public initializer {
        __Ownable_init(systemAdmin);
        systemParameters = IParameters(parametersContract);
        validatorNodes = INodeRegistrationSystem(validatorContract);
        SYSTEM_INITIALIZATION_TIME = Time.timestamp();
    }

    function _authorizeUpgrade(
        address newSystemImplementation
    ) internal       override
    onlyOwner {}

    function registerProtocol(address protocolContract) public onlyOwner {
        protocolRegistry.add(protocolContract);
    }

    function deregisterProtocol(address protocolContract) public onlyOwner {
        protocolRegistry.remove(protocolContract);
    }

    function listSupportedProtocols()
        public
        view
           
        returns (address[] memory protocolAddressList)
    {
        return protocolRegistry.values();
    }

    function enrollValidatorNode(
        address nodeAddress,
        string calldata endpointUrl
    ) external     onlyRegisteredProtocol {
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
    ) external     onlyRegisteredProtocol {
        if (!nodeOperatorRegistry.contains(nodeAddress)) {
            revert ValidatorNodeNotFound();
        }
        nodeOperatorRegistry.remove(nodeAddress);
    }

    function suspendValidatorNode(
        address nodeAddress
    ) external     onlyRegisteredProtocol {
        if (!nodeOperatorRegistry.contains(nodeAddress)) {
            revert ValidatorNodeNotFound();
        }
        nodeOperatorRegistry.disable(nodeAddress);
    }

    function reactivateValidatorNode(
        address nodeAddress
    ) external     onlyRegisteredProtocol {
        if (!nodeOperatorRegistry.contains(nodeAddress)) {
            revert ValidatorNodeNotFound();
        }
        nodeOperatorRegistry.enable(nodeAddress);
    }

    function validateNodeRegistration(
        address nodeAddress
    ) public view     returns (bool) {
        return nodeOperatorRegistry.contains(nodeAddress);
    }

    function validateNodeAuthorization(
        address nodeAddress,
        bytes20 nodeIdentityHash
    ) public view     returns (bool) {
        if (nodeAddress == address(0) || nodeIdentityHash == bytes20(0)) {
            revert QueryValidationFailed();
        }

        return validatorNodes
            .fetchNodeByIdentityHash(nodeIdentityHash)
            .assignedOperatorAddress == nodeAddress;
    }

    function fetchValidatorProfile(
        bytes20 validatorIdentityHash
    ) public view     returns (ValidatorNodeProfile memory profile) {
        if (validatorIdentityHash == bytes20(0)) {
            revert QueryValidationFailed();
        }

        uint48 epochStartTime = calculateEpochFromTimestamp(Time.timestamp());

       IValidatorNodeTypes.ValidatorNodeDetails memory validatorData = validatorNodes
            .fetchNodeByIdentityHash(validatorIdentityHash);

        EnumerableMap.Operator memory operatorInfo = nodeOperatorRegistry.get(
            validatorData.assignedOperatorAddress
        );

        profile.validatorIdentityHash = validatorIdentityHash;
        profile.nodeManagerAddress = validatorData.assignedOperatorAddress;
        profile.serviceEndpointUrl = operatorInfo.rpc;

        (uint48 activationTime, uint48 deactivationTime) = nodeOperatorRegistry
            .getTimes(validatorData.assignedOperatorAddress);

        if (!checkNodeStatusAtTime(activationTime, deactivationTime, epochStartTime)) {
            return profile;
        }

        (
            profile.collateralTokenList,
            profile.collateralAmountList
        ) = IConsensusMiddleware(operatorInfo.middleware)
            .getProviderCollateralTokens(validatorData.assignedOperatorAddress);

        uint256 totalCollateral = 0;
        for (uint256 i = 0; i < profile.collateralAmountList.length; ++i) {
            totalCollateral += profile.collateralAmountList[i];
        }

        profile.operationalStatus = totalCollateral >= systemParameters.OPERATOR_COLLATERAL_MINIMUM();

        return profile;
    }

    function fetchValidatorProfileBatch(
        bytes20[] calldata validatorIdentityHashes
    ) public view     returns (ValidatorNodeProfile[] memory profileList) {
        profileList = new ValidatorNodeProfile[](validatorIdentityHashes.length);
        for (uint256 i = 0; i < validatorIdentityHashes.length; ++i) {
            profileList[i] = fetchValidatorProfile(validatorIdentityHashes[i]);
        }
        return profileList;
    }

    function calculateEpochStartTime(
        uint48 epochNumber
    ) public view returns (uint48 startTimestamp) {
        return SYSTEM_INITIALIZATION_TIME +
            epochNumber *
            systemParameters.VALIDATOR_EPOCH_TIME();
    }

    function calculateEpochFromTimestamp(
        uint48 timestamp
    ) public view returns (uint48 epochNumber) {
        return (timestamp - SYSTEM_INITIALIZATION_TIME) /
            systemParameters.VALIDATOR_EPOCH_TIME();
    }

    function fetchCurrentEpoch() public view returns (uint48 epochNumber) {
        return calculateEpochFromTimestamp(Time.timestamp());
    }

    function fetchNodeCollateralAmount(
        address nodeOperator,
        address collateralToken
    ) public view returns (uint256) {
        EnumerableMap.Operator memory operatorInfo = nodeOperatorRegistry.get(
            nodeOperator
        );

        return IConsensusMiddleware(operatorInfo.middleware)
            .getProviderCollateral(nodeOperator, collateralToken);
    }

    function calculateTotalCollateral(
        address collateralToken
    ) public view returns (uint256 totalAmount) {
        for (uint256 i = 0; i < nodeOperatorRegistry.length(); ++i) {
            (
                address nodeOperator,
                EnumerableMap.Operator memory operatorInfo
            ) = nodeOperatorRegistry.at(i);
            totalAmount += IConsensusMiddleware(operatorInfo.middleware)
                .getProviderCollateral(nodeOperator, collateralToken);
        }
        return totalAmount;
    }

    function checkNodeStatusAtTime(
        uint48 activationTime,
        uint48 deactivationTime,
        uint48 checkTimestamp
    ) internal pure returns (bool) {
        return activationTime != 0 &&
            activationTime <= checkTimestamp &&
            (deactivationTime == 0 || deactivationTime >= checkTimestamp);
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