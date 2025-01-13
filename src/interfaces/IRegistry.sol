// SPDX-License-Identifier: MIT
<<<<<<< HEAD
pragma solidity 0.8.25;

interface IRegistry {
    error InvalidQuery();
    error OperatorAlreadyRegistered();
    error OperatorNotRegistered();
    error UnauthorizedMiddleware();
    // TODO: remove in future upgrade (unused)
    error InactiveOperator();

    /// @notice Proposer status info.
    struct ProposerStatus {
        // The pubkey hash of the validator.
        bytes20 pubkeyHash;
        // Whether the corresponding operator is active based on collateral requirements.
        bool active;
        // The operator address that is authorized to make & sign commitments on behalf of the validator.
        address operator;
        // The operator RPC endpoint.
        string operatorRPC;
        // The addresses of the collateral tokens.
        address[] collaterals;
        // The corresponding amounts of the collateral tokens.
        uint256[] amounts;
    }

    function registerOperator(address operator, string calldata rpc) external;

    function deregisterOperator(
        address operator
    ) external;

    function pauseOperator(
        address operator
    ) external;

    function unpauseOperator(
        address operator
    ) external;

    function isOperator(
        address operator
    ) external view returns (bool);

    function getProposerStatus(
        bytes20 pubkeyHash
    ) external view returns (ProposerStatus memory status);

    function getProposerStatuses(
        bytes20[] calldata pubkeyHashes
    ) external view returns (ProposerStatus[] memory statuses);

    function isOperatorAuthorizedForValidator(address operator, bytes20 pubkeyHash) external view returns (bool);

    function getSupportedRestakingProtocols() external view returns (address[] memory middlewares);
}
=======
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

  
}
>>>>>>> interstate_sidecare
