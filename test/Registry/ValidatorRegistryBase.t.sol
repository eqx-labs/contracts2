// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";
import {IValidatorRegistrySystem} from "../../src/interfaces/IRegistry.sol";
import {EnumerableMap} from "../../src/library/EnumerableMap.sol";
import {BLS12381} from "../../src/library/bls/BLS12381.sol";
import {OperatorMapWithTime} from "../../src/library/OperatorMapWithTime.sol";
import {ValidatorRegistryBase} from "../../src/Registry/ValidatorRegistryBase.sol";

contract MockParameters {
    function VALIDATOR_EPOCH_TIME() external view returns (uint48) { return 1000; }
    function OPERATOR_COLLATERAL_MINIMUM() external view returns (uint256) { return 100; }
}

contract MockNodeRegistrationSystem {
    struct ValidatorNodeDetails {
        BLS12381.G1Point pubkey;
        string  rpcs;
        bytes20 nodeIdentityHash;
        uint32 gasCapacityLimit;
        address assignedOperatorAddress;
        address controllerAddress;
    }

    function fetchValidatorByIdentityHash(
        bytes20 nodeIdentityHash
    ) external view returns (ValidatorNodeDetails memory) {}
}

contract MockValidatorRegistryBase is ValidatorRegistryBase {
    using EnumerableMap for EnumerableMap.OperatorMap;

    function listOperatorNodeKeys() public returns (address[] memory) {
        return nodeOperatorRegistry.keys();
    }
}

