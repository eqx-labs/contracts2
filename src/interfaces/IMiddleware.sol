// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import {BLS12381} from "../lib/bls/BLS12381.sol";

interface IConsensusMiddleware {

    error MalformedRequest();
    error ParticipantExists();
    error ParticipantNotFound();
    error NodeProviderNotActive();
    error UnauthorizedProvider();
    error OperationForbidden();


    function PROTOCOL_IDENTIFIER() external view returns (bytes32);


    function getPeriodStartTime(
        uint48 periodIndex
    ) external view returns (uint48);


    function getPeriodByTimestamp(
        uint48 timestamp
    ) external view returns (uint48);


    function getActivePeriod() external view returns (uint48);


    function getProviderCollateral(
        address provider, 
        address tokenAddress
    ) external view returns (uint256);


    function getProviderCollateralTokens(
        address provider
    ) external view returns (address[] memory, uint256[] memory);


    function getProviderCollateralAt(
        address provider,
        address tokenAddress,
        uint48 timestamp
    ) external view returns (uint256);
}