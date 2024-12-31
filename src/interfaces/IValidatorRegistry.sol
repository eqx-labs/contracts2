// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.0;

interface IValidatorRegistry {

    // VIEW FUNCTIONS
    function initializeDSS(address core, uint256 maxSlashablePercentageWad) external;

    event DSSInitialized(address core, uint256 maxSlashablePercentageWad);

    error CallerNotCoreTemp();
}
