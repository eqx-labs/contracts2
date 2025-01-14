// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "./BaseRegistry.sol";
import {BLS12381} from "../library/bls/BLS12381.sol";

contract QueryRegistry {
    using BLS12381 for BLS12381.G1Point;

    error UnauthorizedAccessAttempt();

    function computeNodeIdentityHash(BLS12381.G1Point memory pubkey) public pure returns (bytes20) {
        uint256[2] memory compressed = pubkey.compress();
        bytes32 fullHash = keccak256(abi.encodePacked(compressed));
        return bytes20(uint160(uint256(fullHash)));
    }
}
