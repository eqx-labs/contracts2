// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import {OwnableUpgradeable} from "node_modules/@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "node_modules/@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {EnumerableSet} from "node_modules/@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ECDSA} from "lib/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import {Time} from "node_modules/@openzeppelin/contracts/utils/types/Time.sol";

import {SecureMerkleTrie} from "./lib/trie/SecureMerkleTrie.sol";
import {MerkleTrie} from "./lib/trie/MerkleTrie.sol";
import {RLPReader} from "./lib/rlp/RLPReader.sol";
import {RLPWriter} from "./lib/rlp/RLPWriter.sol";
import {TransactionDecoder} from "./lib/TransactionDecoder.sol";
import {IChallenger} from "./interfaces/IChallenger.sol";
import {IParameters} from "./interfaces/IParameters.sol";

contract ModifiedSlashing is IChallenger, OwnableUpgradeable, UUPSUpgradeable {
    using RLPReader for bytes;
    using RLPReader for RLPReader.RLPItem;
    using TransactionDecoder for bytes;
    using TransactionDecoder for TransactionDecoder.Transaction;
    using EnumerableSet for EnumerableSet.Bytes32Set;

    // Storage variables
    IParameters public params;
    EnumerableSet.Bytes32Set internal activeDisputes;
    mapping(bytes32 => Challenge) internal disputeDetails;
    uint256[46] private __gap;

    // Initialize contract
    function initializeContract(
        address _owner,
        address _params
    ) public initializer {
        __Ownable_init(_owner);
        params = IParameters(_params);
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    // View functions
    function listAllDisputes() public view returns (Challenge[] memory) {
        Challenge[] memory disputes = new Challenge[](activeDisputes.length());
        for (uint256 i = 0; i < activeDisputes.length(); i++) {
            disputes[i] = disputeDetails[activeDisputes.at(i)];
        }
        return disputes;
    }

    function listActiveDisputes() public view returns (Challenge[] memory) {
        uint256 activeCount = 0;
        for (uint256 i = 0; i < activeDisputes.length(); i++) {
            if (
                disputeDetails[activeDisputes.at(i)].status ==
                ChallengeStatus.Open
            ) {
                activeCount++;
            }
        }

        Challenge[] memory active = new Challenge[](activeCount);
        uint256 j = 0;
        for (uint256 i = 0; i < activeDisputes.length(); i++) {
            Challenge memory dispute = disputeDetails[activeDisputes.at(i)];
            if (dispute.status == ChallengeStatus.Open) {
                active[j] = dispute;
                j++;
            }
        }
        return active;
    }

    function getDisputeById(
        bytes32 disputeId
    ) public view returns (Challenge memory) {
        if (!activeDisputes.contains(disputeId)) {
            revert ChallengeDoesNotExist();
        }
        return disputeDetails[disputeId];
    }

    // Challenge creation
    function initiateDispute(
        SignedCommitment[] calldata commitments
    ) public payable {
        if (commitments.length == 0) {
            revert EmptyCommitments();
        }

        if (msg.value != params.CHALLENGE_BOND()) {
            revert IncorrectChallengeBond();
        }

        bytes32 disputeId = generateDisputeId(commitments);

        if (activeDisputes.contains(disputeId)) {
            revert ChallengeAlreadyExists();
        }

        uint256 targetSlot = commitments[0].slot;
        if (targetSlot > getCurrentSlot() - params.JUSTIFICATION_DELAY()) {
            revert BlockIsNotFinalized();
        }

        TransactionData[] memory txData = new TransactionData[](
            commitments.length
        );
        (
            address sender,
            address signer,
            TransactionData memory firstTx
        ) = extractCommitmentData(commitments[0]);
        txData[0] = firstTx;

        for (uint256 i = 1; i < commitments.length; i++) {
            (
                address otherSender,
                address otherSigner,
                TransactionData memory otherTx
            ) = extractCommitmentData(commitments[i]);

            txData[i] = otherTx;

            if (commitments[i].slot != targetSlot) {
                revert UnexpectedMixedSlots();
            }
            if (otherSender != sender) {
                revert UnexpectedMixedSenders();
            }
            if (otherSigner != signer) {
                revert UnexpectedMixedSigners();
            }
            if (otherTx.nonce != txData[i - 1].nonce + 1) {
                revert UnexpectedNonceOrder();
            }
        }

        activeDisputes.add(disputeId);
        disputeDetails[disputeId] = Challenge({
            id: disputeId,
            openedAt: Time.timestamp(),
            status: ChallengeStatus.Open,
            targetSlot: targetSlot,
            challenger: msg.sender,
            commitmentSigner: signer,
            commitmentReceiver: sender,
            committedTxs: txData
        });
        emit ChallengeOpened(disputeId, msg.sender, signer);
    }

    // Challenge resolution
    function resolveActiveDispute(
        bytes32 disputeId,
        Proof calldata proof
    ) public {
        if (!activeDisputes.contains(disputeId)) {
            revert ChallengeDoesNotExist();
        }

        if (
            disputeDetails[disputeId].targetSlot <
            getCurrentSlot() - params.BLOCKHASH_EVM_LOOKBACK()
        ) {
            revert BlockIsTooOld();
        }

        uint256 prevBlockNum = proof.inclusionBlockNumber - 1;
        if (
            prevBlockNum > block.number ||
            prevBlockNum < block.number - params.BLOCKHASH_EVM_LOOKBACK()
        ) {
            revert InvalidBlockNumber();
        }

        bytes32 trustedPrevBlockHash = blockhash(proof.inclusionBlockNumber);
        processResolution(disputeId, trustedPrevBlockHash, proof);
    }

    function resolveTimedOutDispute(bytes32 disputeId) public {
        if (!activeDisputes.contains(disputeId)) {
            revert ChallengeDoesNotExist();
        }

        Challenge storage dispute = disputeDetails[disputeId];

        if (dispute.status != ChallengeStatus.Open) {
            revert ChallengeAlreadyResolved();
        }

        if (
            dispute.openedAt + params.MAX_CHALLENGE_DURATION() >=
            Time.timestamp()
        ) {
            revert ChallengeNotExpired();
        }

        finalizeDisputeResolution(ChallengeStatus.Breached, dispute);
    }

    // Internal functions
    function processResolution(
        bytes32 disputeId,
        bytes32 trustedPrevBlockHash,
        Proof calldata proof
    ) internal {
        if (!activeDisputes.contains(disputeId)) {
            revert ChallengeDoesNotExist();
        }

        Challenge storage dispute = disputeDetails[disputeId];

        if (dispute.status != ChallengeStatus.Open) {
            revert ChallengeAlreadyResolved();
        }

        if (
            dispute.openedAt + params.MAX_CHALLENGE_DURATION() <
            Time.timestamp()
        ) {
            revert ChallengeExpired();
        }

        uint256 txCount = dispute.committedTxs.length;
        if (
            proof.txMerkleProofs.length != txCount ||
            proof.txIndexesInBlock.length != txCount
        ) {
            revert InvalidProofsLength();
        }

        bytes32 prevBlockHash = keccak256(proof.previousBlockHeaderRLP);
        if (prevBlockHash != trustedPrevBlockHash) {
            revert InvalidBlockHash();
        }

        BlockHeaderData memory prevHeader = parseBlockHeader(
            proof.previousBlockHeaderRLP
        );
        BlockHeaderData memory inclHeader = parseBlockHeader(
            proof.inclusionBlockHeaderRLP
        );

        if (inclHeader.parentHash != prevBlockHash) {
            revert InvalidParentBlockHash();
        }

        (bool exists, bytes memory accRLP) = SecureMerkleTrie.get(
            abi.encodePacked(dispute.commitmentReceiver),
            proof.accountMerkleProof,
            prevHeader.stateRoot
        );

        if (!exists) {
            revert AccountDoesNotExist();
        }

        AccountData memory account = parseAccount(accRLP);

        for (uint256 i = 0; i < txCount; i++) {
            TransactionData memory committedTx = dispute.committedTxs[i];

            if (account.nonce > committedTx.nonce) {
                finalizeDisputeResolution(ChallengeStatus.Defended, dispute);
                return;
            }

            if (account.balance < inclHeader.baseFee * committedTx.gasLimit) {
                finalizeDisputeResolution(ChallengeStatus.Defended, dispute);
                return;
            }

            account.balance -= inclHeader.baseFee * committedTx.gasLimit;
            account.nonce++;

            bytes memory txLeaf = RLPWriter.writeUint(
                proof.txIndexesInBlock[i]
            );
            (bool txExists, bytes memory txRLP) = MerkleTrie.get(
                txLeaf,
                proof.txMerkleProofs[i],
                inclHeader.txRoot
            );

            if (!txExists) {
                revert TransactionNotIncluded();
            }

            if (committedTx.txHash != keccak256(txRLP)) {
                revert WrongTransactionHashProof();
            }
        }

        finalizeDisputeResolution(ChallengeStatus.Defended, dispute);
    }

    function finalizeDisputeResolution(
        ChallengeStatus outcome,
        Challenge storage dispute
    ) internal {
        if (outcome == ChallengeStatus.Defended) {
            dispute.status = ChallengeStatus.Defended;
            distributeBondHalf(msg.sender);
            distributeBondHalf(dispute.commitmentSigner);
            emit ChallengeDefended(dispute.id);
        } else if (outcome == ChallengeStatus.Breached) {
            dispute.status = ChallengeStatus.Breached;
            distributeBondFull(dispute.challenger);
            emit ChallengeBreached(dispute.id);
        }

        delete disputeDetails[dispute.id];
        activeDisputes.remove(dispute.id);
    }

    // Helper functions
    function extractCommitmentData(
        SignedCommitment calldata commitment
    )
        internal
        pure
        returns (address sender, address signer, TransactionData memory txData)
    {
        signer = ECDSA.recover(
            computeCommitmentId(commitment),
            commitment.signature
        );
        TransactionDecoder.Transaction memory decodedTx = commitment
            .signedTx
            .decodeEnveloped();
        sender = decodedTx.recoverSender();
        txData = TransactionData({
            txHash: keccak256(commitment.signedTx),
            nonce: decodedTx.nonce,
            gasLimit: decodedTx.gasLimit
        });
    }

    function generateDisputeId(
        SignedCommitment[] calldata commitments
    ) internal pure returns (bytes32) {
        bytes32[] memory sigs = new bytes32[](commitments.length);
        for (uint256 i = 0; i < commitments.length; i++) {
            sigs[i] = keccak256(commitments[i].signature);
        }
        return keccak256(abi.encodePacked(sigs));
    }

    function computeCommitmentId(
        SignedCommitment calldata commitment
    ) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    keccak256(commitment.signedTx),
                    toLittleEndian(commitment.slot)
                )
            );
    }

    function toLittleEndian(uint64 x) internal pure returns (bytes memory) {
        bytes memory b = new bytes(8);
        for (uint256 i = 0; i < 8; i++) {
            b[i] = bytes1(uint8(x >> (8 * i)));
        }
        return b;
    }

    function parseBlockHeader(
        bytes calldata headerRLP
    ) internal pure returns (BlockHeaderData memory header) {
        RLPReader.RLPItem[] memory fields = headerRLP.toRLPItem().readList();
        header.parentHash = fields[0].readBytes32();
        header.stateRoot = fields[3].readBytes32();
        header.txRoot = fields[4].readBytes32();
        header.blockNumber = fields[8].readUint256();
        header.timestamp = fields[11].readUint256();
        header.baseFee = fields[15].readUint256();
    }

    function parseAccount(
        bytes memory accountRLP
    ) internal pure returns (AccountData memory account) {
        RLPReader.RLPItem[] memory fields = accountRLP.toRLPItem().readList();
        account.nonce = fields[0].readUint256();
        account.balance = fields[1].readUint256();
    }

    function distributeBondFull(address recipient) internal {
        (bool success, ) = payable(recipient).call{
            value: params.CHALLENGE_BOND()
        }("");
        if (!success) {
            revert BondTransferFailed();
        }
    }

    function distributeBondHalf(address recipient) internal {
        (bool success, ) = payable(recipient).call{
            value: params.CHALLENGE_BOND() / 2
        }("");
        if (!success) {
            revert BondTransferFailed();
        }
    }

    function getCurrentSlot() internal view returns (uint256) {
        return getSlotFromTime(block.timestamp);
    }

    function getSlotFromTime(
        uint256 timestamp
    ) internal view returns (uint256) {
        return
            (timestamp - params.ETH2_GENESIS_TIMESTAMP()) / params.SLOT_TIME();
    }

    function getTimeFromSlot(uint256 slot) internal view returns (uint256) {
        return params.ETH2_GENESIS_TIMESTAMP() + slot * params.SLOT_TIME();
    }

    function getBeaconRootForSlot(
        uint256 slot
    ) internal view returns (bytes32) {
        uint256 slotTime = params.ETH2_GENESIS_TIMESTAMP() +
            slot *
            params.SLOT_TIME();
        return getBeaconRootForTime(slotTime);
    }

    function getBeaconRootForTime(
        uint256 timestamp
    ) internal view returns (bytes32) {
        (bool success, bytes memory data) = params
            .BEACON_ROOTS_CONTRACT()
            .staticcall(abi.encode(timestamp));
        if (!success || data.length == 0) {
            revert BeaconRootNotFound();
        }
        return abi.decode(data, (bytes32));
    }

    function _getSlotFromTimestamp(
        uint256 _timestamp
    ) internal view returns (uint256) {
        return
            (_timestamp - params.ETH2_GENESIS_TIMESTAMP()) / params.SLOT_TIME();
    }

    function _getBeaconBlockRootAtTimestamp(
        uint256 _timestamp
    ) internal view returns (bytes32) {
        (bool success, bytes memory data) = params
            .BEACON_ROOTS_CONTRACT()
            .staticcall(abi.encode(_timestamp));

        if (!success || data.length == 0) {
            revert BeaconRootNotFound();
        }

        return abi.decode(data, (bytes32));
    }

    function _getBeaconBlockRootAtSlot(
        uint256 _slot
    ) internal view returns (bytes32) {
        uint256 slotTimestamp = params.ETH2_GENESIS_TIMESTAMP() +
            _slot *
            params.SLOT_TIME();
        return _getBeaconBlockRootAtTimestamp(slotTimestamp);
    }

    function getLatestBeaconRoot() internal view returns (bytes32) {
        uint256 latestSlot = _getSlotFromTimestamp(block.timestamp);
        return _getBeaconBlockRootAtSlot(latestSlot);
    }

    /// @notice Check if a timestamp is within the EIP-4788 window
    /// @param _timestamp The timestamp
    /// @return True if the timestamp is within the EIP-4788 window, false otherwise
    function _isWithinEIP4788Window(
        uint256 _timestamp
    ) internal view returns (bool) {
        return
            _getSlotFromTimestamp(_timestamp) <=
            getCurrentSlot() + params.EIP4788_WINDOW();
    }

    function getAllChallenges()
        external
        view
        override
        returns (Challenge[] memory)
    {}

    function getOpenChallenges()
        external
        view
        override
        returns (Challenge[] memory)
    {}

    function getChallengeByID(
        bytes32 challengeID
    ) external view override returns (Challenge memory) {}

    function openChallenge(
        SignedCommitment[] calldata commitments
    ) external payable override {}

    function resolveExpiredChallenge(bytes32 challengeID) external override {}

    function resolveOpenChallenge(
        bytes32 challengeID,
        Proof calldata proof
    ) external override {}
}
