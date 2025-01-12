// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.0;

// import "forge-std/Test.sol";
// import "../src/Registry/ValidatorRegistryOperations.sol";
// import "../src/interfaces/IParameters.sol";
// import "../src/interfaces/IValidators.sol";
// import "../src/interfaces/IRestaking.sol";

// contract MockParameters is IParameters {
//     uint256 constant EPOCH_TIME = 1 days;
//     uint256 constant MIN_COLLATERAL = 100 ether;
    
//     function VALIDATOR_EPOCH_TIME() external pure returns (uint256) {
//         return EPOCH_TIME;
//     }
    
//     function OPERATOR_COLLATERAL_MINIMUM() external pure returns (uint256) {
//         return MIN_COLLATERAL;
//     }
// }

// contract ValidatorRegistryTest is Test {
//     ValidatorRegistryOperations public registry;
//     MockParameters public parameters;
    
//     address public admin = address(1);
//     address public protocol1 = address(2);
//     address public protocol2 = address(3);
//     address public validator1 = address(4);
//     address public validator2 = address(5);
    
//     function setUp() public {
//         // Deploy mock contracts
//         parameters = new MockParameters();
        
//         // Deploy and initialize registry
//         registry = new ValidatorRegistryOperations();
//         registry.initializeSystem(
//             admin,
//             address(parameters),
//             address(0) // Mock validator contract address
//         );
        
//         vm.startPrank(admin);
//         registry.registerProtocol(protocol1);
//         registry.registerProtocol(protocol2);
//         vm.stopPrank();
//     }

//     function testProtocolRegistration() public {
//         address[] memory protocols = registry.listSupportedProtocols();
//         assertEq(protocols.length, 2);
//         assertTrue(protocols[0] == protocol1 || protocols[1] == protocol1);
//         assertTrue(protocols[0] == protocol2 || protocols[1] == protocol2);
//     }

//     function testEnrollValidator() public {
//         vm.startPrank(protocol1);
//         registry.enrollValidatorNode(validator1, "https://validator1.example.com");
//         assertTrue(registry.validateNodeRegistration(validator1));
//         vm.stopPrank();
//     }

//     function testFailEnrollDuplicateValidator() public {
//         vm.startPrank(protocol1);
//         registry.enrollValidatorNode(validator1, "https://validator1.example.com");
        
//         // Should revert with ValidatorNodeAlreadyExists
//         vm.expectRevert();
//         registry.enrollValidatorNode(validator1, "https://validator1-new.example.com");
//         vm.stopPrank();
//     }

//     function testSuspendAndReactivateValidator() public {
//         vm.startPrank(protocol1);
//         registry.enrollValidatorNode(validator1, "https://validator1.example.com");
        
//         // Test suspension
//         registry.suspendValidatorNode(validator1);
//         assertFalse(registry.checkNodeOperationalStatus(validator1));
        
//         // Test reactivation
//         registry.reactivateValidatorNode(validator1);
//         assertTrue(registry.checkNodeOperationalStatus(validator1));
//         vm.stopPrank();
//     }

//     function testRemoveValidator() public {
//         vm.startPrank(protocol1);
//         registry.enrollValidatorNode(validator1, "https://validator1.example.com");
//         assertTrue(registry.validateNodeRegistration(validator1));
        
//         registry.removeValidatorNode(validator1);
//         assertFalse(registry.validateNodeRegistration(validator1));
//         vm.stopPrank();
//     }

//     function testEpochCalculations() public {
//         uint48 currentTime = uint48(block.timestamp);
//         uint48 epoch = registry.fetchCurrentEpoch();
//         uint48 epochStartTime = registry.calculateEpochStartTime(epoch);
        
//         assertTrue(epochStartTime <= currentTime);
//         assertTrue(currentTime < epochStartTime + parameters.VALIDATOR_EPOCH_TIME());
//     }

//     function testUnauthorizedAccess() public {
//         address unauthorized = address(999);
        
//         vm.startPrank(unauthorized);
        
//         // Should revert when unauthorized address tries to enroll validator
//         vm.expectRevert();
//         registry.enrollValidatorNode(validator1, "https://validator1.example.com");
        
//         vm.stopPrank();
//     }

//     function testProtocolDeregistration() public {
//         vm.startPrank(admin);
//         registry.deregisterProtocol(protocol1);
        
//         address[] memory protocols = registry.listSupportedProtocols();
//         assertEq(protocols.length, 1);
//         assertEq(protocols[0], protocol2);
        
//         vm.stopPrank();
//     }
// }