// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

interface IValidatorRegistrySystem {
    error QueryValidationFailed();
    error ValidatorNodeAlreadyExists();
    error ValidatorNodeNotFound();
    error UnauthorizedProtocolAccess();

    error ValidatorNodeOffline();


    struct ValidatorNodeProfile {

        bytes20 validatorIdentityHash;

        bool operationalStatus;

        address nodeManagerAddress;

        string serviceEndpointUrl;

        address[] collateralTokenList;

        uint256[] collateralAmountList;
    }

    function enrollValidatorNode(
        address nodeAddress, 
        string calldata endpointUrl
    ) external;

    function removeValidatorNode(
        address nodeAddress
    ) external;

    function suspendValidatorNode(
        address nodeAddress
    ) external;

    function reactivateValidatorNode(
        address nodeAddress
    ) external;

    function validateNodeRegistration(
        address nodeAddress
    ) external view returns (bool);

    function fetchValidatorProfile(
        bytes20 validatorIdentityHash
    ) external view returns (ValidatorNodeProfile memory profile);

    function fetchValidatorProfileBatch(
        bytes20[] calldata validatorIdentityHashes
    ) external view returns (ValidatorNodeProfile[] memory profileList);

    function validateNodeAuthorization(
        address nodeAddress, 
        bytes20 validatorIdentityHash
    ) external view returns (bool);

    function listSupportedProtocols() 
        external 
        view 
        returns (address[] memory protocolAddressList);
}