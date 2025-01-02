// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import {RLPReader} from "./rlp/RLPReader.sol";
import {RLPWriter} from "./rlp/RLPWriter.sol";
import {BytesUtils} from "./BytesUtils.sol";


library TransactionDecoder {
    using BytesUtils for bytes;
    using RLPReader for bytes;
    using RLPReader for RLPReader.RLPItem;


    enum TxType {
        Legacy,
        Eip2930,
        Eip1559,
        Eip4844
    }


    struct Transaction {
        TxType txType;
        uint64 chainId;
        bool isChainIdSet;
        uint256 nonce;
        uint256 gasPrice;
        uint256 maxPriorityFeePerGas;
        uint256 maxFeePerGas;
        uint256 gasLimit;
        address to;
        uint256 value;
        bytes data;
        bytes[] accessList;
        uint256 maxFeePerBlobGas;
        bytes32[] blobVersionedHashes;
        bytes sig;
        uint64 legacyV;
    }

    error NoSignature();
    error InvalidYParity();
    error UnsupportedTxType();
    error InvalidFieldCount();
    error InvalidSignatureLength();


    function decodeEnveloped(
        bytes memory raw
    ) internal pure returns (Transaction memory transaction) {
        bytes1 prefix = raw[0];

        if (prefix >= 0x7F) {
            return _decodeLegacy(raw);
        } else if (prefix == 0x01) {
            return _decodeEip2930(raw);
        } else if (prefix == 0x02) {
            return _decodeEip1559(raw);
        } else if (prefix == 0x03) {
            return _decodeEip4844(raw);
        } else {
            revert UnsupportedTxType();
        }
    }


    function recoverSender(
        Transaction memory transaction
    ) internal pure returns (address) {
        return ECDSA.recover(preimage(transaction), signature(transaction));
    }
    function preimage(
        Transaction memory transaction
    ) internal pure returns (bytes32 preimg) {
        preimg = keccak256(unsigned(transaction));
    }


    function unsigned(
        Transaction memory transaction
    ) internal pure returns (bytes memory unsignedTx) {
        if (transaction.txType == TxType.Legacy) {
            unsignedTx = _unsignedLegacy(transaction);
        } else if (transaction.txType == TxType.Eip2930) {
            unsignedTx = _unsignedEip2930(transaction);
        } else if (transaction.txType == TxType.Eip1559) {
            unsignedTx = _unsignedEip1559(transaction);
        } else if (transaction.txType == TxType.Eip4844) {
            unsignedTx = _unsignedEip4844(transaction);
        } else {
            revert UnsupportedTxType();
        }
    }

    function signature(
        Transaction memory transaction
    ) internal pure returns (bytes memory sig) {
        if (transaction.sig.length == 0) {
            revert NoSignature();
        } else if (transaction.sig.length != 65) {
            revert InvalidSignatureLength();
        } else {
            sig = transaction.sig;
        }
    }
    function _decodeLegacy(
        bytes memory raw
    ) private pure returns (Transaction memory transaction) {
        transaction.txType = TxType.Legacy;

        // Legacy transactions don't have a type prefix, so we can decode directly
        RLPReader.RLPItem[] memory fields = raw.toRLPItem().readList();

        if (fields.length != 9 && fields.length != 6) {
            revert InvalidFieldCount();
        }

        transaction.nonce = fields[0].readUint256();
        transaction.gasPrice = fields[1].readUint256();
        transaction.gasLimit = fields[2].readUint256();
        transaction.to = fields[3].readAddress();
        transaction.value = fields[4].readUint256();
        transaction.data = fields[5].readBytes();


        if (fields.length == 6) {
            return transaction;
        }


        uint64 v = uint64(fields[6].readUint256());
        uint256 r = fields[7].readUint256();
        uint256 s = fields[8].readUint256();

        if (r == 0 && s == 0) {

            transaction.chainId = v;
            transaction.isChainIdSet = true;
        } else {
            if (v >= 35) {

                transaction.chainId = (v - 35) / 2;
                transaction.legacyV = v;
                transaction.isChainIdSet = true;
            }


            uint8 parityV = uint8(((v ^ 1) % 2) + 27);
            transaction.sig = abi.encodePacked(bytes32(r), bytes32(s), parityV);
        }
    }


    function _decodeEip2930(
        bytes memory raw
    ) private pure returns (Transaction memory transaction) {
        transaction.txType = TxType.Eip2930;


        bytes memory rlpData = raw.slice(1, raw.length - 1);
        RLPReader.RLPItem[] memory fields = rlpData.toRLPItem().readList();

        if (fields.length != 8 && fields.length != 11) {
            revert InvalidFieldCount();
        }

        transaction.chainId = uint64(fields[0].readUint256());
        transaction.nonce = fields[1].readUint256();
        transaction.gasPrice = fields[2].readUint256();
        transaction.gasLimit = fields[3].readUint256();
        transaction.to = fields[4].readAddress();
        transaction.value = fields[5].readUint256();
        transaction.data = fields[6].readBytes();

        RLPReader.RLPItem[] memory accessListItems = fields[7].readList();
        transaction.accessList = new bytes[](accessListItems.length);
        for (uint256 i = 0; i < accessListItems.length; i++) {
            transaction.accessList[i] = accessListItems[i].readRawBytes();
        }


        if (fields.length == 8) {
            return transaction;
        }

        uint8 v = uint8(fields[8].readUint256()) + 27;
        bytes32 r = fields[9].readBytes32();
        bytes32 s = fields[10].readBytes32();


        transaction.sig = abi.encodePacked(r, s, v);
    }


    function _decodeEip1559(
        bytes memory raw
    ) private pure returns (Transaction memory transaction) {
        transaction.txType = TxType.Eip1559;


        bytes memory rlpData = raw.slice(1, raw.length - 1);
        RLPReader.RLPItem[] memory fields = rlpData.toRLPItem().readList();

        if (fields.length != 9 && fields.length != 12) {
            revert InvalidFieldCount();
        }

        transaction.chainId = uint64(fields[0].readUint256());
        transaction.nonce = fields[1].readUint256();
        transaction.maxPriorityFeePerGas = fields[2].readUint256();
        transaction.maxFeePerGas = fields[3].readUint256();
        transaction.gasLimit = fields[4].readUint256();
        transaction.to = fields[5].readAddress();
        transaction.value = fields[6].readUint256();
        transaction.data = fields[7].readBytes();

        RLPReader.RLPItem[] memory accessListItems = fields[8].readList();
        transaction.accessList = new bytes[](accessListItems.length);
        for (uint256 i = 0; i < accessListItems.length; i++) {
            transaction.accessList[i] = accessListItems[i].readRawBytes();
        }

        if (fields.length == 9) {
            return transaction;
        }

        uint8 v = uint8(fields[9].readUint256()) + 27;
        bytes32 r = fields[10].readBytes32();
        bytes32 s = fields[11].readBytes32();


        transaction.sig = abi.encodePacked(r, s, v);
    }

    function _decodeEip4844(
        bytes memory raw
    ) private pure returns (Transaction memory transaction) {
        transaction.txType = TxType.Eip4844;


        bytes memory rlpData = raw.slice(1, raw.length - 1);
        RLPReader.RLPItem[] memory fields = rlpData.toRLPItem().readList();

        if (fields.length != 11 && fields.length != 14) {
            revert InvalidFieldCount();
        }

        transaction.chainId = uint64(fields[0].readUint256());
        transaction.nonce = fields[1].readUint256();
        transaction.maxPriorityFeePerGas = fields[2].readUint256();
        transaction.maxFeePerGas = fields[3].readUint256();
        transaction.gasLimit = fields[4].readUint256();
        transaction.to = fields[5].readAddress();
        transaction.value = fields[6].readUint256();
        transaction.data = fields[7].readBytes();

        RLPReader.RLPItem[] memory accessListItems = fields[8].readList();
        transaction.accessList = new bytes[](accessListItems.length);
        for (uint256 i = 0; i < accessListItems.length; i++) {
            transaction.accessList[i] = accessListItems[i].readRawBytes();
        }

        transaction.maxFeePerBlobGas = fields[9].readUint256();

        RLPReader.RLPItem[] memory blobVersionedHashesItems = fields[10].readList();
        transaction.blobVersionedHashes = new bytes32[](blobVersionedHashesItems.length);
        for (uint256 i = 0; i < blobVersionedHashesItems.length; i++) {
            transaction.blobVersionedHashes[i] = blobVersionedHashesItems[i].readBytes32();
        }

        if (fields.length == 11) {

            return transaction;
        }

        uint8 v = uint8(fields[11].readUint256()) + 27;
        bytes32 r = fields[12].readBytes32();
        bytes32 s = fields[13].readBytes32();


        transaction.sig = abi.encodePacked(r, s, v);
    }

 
    function _unsignedLegacy(
        Transaction memory transaction
    ) private pure returns (bytes memory unsignedTx) {
        uint64 chainId = 0;
        if (transaction.chainId != 0) {

            chainId = transaction.chainId;
        } else if (transaction.sig.length != 0) {

            if (transaction.legacyV >= 35) {
                chainId = (transaction.legacyV - 35) / 2;
            }
        }

        uint256 fieldsCount = 6 + (transaction.isChainIdSet ? 3 : 0);
        bytes[] memory fields = new bytes[](fieldsCount);

        fields[0] = RLPWriter.writeUint(transaction.nonce);
        fields[1] = RLPWriter.writeUint(transaction.gasPrice);
        fields[2] = RLPWriter.writeUint(transaction.gasLimit);
        fields[3] = RLPWriter.writeAddress(transaction.to);
        fields[4] = RLPWriter.writeUint(transaction.value);
        fields[5] = RLPWriter.writeBytes(transaction.data);

        if (transaction.isChainIdSet) {
            if (transaction.chainId == 0) {

                fields[6] = abi.encodePacked(bytes1(0));
            } else {
                fields[6] = RLPWriter.writeUint(chainId);
            }

            fields[7] = RLPWriter.writeBytes(new bytes(0));
            fields[8] = RLPWriter.writeBytes(new bytes(0));
        }

        unsignedTx = RLPWriter.writeList(fields);
    }

    function _unsignedEip2930(
        Transaction memory transaction
    ) private pure returns (bytes memory unsignedTx) {
        bytes[] memory fields = new bytes[](8);

        fields[0] = RLPWriter.writeUint(transaction.chainId);
        fields[1] = RLPWriter.writeUint(transaction.nonce);
        fields[2] = RLPWriter.writeUint(transaction.gasPrice);
        fields[3] = RLPWriter.writeUint(transaction.gasLimit);
        fields[4] = RLPWriter.writeAddress(transaction.to);
        fields[5] = RLPWriter.writeUint(transaction.value);
        fields[6] = RLPWriter.writeBytes(transaction.data);

        bytes[] memory accessList = new bytes[](transaction.accessList.length);
        for (uint256 i = 0; i < transaction.accessList.length; i++) {
            accessList[i] = transaction.accessList[i];
        }
        fields[7] = RLPWriter.writeList(accessList);


        unsignedTx = abi.encodePacked(uint8(TxType.Eip2930), RLPWriter.writeList(fields));
    }


    function _unsignedEip1559(
        Transaction memory transaction
    ) private pure returns (bytes memory unsignedTx) {
        bytes[] memory fields = new bytes[](9);

        fields[0] = RLPWriter.writeUint(transaction.chainId);
        fields[1] = RLPWriter.writeUint(transaction.nonce);
        fields[2] = RLPWriter.writeUint(transaction.maxPriorityFeePerGas);
        fields[3] = RLPWriter.writeUint(transaction.maxFeePerGas);
        fields[4] = RLPWriter.writeUint(transaction.gasLimit);
        fields[5] = RLPWriter.writeAddress(transaction.to);
        fields[6] = RLPWriter.writeUint(transaction.value);
        fields[7] = RLPWriter.writeBytes(transaction.data);

        bytes[] memory accessList = new bytes[](transaction.accessList.length);
        for (uint256 i = 0; i < transaction.accessList.length; i++) {
            accessList[i] = transaction.accessList[i];
        }
        fields[8] = RLPWriter.writeList(accessList);


        unsignedTx = abi.encodePacked(uint8(TxType.Eip1559), RLPWriter.writeList(fields));
    }


    function _unsignedEip4844(
        Transaction memory transaction
    ) private pure returns (bytes memory unsignedTx) {
        bytes[] memory fields = new bytes[](11);

        fields[0] = RLPWriter.writeUint(transaction.chainId);
        fields[1] = RLPWriter.writeUint(transaction.nonce);
        fields[2] = RLPWriter.writeUint(transaction.maxPriorityFeePerGas);
        fields[3] = RLPWriter.writeUint(transaction.maxFeePerGas);
        fields[4] = RLPWriter.writeUint(transaction.gasLimit);
        fields[5] = RLPWriter.writeAddress(transaction.to);
        fields[6] = RLPWriter.writeUint(transaction.value);
        fields[7] = RLPWriter.writeBytes(transaction.data);

        bytes[] memory accessList = new bytes[](transaction.accessList.length);
        for (uint256 i = 0; i < transaction.accessList.length; i++) {
            accessList[i] = transaction.accessList[i];
        }
        fields[8] = RLPWriter.writeList(accessList);

        fields[9] = RLPWriter.writeUint(transaction.maxFeePerBlobGas);

        bytes[] memory blobVersionedHashes = new bytes[](transaction.blobVersionedHashes.length);
        for (uint256 i = 0; i < transaction.blobVersionedHashes.length; i++) {
            // Decode bytes32 as uint256 (RLPWriter doesn't support bytes32 but they are equivalent)
            blobVersionedHashes[i] = RLPWriter.writeUint(uint256(transaction.blobVersionedHashes[i]));
        }
        fields[10] = RLPWriter.writeList(blobVersionedHashes);

        // EIP-2718 envelope
        unsignedTx = abi.encodePacked(uint8(TxType.Eip4844), RLPWriter.writeList(fields));
    }
}
