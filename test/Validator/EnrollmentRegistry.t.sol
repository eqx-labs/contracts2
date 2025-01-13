// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test} from "forge-std/Test.sol";
import {BLS12381} from "../../src/library/bls/BLS12381.sol";
import {ValidatorsLib} from "../../src/library/ValidatorsLib.sol";
import {INodeRegistrationSystem} from "../../src/interfaces/IValidators.sol";
import {EnrollmentRegistry} from "../../src/Validator/EnrollmentRegistry.sol";
import {QueryRegistry} from "../../src/Validator/QueryRegistry.sol";

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
    address public admin = address(1);
    address public operator = address(2);
    address public maliciousSender = address(3);
    uint32 public maxGasCommitment = 100;
    bytes20 public validatorNodeHash1 = bytes20(uint160(1000));
    bytes20 public validatorNodeHash2 = bytes20(uint160(2000));

    function setUp() public {
        vm.startPrank(admin);
        registry = new MockEnrollmentRegistry();
        registry.registerNode(validatorNodeHash1, operator, maxGasCommitment);
        registry.registerNode(validatorNodeHash2, operator, maxGasCommitment);
        vm.stopPrank();
    }

    function testFetchValidatorNodes() public {
        INodeRegistrationSystem.ValidatorNodeDetails[] memory _nodes = registry.fetchAllValidatorNodes();

        assertEq(_nodes.length, 2);

        assertEq(_nodes[0].nodeIdentityHash, validatorNodeHash1);
        assertEq(_nodes[0].assignedOperatorAddress, operator);
        assertEq(_nodes[0].gasCapacityLimit, maxGasCommitment);
        assertEq(_nodes[0].controllerAddress, admin);

        assertEq(_nodes[1].nodeIdentityHash, validatorNodeHash2);
        assertEq(_nodes[1].assignedOperatorAddress, operator);
        assertEq(_nodes[1].gasCapacityLimit, maxGasCommitment);
        assertEq(_nodes[1].controllerAddress, admin);
    }

    function testUpdateNodeCapacityFailsForMaliciousSender() public {
        // Check if the method blocks the malicious sender
        uint32 newNodeCapacity = 10;
        vm.startPrank(maliciousSender);
        vm.expectRevert(abi.encodeWithSelector(QueryRegistry.UnauthorizedAccessAttempt.selector));
        registry.updateNodeCapacity(validatorNodeHash1, newNodeCapacity);
        vm.stopPrank();

    }

    function testUpdateNodeCapacityFailsForNonExistingHash() public {
        // Check if the method reverts when the validator does not exist
        uint32 newNodeCapacity = 10;
        vm.startPrank(admin);
        bytes20 wrongNodeHash = bytes20(uint160(3000));
        vm.expectRevert(abi.encodeWithSelector(ValidatorsLib.ValidatorDoesNotExist.selector, wrongNodeHash));
        registry.updateNodeCapacity(wrongNodeHash, newNodeCapacity);
        vm.stopPrank();
    }

    function testUpdateNodeCapacity() public {
        // Check if the node capacity is updated properly
        uint32 newNodeCapacity = 10;
        vm.startPrank(admin);
        registry.updateNodeCapacity(validatorNodeHash1, newNodeCapacity);
        INodeRegistrationSystem.ValidatorNodeDetails[] memory _nodes = registry.fetchAllValidatorNodes();
        assertEq(_nodes[0].gasCapacityLimit, newNodeCapacity);
        vm.stopPrank();
    }

    function testFetchNodeByIdentityHashFailsForNonExistingHash() public {
        bytes20 wrongNodeHash = bytes20(uint160(3000));
        vm.expectRevert(abi.encodeWithSelector(ValidatorsLib.ValidatorDoesNotExist.selector, wrongNodeHash));
        registry.fetchNodeByIdentityHash(wrongNodeHash);
    }

    function testFetchNodeByIdentityHash() public {
        INodeRegistrationSystem.ValidatorNodeDetails memory _node = registry.fetchNodeByIdentityHash(validatorNodeHash1);

        assertEq(_node.nodeIdentityHash, validatorNodeHash1);
        assertEq(_node.assignedOperatorAddress, operator);
        assertEq(_node.gasCapacityLimit, maxGasCommitment);
        assertEq(_node.controllerAddress, admin);
    }
}
