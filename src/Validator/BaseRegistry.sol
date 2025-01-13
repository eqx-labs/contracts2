// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {ValidatorsLib} from "../library/ValidatorsLib.sol";
import {IParameters} from "../interfaces/IParameters.sol";
import {INodeRegistrationSystem} from "../interfaces/IValidators.sol";

contract BaseRegistry is OwnableUpgradeable, UUPSUpgradeable {
    using ValidatorsLib for ValidatorsLib.ValidatorSet;
    
    IParameters public protocolParameters;
    ValidatorsLib.ValidatorSet internal NODES;
    uint256[43] private __gap;

    event ConsensusNodeRegistered(bytes32 indexed nodeIdentityHash);

    function initialize(
        address _owner,
        address _parameters
    ) public initializer {
        __Ownable_init(_owner);
        protocolParameters = IParameters(_parameters);
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    function _getNodeInfo(
        ValidatorsLib._Validator memory _node
    ) internal view returns (INodeRegistrationSystem.ValidatorNodeDetails memory) {
        return
            INodeRegistrationSystem.ValidatorNodeDetails({
                nodeIdentityHash: _node.pubkeyHash,
                gasCapacityLimit: _node.maxCommittedGasLimit,
                assignedOperatorAddress: NODES.getAuthorizedOperator(
                    _node.pubkeyHash
                ),
                controllerAddress: NODES.getController(_node.pubkeyHash)
            });
    }
}