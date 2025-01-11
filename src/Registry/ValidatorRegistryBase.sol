// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IParameters} from "../interfaces/IParameters.sol";
import {IValidatorRegistrySystem} from "../interfaces/IRegistry.sol";
import {INodeRegistrationSystem} from "../interfaces/IValidators.sol";
import {IConsensusRestaking} from "../interfaces/IRestaking.sol";
import {EnumerableMap} from "../lib/EnumerableMap.sol";
import {OperatorMapWithTime} from "../lib/OperatorMapWithTime.sol";

contract ValidatorRegistryBase is
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
    ) internal override onlyOwner {}

    function registerProtocol(address protocolContract) public onlyOwner {
        protocolRegistry.add(protocolContract);
    }

    function deregisterProtocol(address protocolContract) public onlyOwner {
        protocolRegistry.remove(protocolContract);
    }

    function listSupportedProtocols()
        public
        view
        virtual
        returns (address[] memory protocolAddressList)
    {
        return protocolRegistry.values();
    }

    function enrollValidatorNode(
        address nodeAddress,
        string calldata endpointUrl
    ) external virtual onlyRegisteredProtocol {
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
    ) external virtual onlyRegisteredProtocol {
        if (!nodeOperatorRegistry.contains(nodeAddress)) {
            revert ValidatorNodeNotFound();
        }
        nodeOperatorRegistry.remove(nodeAddress);
    }

    function suspendValidatorNode(
        address nodeAddress
    ) external virtual onlyRegisteredProtocol {
        if (!nodeOperatorRegistry.contains(nodeAddress)) {
            revert ValidatorNodeNotFound();
        }
        nodeOperatorRegistry.disable(nodeAddress);
    }

    function reactivateValidatorNode(
        address nodeAddress
    ) external virtual onlyRegisteredProtocol {
        if (!nodeOperatorRegistry.contains(nodeAddress)) {
            revert ValidatorNodeNotFound();
        }
        nodeOperatorRegistry.enable(nodeAddress);
    }

    function validateNodeRegistration(
        address nodeAddress
    ) external view virtual returns (bool) {
        return nodeOperatorRegistry.contains(nodeAddress);
    }

    function fetchValidatorProfile(
        bytes20 validatorIdentityHash
    ) external view returns (ValidatorNodeProfile memory profile) {
        if (validatorIdentityHash == bytes20(0)) {
            revert QueryValidationFailed();
        }

        uint48 epochStartTime = calculateEpochFromTimestamp(Time.timestamp());

        INodeRegistrationSystem.ValidatorNodeDetails
            memory validatorData = validatorNodes.fetchNodeByIdentityHash(
                validatorIdentityHash
            );

        EnumerableMap.Operator memory operatorInfo = nodeOperatorRegistry.get(
            validatorData.assignedOperatorAddress
        );

        profile.validatorIdentityHash = validatorIdentityHash;
        profile.nodeManagerAddress = validatorData.assignedOperatorAddress;
        profile.serviceEndpointUrl = operatorInfo.rpc;

        (uint48 activationTime, uint48 deactivationTime) = nodeOperatorRegistry
            .getTimes(validatorData.assignedOperatorAddress);

        if (
            !checkNodeStatusAtTime(
                activationTime,
                deactivationTime,
                epochStartTime
            )
        ) {
            return profile;
        }

        (
            profile.collateralTokenList,
            profile.collateralAmountList
        ) = IConsensusRestaking(operatorInfo.middleware)
            .getProviderCollateralTokens(validatorData.assignedOperatorAddress);

        uint256 totalCollateral = 0;
        for (uint256 i = 0; i < profile.collateralAmountList.length; ++i) {
            totalCollateral += profile.collateralAmountList[i];
        }

        profile.operationalStatus =
            totalCollateral >= systemParameters.OPERATOR_COLLATERAL_MINIMUM();

        return profile;
    }

    function fetchValidatorProfileBatch(
        bytes20[] calldata validatorIdentityHashes
    ) external view returns (ValidatorNodeProfile[] memory profileList) {
        profileList = new ValidatorNodeProfile[](
            validatorIdentityHashes.length
        );
        for (uint256 i = 0; i < validatorIdentityHashes.length; ++i) {
            profileList[i] = this.fetchValidatorProfile(
                validatorIdentityHashes[i]
            );
        }
        return profileList;
    }

    function validateNodeAuthorization(
        address nodeAddress,
        bytes20 validatorIdentityHash
    ) external view returns (bool) {
        if (nodeAddress == address(0) || validatorIdentityHash == bytes20(0)) {
            revert QueryValidationFailed();
        }
        return
            validatorNodes
                .fetchNodeByIdentityHash(validatorIdentityHash)
                .assignedOperatorAddress == nodeAddress;
    }

    // Internal helper functions
    function calculateEpochFromTimestamp(
        uint48 timestamp
    ) internal view virtual returns (uint48) {
        return
            (timestamp - SYSTEM_INITIALIZATION_TIME) /
            systemParameters.VALIDATOR_EPOCH_TIME();
    }

    function checkNodeStatusAtTime(
        uint48 activationTime,
        uint48 deactivationTime,
        uint48 checkTimestamp
    ) internal pure virtual returns (bool) {
        return
            activationTime != 0 &&
            activationTime <= checkTimestamp &&
            (deactivationTime == 0 || deactivationTime >= checkTimestamp);
    }
}
