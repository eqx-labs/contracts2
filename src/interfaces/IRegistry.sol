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
    struct ProposerStatus {
        bytes20 pubkeyHash;       // Hash of the validator's public key.
        bool active;              // Indicates if the operator meets collateral requirements.
        address operator;         // Address of the operator authorized for the validator.
        string operatorRPC;       // RPC endpoint of the operator.
        address[] collaterals;    // List of collateral token addresses.
        uint256[] amounts;        // Corresponding collateral token amounts.
    }

    /// @notice Registers a new operator in the system.
    /// @param operator The address of the operator to register.
    /// @param rpc The RPC endpoint associated with the operator.
    function registerOperator(address operator, string calldata rpc) external;

    /// @notice Deregisters an existing operator, removing them from the system.
    /// @param operator The address of the operator to deregister.
    function deregisterOperator(address operator) external;

    /// @notice Pauses an operator, preventing them from performing actions.
    /// @param operator The address of the operator to pause.
    function pauseOperator(address operator) external;

    /// @notice Unpauses an operator, allowing them to perform actions again.
    /// @param operator The address of the operator to unpause.
    function unpauseOperator(address operator) external;

    /// @notice Checks if a given address is a registered operator.
    /// @param operator The address to check.
    /// @return Boolean indicating whether the address is a registered operator.
    function isOperator(address operator) external view returns (bool);

    /// @notice Retrieves the proposer status for a specific validator.
    /// @param pubkeyHash The hash of the validator's public key.
    /// @return status A `ProposerStatus` struct with details of the validator's proposer.
    function getProposerStatus(bytes20 pubkeyHash) external view returns (ProposerStatus memory status);

    /// @notice Retrieves the proposer statuses for multiple validators.
    /// @param pubkeyHashes An array of validator public key hashes.
    /// @return statuses An array of `ProposerStatus` structs with details of each proposer.
    function getProposerStatuses(bytes20[] calldata pubkeyHashes) external view returns (ProposerStatus[] memory statuses);

    /// @notice Checks if an operator is authorized for a specific validator.
    /// @param operator The address of the operator.
    /// @param pubkeyHash The hash of the validator's public key.
    /// @return Boolean indicating if the operator is authorized for the validator.
    function isOperatorAuthorizedForValidator(address operator, bytes20 pubkeyHash) external view returns (bool);

    /// @notice Retrieves a list of supported restaking middleware protocols.
    /// @return middlewares An array of middleware contract addresses.
    function getSupportedRestakingProtocols() external view returns (address[] memory middlewares);
}
