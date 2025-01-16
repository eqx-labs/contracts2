// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test} from "forge-std/Test.sol";
import {BLS12381} from "../../src/library/bls/BLS12381.sol";
import {IParameters} from "../../src/interfaces/IParameters.sol";
import {NodeRegistry} from "../../src/Validator/NodeRegistry.sol";
import {QueryRegistry} from "../../src/Validator/QueryRegistry.sol";
import {INodeRegistrationSystem} from "../../src/interfaces/IValidators.sol";

contract MockParameters {
    function SKIP_SIGNATURE_VALIDATION() external view returns (bool) {
        return true;
    }
}

contract MockNodeRegistry is NodeRegistry {
    function setParameters(address _parameters) public {
        protocolParameters = IParameters(_parameters);
    }
}

contract NodeRegistryTest is Test {
    using BLS12381 for BLS12381.G1Point;

    MockNodeRegistry public registry;
    address public admin = address(1);
    address public operator = address(2);
    uint32 public maxGasCommitment = 100;
    bytes20 public validatorNodeHash1 = bytes20(uint160(1000));

    function setUp() public {
        vm.startPrank(admin);
        registry = new MockNodeRegistry();
        address mockedParameters = address(new MockParameters());
        registry.setParameters(mockedParameters);
        vm.stopPrank();
    }

    function testFetchNodeByPubkey() public {
        BLS12381.G1Point memory samplePubkey = BLS12381.generatorG1();
        bytes20 sampleHash = registry.computeNodeIdentityHash(samplePubkey);
        vm.startPrank(admin);
        registry.enrollNodeWithoutVerification(
            sampleHash,
            maxGasCommitment,
            operator
        );
        INodeRegistrationSystem.ValidatorNodeDetails memory _node = registry.fetchNodeByPublicKey(samplePubkey);
        vm.stopPrank();

        assertEq(_node.nodeIdentityHash, sampleHash);
        assertEq(_node.assignedOperatorAddress, operator);
        assertEq(_node.gasCapacityLimit, maxGasCommitment);
        assertEq(_node.controllerAddress, admin);
    }

    function testEnrollNodeWithoutVerification() public {
        vm.startPrank(admin);
        registry.enrollNodeWithoutVerification(
            validatorNodeHash1,
            maxGasCommitment,
            operator
        );
        INodeRegistrationSystem.ValidatorNodeDetails[] memory _nodes = registry.fetchAllValidatorNodes();
        vm.stopPrank();
        
        assertEq(_nodes.length, 1);

        assertEq(_nodes[0].nodeIdentityHash, validatorNodeHash1);
        assertEq(_nodes[0].assignedOperatorAddress, operator);
        assertEq(_nodes[0].gasCapacityLimit, maxGasCommitment);
        assertEq(_nodes[0].controllerAddress, admin);
    }
}
