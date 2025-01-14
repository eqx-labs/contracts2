// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test} from "forge-std/Test.sol";
import {BLS12381} from "../../src/library/bls/BLS12381.sol";
import {QueryRegistry} from "../../src/Validator/QueryRegistry.sol";

contract QueryRegistryTest is Test {
    QueryRegistry public registry;
    address public admin = address(1);

    function testComputeNodeIdentityHash() public {
        // Deploy and initialize registry
        registry = new QueryRegistry();
    }
}
