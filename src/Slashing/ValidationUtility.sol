// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {RLPReader} from "../lib/rlp/RLPReader.sol";
import {TransactionDecoder} from "../lib/TransactionDecoder.sol";

import "./ValidationTypes.sol";

 contract ValidationUtility is  ValidationTypes {
    using RLPReader for bytes;
    using RLPReader for RLPReader.RLPItem;
    using TransactionDecoder for bytes;
    using TransactionDecoder for TransactionDecoder.Transaction;

    function _recoverAuthorizationData(
        AuthorizedMessagePacket calldata authorization
    ) internal pure returns (
        address msgSender,
        address witnessAuthorizer,
        MessageDetails memory messageData
    ) {
        witnessAuthorizer = ECDSA.recover(_computeAuthorizationId(authorization), authorization.authorization);
        TransactionDecoder.Transaction memory decodedMsg = authorization.payload.decodeEnveloped();
        msgSender = decodedMsg.recoverSender();
        messageData = MessageDetails({
            messageDigest: keccak256(authorization.payload),
            sequence: decodedMsg.nonce,
            fuelLimit: decodedMsg.gasLimit
        });
    }

    function _computeValidationId(
        AuthorizedMessagePacket[] calldata authorizations
    ) internal pure returns (bytes32) {
        bytes32[] memory signatures = new bytes32[](authorizations.length);
        for (uint256 i = 0; i < authorizations.length; i++) {
            signatures[i] = keccak256(authorizations[i].authorization);
        }
        return keccak256(abi.encodePacked(signatures));
    }

    function _computeAuthorizationId(
        AuthorizedMessagePacket calldata authorization
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(
            keccak256(authorization.payload),
            _toLittleEndian(authorization.epoch)
        ));
    }

    function _toLittleEndian(uint64 x) internal pure returns (bytes memory) {
        bytes memory b = new bytes(8);
        for (uint256 i = 0; i < 8; i++) {
            b[i] = bytes1(uint8(x >> (8 * i)));
        }
        return b;
    }

     function _decodeSegmentHeaderRLP(
        bytes calldata headerRLP
    ) internal pure returns (ChainSegmentInfo memory segmentInfo) {
        RLPReader.RLPItem[] memory headerFields = headerRLP.toRLPItem().readList();

        segmentInfo.ancestorDigest = headerFields[0].readBytes32();
        segmentInfo.worldStateDigest = headerFields[3].readBytes32();
        segmentInfo.messageTreeDigest = headerFields[4].readBytes32();
        segmentInfo.segmentHeight = headerFields[8].readUint256();
        segmentInfo.chronograph = headerFields[11].readUint256();
        segmentInfo.networkFee = headerFields[15].readUint256();
    }
    }