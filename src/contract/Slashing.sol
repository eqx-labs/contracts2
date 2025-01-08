// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";

import {SecureMerkleTrie} from "./lib/trie/SecureMerkleTrie.sol";
import {MerkleTrie} from "./lib/trie/MerkleTrie.sol";
import {RLPReader} from "./lib/rlp/RLPReader.sol";
import {RLPWriter} from "./lib/rlp/RLPWriter.sol";
import {TransactionDecoder} from "./lib/TransactionDecoder.sol";
import {IChallenger} from "./interfaces/IChallenger.sol";
import {ISystemParameters} from "./interfaces/IParameters.sol";

contract Slashing is IChallenger, OwnableUpgradeable, UUPSUpgradeable {
    using RLPReader for bytes;
    using RLPReader for RLPReader.RLPItem;
    using TransactionDecoder for bytes;
    using TransactionDecoder for TransactionDecoder.Transaction;
    using EnumerableSet for EnumerableSet.Bytes32Set;

    // Storage variables
    ISystemParameters public params;
    EnumerableSet.Bytes32Set internal activeDisputes;
    mapping(bytes32 => Dispute) internal disputeDetails;
    uint256[46] private __gap;

    // Initialize contract
    function initializeContract(
        address _owner,
        address _params
    ) public initializer {
        __Ownable_init(_owner);
        params = ISystemParameters(_params);
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    // View functions
    function fetchAllDisputes() public view returns (Dispute[] memory) {
        Dispute[] memory disputes = new Dispute[](activeDisputes.length());
        for (uint256 i = 0; i < activeDisputes.length(); i++) {
            disputes[i] = disputeDetails[activeDisputes.at(i)];
        }
        return disputes;
    }

    function fetchActiveDisputes() public view returns (Dispute[] memory) {
        uint256 activeCount = 0;
        for (uint256 i = 0; i < activeDisputes.length(); i++) {
            if (
                disputeDetails[activeDisputes.at(i)].currentState ==
                ChallengeState.Active
            ) {
                activeCount++;
            }
        }

        Dispute[] memory active = new Dispute[](activeCount);
        uint256 j = 0;
        for (uint256 i = 0; i < activeDisputes.length(); i++) {
            Dispute memory dispute = disputeDetails[activeDisputes.at(i)];
            if (dispute.currentState == ChallengeState.Active) {
                active[j] = dispute;
                j++;
            }
        }
        return active;
    }

    function fetchDisputeById(
        bytes32 disputeId
    ) public view returns (Dispute memory) {
        if (!activeDisputes.contains(disputeId)) {
            revert NonexistentDispute();
        }
        return disputeDetails[disputeId];
    }

    // Challenge creation
    function initiateDispute(
        Commitment[] calldata commitments
    ) public payable {
        if (commitments.length == 0) {
            revert EmptyCommitmentList();
        }

        if (msg.value != params.getChallengeBond()) {
            revert InvalidBondAmount();
        }

        bytes32 disputeId = generateDisputeId(commitments);

        if (activeDisputes.contains(disputeId)) {
            revert ExistingDispute();
        }

        uint256 targetSlot = commitments[0].slotNumber;
        if (targetSlot > getCurrentSlot() - params.getJustificationDelay()) {
            revert UnfinalizedBlock();
        }

        TransactionDetail[] memory txData = new TransactionDetail[](
            commitments.length
        );
        (
            address sender,
            address signer,
            TransactionDetail memory firstTx
        ) = extractCommitmentData(commitments[0]);
        txData[0] = firstTx;

        for (uint256 i = 1; i < commitments.length; i++) {
            (
                address otherSender,
                address otherSigner,
                TransactionDetail memory otherTx
            ) = extractCommitmentData(commitments[i]);

            txData[i] = otherTx;

            if (commitments[i].slotNumber != targetSlot) {
                revert MixedSlotError();
            }
            if (otherSender != sender) {
                revert MixedSignerError();
            }
            if (otherSigner != signer) {
                revert MixedSenderError();
            }
            if (otherTx.transactionNonce != txData[i - 1].transactionNonce + 1) {
                revert NonSequentialNonce();
            }
        }

        activeDisputes.add(disputeId);
        disputeDetails[disputeId] = Dispute({
            disputeId: disputeId,
            initiatedAt: Time.timestamp(),
            currentState: ChallengeState.Active,
            associatedSlot: targetSlot,
            initiator: msg.sender,
            signer: signer,
            recipient: sender,
            transactions: txData
        });
        emit DisputeOpened(disputeId, msg.sender, signer);
    }

    // Challenge resolution
    function resolveActiveDispute(
        bytes32 disputeId,
        VerificationProof calldata proof
    ) public {
        if (!activeDisputes.contains(disputeId)) {
            revert NonexistentDispute();
        }

        if (
            disputeDetails[disputeId].associatedSlot <
            getCurrentSlot() - params.getBlockhashEvmLookback()
        ) {
            revert ObsoleteBlock();
        }

        uint256 prevBlockNum = proof.inclusionBlockHeight - 1;
        if (
            prevBlockNum > block.number ||
            prevBlockNum < block.number - params.getBlockhashEvmLookback()
        ) {
            revert InvalidHeight();
        }

        bytes32 trustedPrevBlockHash = blockhash(proof.inclusionBlockHeight);
        processResolution(disputeId, trustedPrevBlockHash, proof);
    }

    function resolveExpiredDispute(bytes32 disputeId) public {
        if (!activeDisputes.contains(disputeId)) {
            revert NonexistentDispute();
        }

        Dispute storage dispute = disputeDetails[disputeId];

        if (dispute.currentState != ChallengeState.Active) {
            revert ResolvedDispute();
        }

        if (
            dispute.initiatedAt + params.getMaxChallengeDuration() >=
            Time.timestamp()
        ) {
            revert ExistingDispute();
        }

        finalizeDisputeResolution(ChallengeState.Violation, dispute);
    }

    // Internal functions
    function processResolution(
        bytes32 disputeId,
        bytes32 trustedPrevBlockHash,
        VerificationProof calldata proof
    ) internal {
        if (!activeDisputes.contains(disputeId)) {
            revert NonexistentDispute();
        }

        Dispute storage dispute = disputeDetails[disputeId];

        if (dispute.currentState != ChallengeState.Active) {
            revert ResolvedDispute();
        }

        if (
            dispute.initiatedAt + params.getMaxChallengeDuration() <
            Time.timestamp()
        ) {
            revert ExpiredDispute();
        }

        uint256 txCount = dispute.transactions.length;
        if (
            proof.transactionMerkleProofs.length != txCount ||
            proof.transactionIndexes.length != txCount
        ) {
            revert InvalidProofLength();
        }

        bytes32 prevBlockHash = keccak256(proof.previousBlockHeaderData);
        if (prevBlockHash != trustedPrevBlockHash) {
            revert MismatchedBlockHash();
        }

        BlockHeader memory prevHeader = parseBlockHeader(
            proof.previousBlockHeaderData
        );
        BlockHeader memory inclHeader = parseBlockHeader(
            proof.inclusionBlockHeaderData
        );

        if (inclHeader.parentBlockHash != prevBlockHash) {
            revert MismatchedParentHash();
        }

        (bool exists, bytes memory accRLP) = SecureMerkleTrie.get(
            abi.encodePacked(dispute.recipient),
            proof.stateMerkleProof,
            prevHeader.globalStateRoot
        );

        if (!exists) {
            revert MissingAccount();
        }

        AccountDetails memory account = parseAccount(accRLP);

        for (uint256 i = 0; i < txCount; i++) {
            TransactionDetail memory committedTx = dispute.transactions[i];

            if (account.accountNonce > committedTx.transactionNonce) {
                finalizeDisputeResolution(ChallengeState.SuccessfullyDefended, dispute);
                return;
            }

            if (account.accountBalance < inclHeader.gasBaseFee * committedTx.gas) {
                finalizeDisputeResolution(ChallengeState.SuccessfullyDefended, dispute);
                return;
            }

            account.accountBalance -= inclHeader.gasBaseFee * committedTx.gas;
            account.accountNonce++;

            bytes memory txLeaf = RLPWriter.writeUint(
                proof.transactionIndexes[i]
            );
            (bool txExists, bytes memory txRLP) = MerkleTrie.get(
                txLeaf,
                proof.transactionMerkleProofs[i],
                inclHeader.transactionRoot
            );

            if (!txExists) {
                revert MissingTransaction();
            }

            if (committedTx.transactionHash != keccak256(txRLP)) {
                revert InvalidTransactionHashProof();
            }
        }

        finalizeDisputeResolution(ChallengeState.SuccessfullyDefended, dispute);
    }

    function finalizeDisputeResolution(
        ChallengeState outcome,
        Dispute storage dispute
    ) internal {
        if (outcome == ChallengeState.SuccessfullyDefended) {
            dispute.currentState = ChallengeState.SuccessfullyDefended;
            distributeBondHalf(msg.sender);
            distributeBondHalf(dispute.signer);
            emit DisputeDefended(dispute.disputeId);
        } else if (outcome == ChallengeState.Violation) {
            dispute.currentState = ChallengeState.Violation;
            distributeBondFull(dispute.initiator);
            emit DisputeViolation(dispute.disputeId);
        }

        delete disputeDetails[dispute.disputeId];
        activeDisputes.remove(dispute.disputeId);
    }

    // Helper functions
    function extractCommitmentData(
        Commitment calldata commitment
    )
        internal
        pure
        returns (address sender, address signer, TransactionDetail memory txData)
    {
        signer = ECDSA.recover(
            computeCommitmentId(commitment),
            commitment.signatureData
        );
        TransactionDecoder.Transaction memory decodedTx = commitment
            .transaction
            .decodeEnveloped();
        sender = decodedTx.recoverSender();
        txData = TransactionDetail({
            transactionHash: keccak256(commitment.transaction),
            transactionNonce: decodedTx.nonce,
            gas: decodedTx.gasLimit
        });
    }

    function generateDisputeId(
        Commitment[] calldata commitments
    ) internal pure returns (bytes32) {
        bytes32[] memory sigs = new bytes32[](commitments.length);
        for (uint256 i = 0; i < commitments.length; i++) {
            sigs[i] = keccak256(commitments[i].signatureData);
        }
        return keccak256(abi.encodePacked(sigs));
    }

    function computeCommitmentId(
        Commitment calldata commitment
    ) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    keccak256(commitment.transaction),
                    toLittleEndian(commitment.slotNumber)
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
    ) internal pure returns (BlockHeader memory header) {
        RLPReader.RLPItem[] memory fields = headerRLP.toRLPItem().readList();
        header.parentBlockHash = fields[0].readBytes32();
        header.globalStateRoot = fields[3].readBytes32();
        header.transactionRoot = fields[4].readBytes32();
        header.height = fields[8].readUint256();
        header.blockTimestamp = fields[11].readUint256();
        header.gasBaseFee = fields[15].readUint256();
    }

    function parseAccount(
        bytes memory accountRLP
    ) internal pure returns (AccountDetails memory account) {
        RLPReader.RLPItem[] memory fields = accountRLP.toRLPItem().readList();
        account.accountNonce = fields[0].readUint256();
        account.accountBalance = fields[1].readUint256();
    }

    function distributeBondFull(address recipient) internal {
        (bool success, ) = payable(recipient).call{
            value: params.getChallengeBond()
        }("");
        if (!success) {
            revert BondTransferError();
        }
    }

    function distributeBondHalf(address recipient) internal {
        (bool success, ) = payable(recipient).call{
            value: params.getChallengeBond() / 2
        }("");
        if (!success) {
            revert BondTransferError();
        }
    }

    function getCurrentSlot() internal view returns (uint256) {
        return getSlotFromTime(block.timestamp);
    }

    function getSlotFromTime(
        uint256 timestamp
    ) internal view returns (uint256) {
        return
            (timestamp - params.getEth2GenesisTimestamp()) / params.getSlotTime();
    }

    function getTimeFromSlot(uint256 slot) internal view returns (uint256) {
        return params.getEth2GenesisTimestamp() + slot * params.getSlotTime();
    }

    function getBeaconRootForSlot(
        uint256 slot
    ) internal view returns (bytes32) {
        uint256 slotTime = params.getEth2GenesisTimestamp() +
            slot *
            params.getSlotTime();
        return getBeaconRootForTime(slotTime);
    }

    function getBeaconRootForTime(
        uint256 timestamp
    ) internal view returns (bytes32) {
        (bool success, bytes memory data) = params
            .getBeaconRootsContract()
            .staticcall(abi.encode(timestamp));
        if (!success || data.length == 0) {
            revert MissingBeaconRoot();
        }
        return abi.decode(data, (bytes32));
    }

    function _getSlotFromTimestamp(
        uint256 _timestamp
    ) internal view returns (uint256) {
        return
            (_timestamp - params.getEth2GenesisTimestamp()) / params.getSlotTime();
    }

    function _getBeaconBlockRootAtTimestamp(
        uint256 _timestamp
    ) internal view returns (bytes32) {
        (bool success, bytes memory data) = params
            .getBeaconRootsContract()
            .staticcall(abi.encode(_timestamp));

        if (!success || data.length == 0) {
            revert MissingBeaconRoot();
        }

        return abi.decode(data, (bytes32));
    }

    function _getBeaconBlockRootAtSlot(
        uint256 _slot
    ) internal view returns (bytes32) {
        uint256 slotTimestamp = params.getEth2GenesisTimestamp() +
            _slot *
            params.getSlotTime();
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
            getCurrentSlot() + params.getEip4788Window();
    }

 
}
