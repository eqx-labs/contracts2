// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

interface IValidatorRegistrySystem {
    error QueryValidationFailed();
    error ValidatorNodeAlreadyExists();
    error ValidatorNodeNotFound();
    error UnauthorizedProtocolAccess();
    error InvalidNodeAddress();
    error InvalidEndpointUrl();
    error InvalidProtocolAddress();
    error InvalidSystemAdminAddress();
    error InvalidParametersContractAddress();
    error InvalidValidatorContractAddress();
    error InvalidCollateralTokenAddress();
    error InvalidNodeOperatorAddress();
    



    error ValidatorNodeOffline();


    struct ValidatorNodeProfile {
        bytes20 validatorIdentityHash;
        bool operationalStatus;
        address nodeManagerAddress;
        string serviceEndpointUrl;
        address[] collateralTokenList;
        uint256[] collateralAmountList;
    }

    function enrollOperatorNode(
        address nodeAddress, 
        string calldata endpointUrl,
        string calldata endpointUrl1,
        string calldata endpointUrl2

    ) external;

    function removeOperatorNode(
        address nodeAddress
    ) external;

    function suspendOperatorNode(
        address nodeAddress
    ) external;

    function reactivateOperatorNode(
        address nodeAddress
    ) external;

    function validateNodeRegistration(
        address nodeAddress
    ) external view returns (bool);

  
}