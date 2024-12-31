// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {BaseDSS} from "lib/karak-onchain-sdk/src/BaseDSS.sol";
import {IBaseDSS} from "lib/karak-onchain-sdk/src/interfaces/IBaseDSS.sol";
import {IValidatorRegistry} from "./interfaces/IValidatorRegistry.sol";

contract ValidatorRegistry is BaseDSS, IValidatorRegistry  {
    uint256 public number;

    function setNumber(uint256 newNumber) public {
        number = newNumber;
    }

    function increment() public {
        number++;
    }

    function initializeDSS(address core, uint256 maxSlashablePercentageWad) external {
        // Calls the internal _init function from BaseDSS
        _init(core, maxSlashablePercentageWad);
        emit DSSInitialized(core, maxSlashablePercentageWad);
    }

    function registrationHook(address operator, bytes memory data) public override onlyCore {
        super.registrationHook(operator, data);  // Calls the BaseDSS hook logic
        // Add any custom logic here
    }

    function unregistrationHook(address operator) public override onlyCore {
        super.unregistrationHook(operator);  // Calls the BaseDSS hook logic
        // Add any custom logic here
    }

    function requestUpdateStakeHook(address operator, IBaseDSS.StakeUpdateRequest memory newStake) public override onlyCore {
        super.requestUpdateStakeHook(operator, newStake); // Calls the BaseDSS hook logic
        // Add any custom logic here
    }
    
    function finishUpdateStakeHook(address operator, IBaseDSS.QueuedStakeUpdate memory queuedStakeUpdate) public override onlyCore {
        super.finishUpdateStakeHook(operator, queuedStakeUpdate); // Calls the BaseDSS hook logic
        // Add any custom logic here
    }

    function jailOperator(address operator) external {
        _jailOperator(operator);  // Uses internal function to jail the operator
    }
    
    function unjailOperator(address operator) external {
        _unjailOperator(operator);  // Uses internal function to unjail the operator
    }
}
