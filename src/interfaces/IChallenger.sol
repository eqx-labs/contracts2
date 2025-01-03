// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

interface IChallenger {
    // Enum representing the possible statuses of a challenge.
    enum ChallengeState {
        Active,        // Challenge is active and unresolved.
        SuccessfullyDefended, // Challenge has been successfully defended.
        Violation      // Challenge has been breached and proven invalid.
    }

    // Represents a challenge issued by a challenger.
    struct Dispute {
        bytes32 disputeId;                 // Unique identifier for the dispute.
        uint48 initiatedAt;                // Timestamp when the dispute was initiated.
        ChallengeState currentState;       // Current state of the dispute.
        uint256 associatedSlot;            // Slot associated with the dispute.
        address initiator;                 // Address of the challenger initiating the dispute.
        address signer;                    // Address of the entity signing the commitment.
        address recipient;                 // Address of the entity receiving the commitment.
        TransactionDetail[] transactions;  // Array of committed transactions related to the dispute.
    }

    // Represents a signed commitment including the slot and transaction signature.
    struct Commitment {
        uint64 slotNumber;   // Slot number associated with the commitment.
        bytes signatureData; // Signature of the commitment.
        bytes transaction;   // Serialized transaction data signed by the signer.
    }

    // Details of a transaction within the dispute context.
    struct TransactionDetail {
        bytes32 transactionHash;  // Hash of the transaction.
        uint256 transactionNonce; // Nonce of the transaction.
        uint256 gas;              // Gas limit specified for the transaction.
    }

    // Represents a block header used in the proof of inclusion and verification.
    struct BlockHeader {
        bytes32 parentBlockHash;   // Hash of the parent block.
        bytes32 globalStateRoot;   // Root hash of the global state trie.
        bytes32 transactionRoot;   // Root hash of the transaction trie.
        uint256 height;            // Block number of the current block.
        uint256 blockTimestamp;    // Timestamp of the block.
        uint256 gasBaseFee;        // Base fee per gas unit in the block.
    }

    // Contains account-related data for inclusion proof verification.
    struct AccountDetails {
        uint256 accountNonce;   // Account nonce.
        uint256 accountBalance; // Account balance in wei.
    }

    // Represents a proof required to resolve a dispute.
    struct VerificationProof {
        uint256 inclusionBlockHeight;   // Block height where transactions are included.
        bytes previousBlockHeaderData;  // Encoded header of the previous block.
        bytes inclusionBlockHeaderData; // Encoded header of the inclusion block.
        bytes stateMerkleProof;         // Merkle proof for account inclusion in the state trie.
        bytes[] transactionMerkleProofs; // Merkle proofs for committed transactions in the tx trie.
        uint256[] transactionIndexes;  // Indexes of the committed transactions within the block.
    }

    // Custom error messages for specific failure cases.
    error FutureSlot();                   // Error when the specified slot is in the future.
    error UnfinalizedBlock();             // Error when the block is not finalized.
    error InvalidBondAmount();            // Error for an incorrect bond amount.
    error ExistingDispute();              // Error when a dispute with the same ID already exists.
    error ResolvedDispute();              // Error when attempting to resolve an already resolved dispute.
    error NonexistentDispute();           // Error for a non-existent dispute.
    error ObsoleteBlock();                // Error when the block is too old.
    error MismatchedBlockHash();          // Error for an invalid block hash.
    error MismatchedParentHash();         // Error for an invalid parent block hash.
    error MissingAccount();               // Error when the account does not exist in the state trie.
    error MissingTransaction();           // Error when a transaction is not included in the block.
    error InvalidTransactionHashProof();  // Error for an invalid transaction hash proof.
    error InvalidHeight();                // Error for an invalid block number.
    error BondTransferError();            // Error when transferring the bond fails.
    error ActiveDispute();                // Error when trying to resolve a dispute that has not expired.
    error ExpiredDispute();               // Error for expired disputes.
    error EmptyCommitmentList();          // Error for disputes with no commitments.
    error MixedSenderError();             // Error for commitments from mixed senders.
    error MixedSlotError();               // Error for commitments from mixed slots.
    error MixedSignerError();             // Error for commitments with mixed signers.
    error NonSequentialNonce();           // Error for unexpected nonce order in transactions.
    error InvalidProofLength();           // Error when proof length is invalid.
    error MissingBeaconRoot();            // Error when the beacon root is not found.

    // Events emitted during the dispute lifecycle.
    event DisputeOpened(bytes32 indexed disputeId, address indexed initiator, address indexed signer);
    event DisputeDefended(bytes32 indexed disputeId);
    event DisputeViolation(bytes32 indexed disputeId);

    // Returns all disputes that have been created.
    function fetchAllDisputes() external view returns (Dispute[] memory);

    // Returns all disputes that are currently active and unresolved.
    function fetchActiveDisputes() external view returns (Dispute[] memory);

    // Fetches the details of a specific dispute by its ID.
    function fetchDisputeById(bytes32 disputeId) external view returns (Dispute memory);

    // Opens a new dispute with the provided commitments.
    function initiateDispute(Commitment[] calldata commitments) external payable;

    // Resolves an expired dispute, releasing any bonds associated with it.
    function resolveExpiredDispute(bytes32 disputeId) external;

    // Resolves an active dispute by validating the provided proof.
    function resolveActiveDispute(bytes32 disputeId, VerificationProof calldata proof) external;
}
