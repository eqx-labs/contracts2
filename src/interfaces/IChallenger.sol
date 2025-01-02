// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

interface IChallenger {
    // Enum representing the possible statuses of a challenge.
    enum ChallengeStatus {
        Open,        // Challenge is active and unresolved.
        Defended,    // Challenge has been successfully defended.
        Breached     // Challenge has been breached and proven invalid.
    }

    // Represents a challenge issued by a challenger.
    struct Challenge {
        bytes32 id;                      // Unique identifier for the challenge.
        uint48 openedAt;                 // Timestamp when the challenge was opened.
        ChallengeStatus status;          // Current status of the challenge.
        uint256 targetSlot;              // Slot associated with the challenge.
        address challenger;              // Address of the challenger initiating the challenge.
        address commitmentSigner;        // Address of the entity signing the commitment.
        address commitmentReceiver;      // Address of the entity receiving the commitment.
        TransactionData[] committedTxs;  // Array of committed transactions related to the challenge.
    }

    // Represents a signed commitment including the slot and transaction signature.
    struct SignedCommitment {
        uint64 slot;       // Slot number associated with the commitment.
        bytes signature;   // Signature of the commitment.
        bytes signedTx;    // Serialized transaction data signed by the commitment signer.
    }

    // Details of a transaction within the challenge context.
    struct TransactionData {
        bytes32 txHash;     // Hash of the transaction.
        uint256 nonce;      // Nonce of the transaction.
        uint256 gasLimit;   // Gas limit specified for the transaction.
    }

    // Represents a block header used in the proof of inclusion and verification.
    struct BlockHeaderData {
        bytes32 parentHash;   // Hash of the parent block.
        bytes32 stateRoot;    // Root hash of the state trie.
        bytes32 txRoot;       // Root hash of the transaction trie.
        uint256 blockNumber;  // Block number of the current block.
        uint256 timestamp;    // Timestamp of the block.
        uint256 baseFee;      // Base fee per gas unit in the block.
    }

    // Contains account-related data for inclusion proof verification.
    struct AccountData {
        uint256 nonce;       // Account nonce.
        uint256 balance;     // Account balance in wei.
    }

    // Represents a proof required to resolve a challenge.
    struct Proof {
        uint256 inclusionBlockNumber;       // Block number where transactions are included.
        bytes previousBlockHeaderRLP;       // RLP-encoded header of the previous block.
        bytes inclusionBlockHeaderRLP;      // RLP-encoded header of the inclusion block.
        bytes accountMerkleProof;           // Merkle proof for account inclusion in the state trie.
        bytes[] txMerkleProofs;             // Merkle proofs for committed transactions in the tx trie.
        uint256[] txIndexesInBlock;         // Indexes of the committed transactions within the block.
    }

    // Custom error messages for specific failure cases.
    error SlotInTheFuture();                 // Error when the specified slot is in the future.
    error BlockIsNotFinalized();             // Error when the block is not finalized.
    error IncorrectChallengeBond();          // Error for an incorrect challenge bond amount.
    error ChallengeAlreadyExists();          // Error when a challenge with the same ID already exists.
    error ChallengeAlreadyResolved();        // Error when attempting to resolve an already resolved challenge.
    error ChallengeDoesNotExist();           // Error for a non-existent challenge.
    error BlockIsTooOld();                   // Error when the block is too old.
    error InvalidBlockHash();                // Error for an invalid block hash.
    error InvalidParentBlockHash();          // Error for an invalid parent block hash.
    error AccountDoesNotExist();             // Error when the account does not exist in the state trie.
    error TransactionNotIncluded();          // Error when a transaction is not included in the block.
    error WrongTransactionHashProof();       // Error for an invalid transaction hash proof.
    error InvalidBlockNumber();              // Error for an invalid block number.
    error BondTransferFailed();              // Error when transferring the bond fails.
    error ChallengeNotExpired();             // Error when trying to resolve a challenge that has not expired.
    error ChallengeExpired();                // Error for expired challenges.
    error EmptyCommitments();                // Error for challenges with no commitments.
    error UnexpectedMixedSenders();          // Error for commitments from mixed senders.
    error UnexpectedMixedSlots();            // Error for commitments from mixed slots.
    error UnexpectedMixedSigners();          // Error for commitments with mixed signers.
    error UnexpectedNonceOrder();            // Error for unexpected nonce order in transactions.
    error InvalidProofsLength();             // Error when proofs length is invalid.
    error BeaconRootNotFound();              // Error when the beacon root is not found.

    // Events emitted during the challenge lifecycle.
    event ChallengeOpened(bytes32 indexed challengeId, address indexed challenger, address indexed commitmentSigner);
    event ChallengeDefended(bytes32 indexed challengeId);
    event ChallengeBreached(bytes32 indexed challengeId);

    // Returns all challenges that have been created.
    function getAllChallenges() external view returns (Challenge[] memory);

    // Returns all challenges that are currently open and unresolved.
    function getOpenChallenges() external view returns (Challenge[] memory);

    // Fetches the details of a specific challenge by its ID.
    function getChallengeByID(bytes32 challengeID) external view returns (Challenge memory);

    // Opens a new challenge with the provided commitments.
    function openChallenge(SignedCommitment[] calldata commitments) external payable;

    // Resolves an expired challenge, releasing any bonds associated with it.
    function resolveExpiredChallenge(bytes32 challengeID) external;

    // Resolves an open challenge by validating the provided proof.
    function resolveOpenChallenge(bytes32 challengeID, Proof calldata proof) external;
}