contract TestValidatorRegistryBase is Test {
    address public validatorContract = address(new MockNodeRegistrationSystem());
    address public parametersContract = address(new MockParameters());
    address public systemAdmin = address(0x01);
    address public mainActor = address(0x02);
    address public operatorNode = address(0x03);

    MockValidatorRegistryBase public validatorRegistry;

    function setUp() public {
        vm.startPrank(systemAdmin);
        validatorRegistry = new MockValidatorRegistryBase();
        validatorRegistry.initializeSystem(
            systemAdmin,
            parametersContract,
            validatorContract
        );
        validatorRegistry.registerProtocol(mainActor);
        vm.stopPrank();

        vm.startPrank(mainActor);
        validatorRegistry.enrollOperatorNode(
            operatorNode,
            "endpoint1",
            "endpoint2",
            "endpoint3"
        );
        vm.stopPrank();
    }

    function testInitializeSystemFailsWithInvalidSystemAdmin() public {
        ValidatorRegistryBase testRegistry = new ValidatorRegistryBase();
        vm.expectRevert(abi.encodeWithSelector(IValidatorRegistrySystem.InvalidSystemAdminAddress.selector));
        testRegistry.initializeSystem(
            address(0),
            parametersContract,
            validatorContract
        );
    }

    function testInitializeSystemFailsWithInvalidParametersContract() public {
        ValidatorRegistryBase testRegistry = new ValidatorRegistryBase();
        vm.expectRevert(abi.encodeWithSelector(IValidatorRegistrySystem.InvalidParametersContractAddress.selector));
        testRegistry.initializeSystem(
            systemAdmin,
            address(0),
            validatorContract
        );
    }

    function testInitializeSystemFailsWithInvalidValidatorContract() public {
        ValidatorRegistryBase testRegistry = new ValidatorRegistryBase();
        vm.expectRevert(abi.encodeWithSelector(IValidatorRegistrySystem.InvalidValidatorContractAddress.selector));
        testRegistry.initializeSystem(
            systemAdmin,
            parametersContract,
            address(0)
        );
    }

    function testCheckOperatorEnabledFailsWithInvalidNodeAddress() public {
        vm.expectRevert(abi.encodeWithSelector(IValidatorRegistrySystem.InvalidNodeAddress.selector));
        validatorRegistry.checkOperatorEnabled(address(0));
    }

    function testCheckOperatorEnabled() public {
        assertTrue(validatorRegistry.checkOperatorEnabled(operatorNode));
        address wrongOperatorNode = address(0x10);
        assertFalse(validatorRegistry.checkOperatorEnabled(wrongOperatorNode));
    }

    function testRegisterProtocolFailsWhenNotInvokedByAdmin() public {
        address someAddress = address(0x10);
        vm.expectRevert();
        validatorRegistry.registerProtocol(someAddress);
    }

    function testRegisterProtocolFailsWithInvalidProtocolContract() public {
        vm.startPrank(systemAdmin);
        vm.expectRevert(abi.encodeWithSelector(IValidatorRegistrySystem.InvalidProtocolAddress.selector));
        validatorRegistry.registerProtocol(address(0));
        vm.stopPrank();
    }

    function testRegisterProtocol() public {
        address someAddress = address(0x10);
        vm.startPrank(systemAdmin);
        validatorRegistry.registerProtocol(someAddress);
        address[] memory supportedAddresses = validatorRegistry.listSupportedProtocols();
        vm.stopPrank();

        assertEq(supportedAddresses.length, 2);
        assertEq(supportedAddresses[1], someAddress);
    }

    function testDeregisterProtocolFailsWhenNotInvokedByAdmin() public {
        address someAddress = address(0x10);
        vm.expectRevert();
        validatorRegistry.registerProtocol(someAddress);
    }

    function testDeregisterProtocolFailsWithInvalidProtocolContract() public {
        vm.startPrank(systemAdmin);
        vm.expectRevert(abi.encodeWithSelector(IValidatorRegistrySystem.InvalidProtocolAddress.selector));
        validatorRegistry.registerProtocol(address(0));
        vm.stopPrank();
    }

    function testDeregisterProtocol() public {
        address someAddress = address(0x10);
        vm.startPrank(systemAdmin);

        validatorRegistry.registerProtocol(someAddress);
        address[] memory addressesAfterRegistration = validatorRegistry.listSupportedProtocols();
        assertEq(addressesAfterRegistration.length, 2);

        validatorRegistry.deregisterProtocol(someAddress);
        address[] memory addressesAfterDeregistration = validatorRegistry.listSupportedProtocols();
        assertEq(addressesAfterDeregistration.length, 1);
        vm.stopPrank();
    }

    function testCalculateEpochStartTime() public {
        uint48 someEpochNumber = 123;
        uint48 expected = validatorRegistry.SYSTEM_INITIALIZATION_TIME() +
            someEpochNumber *
            1000;

        assertEq(validatorRegistry.calculateEpochStartTime(someEpochNumber), expected);
    }

    function testEnrollOperatorNodeFailsWhenNotInvokedByAdmin() public {
        address someAddress = address(0x10);
        vm.expectRevert();
        validatorRegistry.enrollOperatorNode(
            someAddress,
            "endpoint1",
            "endpoint2",
            "endpoint3"
        );
    }

    function testEnrollOperatorNodeFailsWithInvalidNodeAddress() public {
        vm.startPrank(mainActor);
        vm.expectRevert(abi.encodeWithSelector(IValidatorRegistrySystem.InvalidNodeAddress.selector));
        validatorRegistry.enrollOperatorNode(
            address(0),
            "endpoint1",
            "endpoint2",
            "endpoint3"
        );
        vm.stopPrank();
    }

    function testEnrollOperatorNodeFailsWithInvalidEndpoint() public {
        address someAddress = address(0x10);
        vm.startPrank(mainActor);
        vm.expectRevert(abi.encodeWithSelector(IValidatorRegistrySystem.InvalidEndpointUrl.selector));
        validatorRegistry.enrollOperatorNode(
            someAddress,
            "",
            "endpoint2",
            "endpoint3"
        );
        vm.stopPrank();
    }

    function testEnrollOperatorNodeFailsWithValidatorNodeAlreadyExists() public {
        vm.startPrank(mainActor);
        vm.expectRevert(abi.encodeWithSelector(IValidatorRegistrySystem.ValidatorNodeAlreadyExists.selector));
        validatorRegistry.enrollOperatorNode(
            operatorNode,
            "endpoint1",
            "endpoint2",
            "endpoint3"
        );
        vm.stopPrank();
    }

    function testEnrollOperatorNode() public {
        address someAddress = address(0x10);
        vm.startPrank(mainActor);
        validatorRegistry.enrollOperatorNode(
            someAddress,
            "endpoint1",
            "endpoint2",
            "endpoint3"
        );

        address[] memory keys = validatorRegistry.listOperatorNodeKeys();
        vm.stopPrank();

        assertEq(keys.length, 2);
        assertEq(keys[0], operatorNode);
        assertEq(keys[1], someAddress);
    }

    function testRemoveOperatorNodeFailsWhenNotInvokedByAdmin() public {
        address someAddress = address(0x10);
        vm.expectRevert();
        validatorRegistry.removeOperatorNode(someAddress);
    }

    function testRemoveOperatorNodeFailsWithInvalidNodeAddress() public {
        vm.startPrank(mainActor);
        vm.expectRevert(abi.encodeWithSelector(IValidatorRegistrySystem.InvalidNodeAddress.selector));
        validatorRegistry.removeOperatorNode(address(0));
        vm.stopPrank();
    }

    function testRemoveOperatorNode() public {
        vm.startPrank(mainActor);
        validatorRegistry.removeOperatorNode(operatorNode);
        address[] memory keys = validatorRegistry.listOperatorNodeKeys();
        vm.stopPrank();

        assertEq(keys.length, 0);
    }

    function testSuspendOperatorNodeFailsWhenNotInvokedByAdmin() public {
        address someAddress = address(0x10);
        vm.expectRevert();
        validatorRegistry.suspendOperatorNode(someAddress);
    }

    function testSuspendOperatorNodeFailsWithInvalidNodeAddress() public {
        vm.startPrank(mainActor);
        vm.expectRevert(abi.encodeWithSelector(IValidatorRegistrySystem.InvalidNodeAddress.selector));
        validatorRegistry.suspendOperatorNode(address(0));
        vm.stopPrank();
    }

    function testSuspendOperatorNode() public {
        vm.startPrank(mainActor);
        assertTrue(validatorRegistry.checkNodeOperationalStatus(operatorNode));
        validatorRegistry.suspendOperatorNode(operatorNode);
        assertFalse(validatorRegistry.checkNodeOperationalStatus(operatorNode));
        vm.stopPrank();
    }

    function testReactivateOperatorNodeFailsWhenNotInvokedByAdmin() public {
        address someAddress = address(0x10);
        vm.expectRevert();
        validatorRegistry.reactivateOperatorNode(someAddress);
    }

    function testReactivateOperatorNodeFailsWithInvalidNodeAddress() public {
        vm.startPrank(mainActor);
        vm.expectRevert(abi.encodeWithSelector(IValidatorRegistrySystem.InvalidNodeAddress.selector));
        validatorRegistry.reactivateOperatorNode(address(0));
        vm.stopPrank();
    }

    function testReactivateOperatorNode() public {
        vm.startPrank(mainActor);
        assertTrue(validatorRegistry.checkNodeOperationalStatus(operatorNode));
        validatorRegistry.suspendOperatorNode(operatorNode);
        assertFalse(validatorRegistry.checkNodeOperationalStatus(operatorNode));
        validatorRegistry.reactivateOperatorNode(operatorNode);
        assertTrue(validatorRegistry.checkNodeOperationalStatus(operatorNode));
        vm.stopPrank();
    }

    function testCalculateEpochFromTimestamp() public {
        uint48 timestamp = Time.timestamp();
        uint48 expected = (timestamp - validatorRegistry.SYSTEM_INITIALIZATION_TIME()) / 1000;
        assertEq(validatorRegistry.calculateEpochFromTimestamp(timestamp), expected);
    }
}
