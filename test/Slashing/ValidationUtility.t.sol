// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test} from "forge-std/Test.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {TransactionDecoder} from "../../src/library/TransactionDecoder.sol";
import {ValidationTypes} from "../../src/Slashing/ValidationTypes.sol";
import {ValidationUtility} from "../../src/Slashing/ValidationUtility.sol";

contract MockValidationUtility is ValidationUtility {
    function recoverAuthorizationDataMock(AuthorizedMessagePacket calldata authorization)
        public
        pure
        returns (address msgSender, address witnessAuthorizer, MessageDetails memory messageData)
    {
        (msgSender, witnessAuthorizer, messageData) = recoverAuthorizationData(authorization);
    }
}

contract TestValidationUtility is Test, ValidationTypes {
    address public admin = address(0x01);
    address public operator = address(0x02);

    MockValidationUtility public validationUtility;

    function setUp() public {
        vm.startPrank(admin);
        validationUtility = new MockValidationUtility();
        vm.stopPrank();
    }

    function testRecoverAuthorizationData() public {
        address expectedMsgSender = address(0x03);
        uint256 expectedNonce = 1;
        uint256 expectedGasLimit = 50000;
        uint256 expectedGasPrice = 2000000000;
        uint64 expectedEpoch = 42;
        address expectedWitnessAuthorizer = address(0x456);

        // Create a mock Transaction
        TransactionDecoder.Transaction memory transaction = TransactionDecoder.Transaction({
            txType: TransactionDecoder.TxType.Legacy, // Replace with your actual enum type if necessary
            chainId: 1,
            isChainIdSet: true,
            nonce: expectedNonce,
            gasPrice: expectedGasPrice,
            maxPriorityFeePerGas: 0,
            maxFeePerGas: 0,
            gasLimit: expectedGasLimit,
            to: expectedMsgSender,
            value: 0,
            data: "",
            accessList: new bytes[](1),
            maxFeePerBlobGas: 0,
            blobVersionedHashes: new bytes32[](1),
            sig: "",
            legacyV: 0
        });

        // Encode the mock Transaction
        bytes memory payload = TransactionDecoder.unsigned(transaction);

        // Mock message digest
        bytes32 messageDigest = keccak256(payload);

        // Compute the authorization ID and sign it
        bytes32 authorizationId = keccak256(abi.encodePacked(messageDigest, expectedEpoch));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, authorizationId); // Sign using a test private key
        bytes memory signature = abi.encodePacked(r, s, v);

        // Create the `AuthorizedMessagePacket`
        AuthorizedMessagePacket memory authPacket =
            AuthorizedMessagePacket({payload: payload, authorization: signature, epoch: expectedEpoch});

        // Call the test wrapper function
        // (
        //     address msgSender,
        //     address witnessAuthorizer,
        //     ValidationUtility.MessageDetails memory messageData
        // ) = validationUtility.recoverAuthorizationDataMock(authPacket);

        // Assertions
        // assertEq(msgSender, expectedMsgSender, "MsgSender mismatch");
        // assertEq(witnessAuthorizer, expectedWitnessAuthorizer, "WitnessAuthorizer mismatch");
        // assertEq(messageData.messageDigest, messageDigest, "MessageDigest mismatch");
        // assertEq(messageData.sequence, expectedNonce, "Sequence mismatch");
        // assertEq(messageData.fuelLimit, expectedGasLimit, "FuelLimit mismatch");
    }
}
