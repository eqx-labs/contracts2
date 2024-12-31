// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import {IValidator} from "./IValidator.sol";

interface IManager {
    error InvalidQuery();
    error OperatorAlreadyRegistered();
    error OperatorNotRegistered();
    error UnauthorizedMiddleware();
    error InactiveOperator();

    struct Operator {
        string rpc;
        address middleware;
        uint256 timestamp;
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

    function validators() external view returns (IValidator);

    function getProposerStatus(
        bytes32 pubkeyHash
    ) external view returns (IValidator.ProposerStatus memory status);

    function getProposerStatuses(
        bytes32[] calldata pubkeyHashes
    ) external view returns (IValidator.ProposerStatus[] memory statuses);

    function isOperatorAuthorizedForValidator(address operator, bytes32 pubkeyHash) external view returns (bool);

    function getSupportedRestakingProtocols() external view returns (address[] memory middlewares);
}
