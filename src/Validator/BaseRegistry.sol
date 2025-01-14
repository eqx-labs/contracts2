// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {ValidatorsLib} from "../library/ValidatorsLib.sol";
import {IParameters} from "../interfaces/IParameters.sol";
import {INodeRegistrationSystem} from "../interfaces/IValidators.sol";
import {NodeRegistry} from "./NodeRegistry.sol";

contract BaseRegistry is OwnableUpgradeable, UUPSUpgradeable, NodeRegistry {
    using ValidatorsLib for ValidatorsLib.ValidatorSet;

    uint256[43] private __gap;

    function initialize(address _owner, address _parameters) public initializer {
        __Ownable_init(_owner);
        protocolParameters = IParameters(_parameters);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
