// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import "./BaseRegistry.sol";
import {BLS12381} from "../library/bls/BLS12381.sol";
import {ValidatorsLib} from "../library/ValidatorsLib.sol";

contract QueryRegistry is BaseRegistry {
    using BLS12381 for BLS12381.G1Point;
      using ValidatorsLib for ValidatorsLib.ValidatorSet;
      error UnauthorizedAccessAttempt();


    function updateNodeCapacity(
        bytes20 nodeIdentityHash,
        uint32 maxGasCommitment
    ) public {
        address controller = NODES.getController(nodeIdentityHash);
        if (msg.sender != controller) {
            revert UnauthorizedAccessAttempt();
        }

        NODES.updateMaxCommittedGasLimit(nodeIdentityHash, maxGasCommitment);
    }

    function computeNodeIdentityHash(
        BLS12381.G1Point memory pubkey
    ) public pure returns (bytes20) {
        uint256[2] memory compressed = pubkey.compress();
        bytes32 fullHash = keccak256(abi.encodePacked(compressed));
        return bytes20(uint160(uint256(fullHash)));
    }
}