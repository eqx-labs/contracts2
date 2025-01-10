// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;
interface ISlashing {
    enum ValidationPhase {
        Awaiting,
        Confirmed,
        Rejected
    }
    
    struct ValidationRecord {
        bytes32 attestationId;
        uint48 timestampInit;
        ValidationPhase phase;
        uint256 targetEpoch;
        address validator;
        address witnessAuthorizer;
        address protocolDestination;
        MessageDetails[] authorizedMessages;
    }
    
    struct AuthorizedMessagePacket {
        uint64 epoch;
        bytes authorization;
        bytes payload;
    }
    
    struct MessageDetails {
        bytes32 messageDigest;
        uint256 sequence;
        uint256 fuelLimit;
    }
    
    struct ChainSegmentInfo {
        bytes32 ancestorDigest;
        bytes32 worldStateDigest;
        bytes32 messageTreeDigest;
        uint256 segmentHeight;
        uint256 chronograph;
        uint256 networkFee;
    }
    
    struct ParticipantState {
        uint256 sequence;
        uint256 holdings;
    }
    
    struct ValidationEvidence {
        uint256 incorporationHeight;
        bytes precedingSegmentRLP;
        bytes incorporationSegmentRLP;
        bytes participantMerkleEvidence;
        bytes[] messageMerkleEvidence;
        uint256[] messagePositions;
    }
    
    error FutureEpochError();
    error UnfinalizedSegmentError();
    error InvalidBondAmountError();
    error DuplicateValidationError();
    error ValidationAlreadySettledError();
    error ValidationNotFoundError();
    error SegmentTooAgedError();
    error InvalidSegmentDigestError();
    error InvalidAncestorDigestError();
    error ParticipantNotFoundError();
    error MessageNotFoundError();
    error InvalidMessageEvidenceError();
    error InvalidSegmentHeightError();
    error BondTransferFailedError();
    error ValidationStillActiveError();
    error ValidationTimedOutError();
    error EmptyAuthorizationError();
    error MixedValidatorError();
    error MixedEpochError();
    error MixedAuthorizerError();
    error InvalidSequenceError();
    error InvalidEvidenceCountError();
    error ConsensusRootMissingError();
    
    event ValidationInitiated(bytes32 indexed attestationId, address indexed validator, address indexed witnessAuthorizer);
    event ValidationConfirmed(bytes32 indexed attestationId);
    event ValidationRejected(bytes32 indexed attestationId);
    
    function retrieveAllValidations() external view returns (ValidationRecord[] memory);
    
    function retrieveAwaitingValidations() external view returns (ValidationRecord[] memory);
    
    function retrieveValidationById(
        bytes32 attestationId
    ) external view returns (ValidationRecord memory);
    
    function initiateValidation(
        AuthorizedMessagePacket[] calldata authorizations
    ) external payable;
    
    function processTimedOutValidation(
        bytes32 attestationId
    ) external;
    
    function concludeAwaitingValidation(
        bytes32 attestationId, 
        ValidationEvidence calldata evidence
    ) external;
}