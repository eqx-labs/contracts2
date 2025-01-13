// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IParameters} from "../interfaces/IParameters.sol";
import {ValidationTypes} from "./ValidationTypes.sol";

contract Shared is ValidationTypes {
    using EnumerableSet for EnumerableSet.Bytes32Set;

    IParameters public validatorParams;
    EnumerableSet.Bytes32Set internal validationSetIDs;
    mapping(bytes32 => ValidationRecord) internal validationRecords;
}
