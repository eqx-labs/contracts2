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


  


    function getProviderCollateral(
        address provider, 
        address tokenAddress
    ) external view returns (uint256);


    function getProviderCollateralTokens(
        address provider
    ) external view returns (address[] memory, uint256[] memory);


}