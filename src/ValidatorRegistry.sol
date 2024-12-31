// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {BaseDSS} from "lib/karak-onchain-sdk/src/BaseDSS.sol";

contract ValidatorRegistry {
    uint256 public number;

    function setNumber(uint256 newNumber) public {
        number = newNumber;
    }

    function increment() public {
        number++;
    }
}
