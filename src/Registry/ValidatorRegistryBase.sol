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
import "./ValidatorRegistryCore.sol";
import {OperatorMapWithTime} from "../library/OperatorMapWithTime.sol";

contract ValidatorRegistryBase is
    OwnableUpgradeable,
    ValidatorRegistryCore,
    UUPSUpgradeable
{
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableMap for EnumerableMap.OperatorMap;
    using OperatorMapWithTime for EnumerableMap.OperatorMap;

    uint48 public SYSTEM_INITIALIZATION_TIME;
    IParameters public systemParameters;
    INodeRegistrationSystem public validatorNodes;
    EnumerableSet.AddressSet internal protocolRegistry;
    // EnumerableMap.OperatorMap private nodeOperatorRegistry;

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
        if (systemAdmin == address(0)) {
            revert InvalidSystemAdminAddress();
        }

        // Check if parametersContract is a valid address
        if (parametersContract == address(0)) {
            revert InvalidParametersContractAddress();
        }

        // Check if validatorContract is a valid address
        if (validatorContract == address(0)) {
            revert InvalidValidatorContractAddress();
        }
        __Ownable_init(systemAdmin);
        systemParameters = IParameters(parametersContract);
        validatorNodes = INodeRegistrationSystem(validatorContract);
        SYSTEM_INITIALIZATION_TIME = Time.timestamp();
    }

    function _authorizeUpgrade(
        address newSystemImplementation
    ) internal override onlyOwner {}

    function checkOperatorEnabled(
        address nodeAddress
    ) public view returns (bool) {
        if (nodeAddress == address(0)) {
            revert InvalidNodeAddress();
        }

        return nodeOperatorRegistry.contains(nodeAddress);
    }

    function registerProtocol(address protocolContract) public onlyOwner {
        if (protocolContract == address(0)) {
            revert InvalidProtocolAddress();
        }
        protocolRegistry.add(protocolContract);
    }

    function deregisterProtocol(address protocolContract) public onlyOwner {
        if (protocolContract == address(0)) {
            revert InvalidProtocolAddress();
        }

        protocolRegistry.remove(protocolContract);
    }

    function listSupportedProtocols()
        public
        view
        returns (address[] memory protocolAddressList)
    {
        return protocolRegistry.values();
    }

    function calculateEpochStartTime(
        uint48 epochNumber
    ) public view returns (uint48 startTimestamp) {
        return
            SYSTEM_INITIALIZATION_TIME +
            epochNumber *
            systemParameters.VALIDATOR_EPOCH_TIME();
    }

    function enrollOperatorNode(
        address nodeAddress,
        string calldata endpointUrl,
        string calldata endpointUrl1,
        string calldata endpointUrl2
    ) external override onlyRegisteredProtocol {
        if (nodeAddress == address(0)) {
            revert InvalidNodeAddress();
        }

        // Check if endpointUrl is not empty
        if (
            bytes(endpointUrl).length == 0 ||
            bytes(endpointUrl1).length == 0 ||
            bytes(endpointUrl2).length == 0
        ) {
            revert InvalidEndpointUrl();
        }

        //  nodeRegistry have all the list of validator nodeaddress

        if (nodeOperatorRegistry.contains(nodeAddress)) {
            revert ValidatorNodeAlreadyExists();
        }

        EnumerableMap.Operator memory nodeOperator = EnumerableMap.Operator(
            endpointUrl,
            endpointUrl1,
            endpointUrl2,
            msg.sender,
            Time.timestamp()
        );

        nodeOperatorRegistry.set(nodeAddress, nodeOperator);
    }

    function removeOperatorNode(
        address nodeAddress
    ) external override onlyRegisteredProtocol {
        if (nodeAddress == address(0)) {
            revert InvalidNodeAddress();
        }

        nodeOperatorRegistry.remove(nodeAddress);
    }

    function suspendOperatorNode(
        address nodeAddress
    ) external override onlyRegisteredProtocol {
        if (nodeAddress == address(0)) {
            revert InvalidNodeAddress();
        }

        nodeOperatorRegistry.disable(nodeAddress);
    }

    function reactivateOperatorNode(
        address nodeAddress
    ) external override onlyRegisteredProtocol {
        if (nodeAddress == address(0)) {
            revert InvalidNodeAddress();
        }

        nodeOperatorRegistry.enable(nodeAddress);
    }

    function calculateEpochFromTimestamp(
        uint48 timestamp
    ) public view returns (uint48) {
        return
            (timestamp - SYSTEM_INITIALIZATION_TIME) /
            systemParameters.VALIDATOR_EPOCH_TIME();
    }

    function fetchCurrentEpoch() public view returns (uint48 epochNumber) {
        return calculateEpochFromTimestamp(Time.timestamp());
    }

    function fetchProposerProfile(
        bytes20 validatorIdentityHash
    ) external view returns (ValidatorNodeProfile memory profile) {
        if (validatorIdentityHash == bytes20(0)) {
            revert QueryValidationFailed();
        }

        uint48 epochStartTime = calculateEpochFromTimestamp(Time.timestamp());

        INodeRegistrationSystem.ValidatorNodeDetails
            memory validatorData = validatorNodes.fetchValidatorByIdentityHash(
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

    function fetchProposerProfileBatch(
        bytes20[] calldata validatorIdentityHashes
    ) external view returns (ValidatorNodeProfile[] memory profileList) {
        profileList = new ValidatorNodeProfile[](
            validatorIdentityHashes.length
        );
        for (uint256 i = 0; i < validatorIdentityHashes.length; ++i) {
            profileList[i] = this.fetchProposerProfile(
                validatorIdentityHashes[i]
            );
        }
        return profileList;
    }

    function isOperatorAuthorizedForValidator(
        address nodeAddress,
        bytes20 validatorIdentityHash
    ) external view returns (bool) {
        if (nodeAddress == address(0) || validatorIdentityHash == bytes20(0)) {
            revert QueryValidationFailed();
        }
        return
            validatorNodes
                .fetchValidatorByIdentityHash(validatorIdentityHash)
                .assignedOperatorAddress == nodeAddress;
    }

    // Internal helper functions

    function checkNodeStatusAtTime(
        uint48 activationTime,
        uint48 deactivationTime,
        uint48 checkTimestamp
    ) private pure returns (bool) {
        return
            activationTime != 0 &&
            activationTime <= checkTimestamp &&
            (deactivationTime == 0 || deactivationTime >= checkTimestamp);
    }

   




}
