// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";
import {IValidatorRegistrySystem} from "../../src/interfaces/IRegistry.sol";
import {EnumerableMap} from "../../src/library/EnumerableMap.sol";
import {OperatorMapWithTime} from "../../src/library/OperatorMapWithTime.sol";
import {ValidatorRegistryCore} from "../../src/Registry/ValidatorRegistryCore.sol";

contract MockConsensusRestaking {
    function getProviderCollateral(address _operator, address _collateral) public returns (uint256) {
        return 100;
    }
}

contract MockValidatorRegistryCore is ValidatorRegistryCore {
    using EnumerableMap for EnumerableMap.OperatorMap;
    using OperatorMapWithTime for EnumerableMap.OperatorMap;

    function enrollOperatorNode(address nodeAddress) public {
        EnumerableMap.Operator memory nodeOperator =
            EnumerableMap.Operator("address1", "address2", "address3", msg.sender, Time.timestamp());

        nodeOperatorRegistry.set(nodeAddress, nodeOperator);
    }

    function suspendOperatorNode(address nodeAddress) public override {
        nodeOperatorRegistry.disable(nodeAddress);
    }
}

contract TestValidatorRegistryCore is Test {
    address public admin = address(0x1);
    MockValidatorRegistryCore public validatorRegistry;

    function setUp() public {
        vm.startPrank(admin);
        validatorRegistry = new MockValidatorRegistryCore();
        vm.stopPrank();
    }

    function testFetchOperatorCollateralAmountFailWithInvalidNodeOperator() public {
        vm.expectRevert(abi.encodeWithSelector(IValidatorRegistrySystem.InvalidNodeOperatorAddress.selector));
        validatorRegistry.fetchOperatorCollateralAmount(address(0), address(0x01));
    }

    function testFetchOperatorCollateralAmountFailWithInvalidCollateralToken() public {
        vm.expectRevert(abi.encodeWithSelector(IValidatorRegistrySystem.InvalidCollateralTokenAddress.selector));
        validatorRegistry.fetchOperatorCollateralAmount(address(0x01), address(0));
    }

    function testFetchOperatorCollateralAmount() public {
        address nodeOperator = address(0x2);
        address sender = address(new MockConsensusRestaking());
        vm.startPrank(sender);
        validatorRegistry.enrollOperatorNode(nodeOperator);
        vm.stopPrank();

        uint256 amount = validatorRegistry.fetchOperatorCollateralAmount(nodeOperator, address(0x03));

        assertEq(amount, 100, "Collateral amount is invalid");
    }

    function testCalculateTotalCollateralFailWithInvalidCollateralToken() public {
        vm.expectRevert(abi.encodeWithSelector(IValidatorRegistrySystem.InvalidCollateralTokenAddress.selector));
        validatorRegistry.calculateTotalCollateral(address(0));
    }

    function testCalculateTotalCollateral() public {
        address sender = address(new MockConsensusRestaking());
        vm.startPrank(sender);
        // Add 3 node operators
        validatorRegistry.enrollOperatorNode(address(0x02));
        validatorRegistry.enrollOperatorNode(address(0x03));
        validatorRegistry.enrollOperatorNode(address(0x04));
        vm.stopPrank();

        uint256 amount = validatorRegistry.calculateTotalCollateral(address(0x01));

        assertEq(amount, 100 * 3, "Collateral amount is invalid");
    }

    function testCheckNodeOperationalStatusFailWithInvalidNodeAddress() public {
        vm.expectRevert(abi.encodeWithSelector(IValidatorRegistrySystem.InvalidNodeAddress.selector));
        validatorRegistry.checkNodeOperationalStatus(address(0));
    }

    function testCheckNodeOperationalStatusFailWhenNodeNotFound() public {
        vm.expectRevert(abi.encodeWithSelector(IValidatorRegistrySystem.ValidatorNodeNotFound.selector));
        validatorRegistry.checkNodeOperationalStatus(address(0x01));
    }

    function testCheckNodeOperationalStatusResultTrue() public {
        address nodeOperator = address(0x02);
        validatorRegistry.enrollOperatorNode(nodeOperator);

        bool result = validatorRegistry.checkNodeOperationalStatus(nodeOperator);

        assertTrue(result);
    }

    function testCheckNodeOperationalStatusResultFalse() public {
        address nodeOperator = address(0x02);
        validatorRegistry.enrollOperatorNode(nodeOperator);
        validatorRegistry.suspendOperatorNode(nodeOperator);

        bool result = validatorRegistry.checkNodeOperationalStatus(nodeOperator);

        assertFalse(result);
    }
}
