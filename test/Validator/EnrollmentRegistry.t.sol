// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test} from "forge-std/Test.sol";
import {BLS12381} from "../../src/library/bls/BLS12381.sol";
import {ValidatorsLib} from "../../src/library/ValidatorsLib.sol";
import {INodeRegistrationSystem} from "../../src/interfaces/IValidators.sol";
import {EnrollmentRegistry} from "../../src/Validator/EnrollmentRegistry.sol";

contract MockEnrollmentRegistry is EnrollmentRegistry {
    function registerNode(
        bytes20 nodeIdentityHash,
        address operatorAddress,
        uint32 maxGasCommitment
    ) public {
        _registerNode(nodeIdentityHash, operatorAddress, maxGasCommitment);
    }
}

contract EnrollmentRegistryTest is Test {
    MockEnrollmentRegistry public registry;
    uint32 public maxGasCommitment = 100;
    bytes20 public validatorNodeHash1 = bytes20(uint160(1000));
    bytes20 public validatorNodeHash2 = bytes20(uint160(2000));
    address public operatorAddress = address(1);

    function setUp() public {
        registry = new MockEnrollmentRegistry();
        registry.registerNode(validatorNodeHash1, operatorAddress, maxGasCommitment);
        registry.registerNode(validatorNodeHash2, operatorAddress, maxGasCommitment);
    }

    function testFetchValidatorNodes() public {
        INodeRegistrationSystem.ValidatorNodeDetails[] memory _nodes = registry.fetchAllValidatorNodes();

        assertEq(_nodes.length, 2);

        assertEq(_nodes[0].nodeIdentityHash, validatorNodeHash1);
        assertEq(_nodes[0].assignedOperatorAddress, operatorAddress);
        assertEq(_nodes[0].gasCapacityLimit, maxGasCommitment);

        assertEq(_nodes[1].nodeIdentityHash, validatorNodeHash2);
        assertEq(_nodes[1].assignedOperatorAddress, operatorAddress);
        assertEq(_nodes[1].gasCapacityLimit, maxGasCommitment);
    }
}
