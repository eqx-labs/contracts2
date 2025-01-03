// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import {BLS} from "../lib/bls/BLS.sol";

interface IMiddleware {
    error InvalidQuery();
    error AlreadyRegistered();
    error NotRegistered();
    error OperatorNotOptedIn();
    error NotOperator();
    error NotAllowed();

    function NAME_HASH() external view returns (bytes32);

    function getEpochStartTs(
        uint48 epoch
    ) external view returns (uint48);

    function getEpochAtTs(
        uint48 timestamp
    ) external view returns (uint48);

    function getCurrentEpoch() external view returns (uint48);

    function getOperatorStake(address operator, address collateral) external view returns (uint256);

    function getOperatorCollaterals(
        address operator
    ) external view returns (address[] memory, uint256[] memory);

    function getOperatorStakeAt(
        address operator,
        address collateral,
        uint48 timestamp
    ) external view returns (uint256);
}
