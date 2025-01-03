// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

interface IManager {
    // Custom error for invalid queries (e.g., missing or incorrect data).
    error InvalidQuery();
    // Error when an operator is already registered in the system.
    error OperatorAlreadyRegistered();
    // Error when trying to interact with an operator that is not registered.
    error OperatorNotRegistered();
    // Error for unauthorized access by a middleware contract.
    error UnauthorizedMiddleware();
    // Deprecated error (reserved for removal in future upgrades). Indicates an operator is inactive.
    error InactiveOperator();

    /// @notice Represents the status and details of a validator's proposer.
    struct ValidatorProposerStatus {
        bytes20 validatorPubkeyHash;   // Hash of the validator's public key.
        bool isActive;                 // Indicates if the operator meets collateral requirements.
        address operatorAddress;       // Address of the operator authorized for the validator.
        string operatorRpcUrl;         // RPC endpoint of the operator.
        address[] collateralTokens;    // List of collateral token addresses.
        uint256[] collateralAmounts;   // Corresponding collateral token amounts.
    }

    /// @notice Registers a new operator in the system.
    /// @param operatorAddress The address of the operator to register.
    /// @param rpcUrl The RPC endpoint associated with the operator.
    function registerNewOperator(address operatorAddress, string calldata rpcUrl) external;

    /// @notice Deregisters an existing operator, removing them from the system.
    /// @param operatorAddress The address of the operator to deregister.
    function removeOperator(address operatorAddress) external;

    /// @notice Pauses an operator, preventing them from performing actions.
    /// @param operatorAddress The address of the operator to pause.
    function suspendOperator(address operatorAddress) external;

    /// @notice Unpauses an operator, allowing them to perform actions again.
    /// @param operatorAddress The address of the operator to unpause.
    function resumeOperator(address operatorAddress) external;

    /// @notice Checks if a given address is a registered operator.
    /// @param operatorAddress The address to check.
    /// @return Boolean indicating whether the address is a registered operator.
    function isOperatorRegistered(address operatorAddress) external view returns (bool);

    /// @notice Retrieves the proposer status for a specific validator.
    /// @param validatorPubkeyHash The hash of the validator's public key.
    /// @return proposerStatus A `ValidatorProposerStatus` struct with details of the validator's proposer.
    function getValidatorProposerStatus(bytes20 validatorPubkeyHash) external view returns (ValidatorProposerStatus memory proposerStatus);

    /// @notice Retrieves the proposer statuses for multiple validators.
    /// @param validatorPubkeyHashes An array of validator public key hashes.
    /// @return proposerStatuses An array of `ValidatorProposerStatus` structs with details of each proposer.
    function getValidatorProposerStatuses(bytes20[] calldata validatorPubkeyHashes) external view returns (ValidatorProposerStatus[] memory proposerStatuses);

    /// @notice Checks if an operator is authorized for a specific validator.
    /// @param operatorAddress The address of the operator.
    /// @param validatorPubkeyHash The hash of the validator's public key.
    /// @return Boolean indicating if the operator is authorized for the validator.
    function isOperatorAuthorizedForValidator(address operatorAddress, bytes20 validatorPubkeyHash) external view returns (bool);

    /// @notice Retrieves a list of supported restaking middleware protocols.
    /// @return middlewareAddresses An array of middleware contract addresses.
    function getRestakingMiddlewareProtocols() external view returns (address[] memory middlewareAddresses);
}
