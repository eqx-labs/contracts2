// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";
import {ValidationProcessor} from "./ValidationProcessor.sol";

import {IParameters} from "../interfaces/IParameters.sol";

import {RLPReader} from "../lib/rlp/RLPReader.sol";
import {RLPWriter} from "../lib/rlp/RLPWriter.sol";
import {TransactionDecoder} from "../lib/TransactionDecoder.sol";





contract ValidatorSlashingCore is
    OwnableUpgradeable,
    UUPSUpgradeable,
    ValidationProcessor



    
{
    using EnumerableSet for EnumerableSet.Bytes32Set;

    uint256[46] private __gap;

    function initialize(address _owner, address _parameters) public initializer {
        __Ownable_init(_owner);
        validatorParams = IParameters(_parameters);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function retrieveAllValidations() public view returns (ValidationRecord[] memory) {
        ValidationRecord[] memory allValidations = new ValidationRecord[](validationSetIDs.length());
        for (uint256 i = 0; i < validationSetIDs.length(); i++) {
            allValidations[i] = validationRecords[validationSetIDs.at(i)];
        }
        return allValidations;
    }

    function retrieveAwaitingValidations() public view returns (ValidationRecord[] memory) {
        uint256 pendingCount = 0;
        for (uint256 i = 0; i < validationSetIDs.length(); i++) {
            if (validationRecords[validationSetIDs.at(i)].phase == ValidationPhase.Awaiting) {
                pendingCount++;
            }
        }

        ValidationRecord[] memory pendingValidations = new ValidationRecord[](pendingCount);
        uint256 j = 0;
        for (uint256 i = 0; i < validationSetIDs.length(); i++) {
            ValidationRecord memory record = validationRecords[validationSetIDs.at(i)];
            if (record.phase == ValidationPhase.Awaiting) {
                pendingValidations[j] = record;
                j++;
            }
        }
        return pendingValidations;
    }

    function retrieveValidationById(bytes32 validationId) public view returns (ValidationRecord memory) {
        if (!validationSetIDs.contains(validationId)) {
            revert ValidationNotFoundError();
        }
        return validationRecords[validationId];
    }

  function initiateValidation(AuthorizedMessagePacket[] calldata authorizations) public payable {
        if (authorizations.length == 0) {
            revert EmptyAuthorizationError();
        }

        if (msg.value != validatorParams.DISPUTE_SECURITY_DEPOSIT()) {
            revert InvalidBondAmountError();
        }

        bytes32 validationId = _computeValidationId(authorizations);
        if (validationSetIDs.contains(validationId)) {
            revert DuplicateValidationError();
        }

        uint256 targetEpoch = authorizations[0].epoch;
        if (targetEpoch > _getCurrentEpoch() - validatorParams.FINALIZATION_DELAY_SLOTS()) {
            revert UnfinalizedSegmentError();
        }

        MessageDetails[] memory messagesData = new MessageDetails[](authorizations.length);
        (address msgSender, address witnessAuthorizer, MessageDetails memory firstMessageData) = 
            _recoverAuthorizationData(authorizations[0]);

        messagesData[0] = firstMessageData;

        for (uint256 i = 1; i < authorizations.length; i++) {
            (address otherMsgSender, address otherAuthorizer, MessageDetails memory otherMessageData) =
                _recoverAuthorizationData(authorizations[i]);

            messagesData[i] = otherMessageData;

            if (authorizations[i].epoch != targetEpoch) {
                revert MixedEpochError();
            }
            if (otherMsgSender != msgSender) {
                revert MixedValidatorError();
            }
            if (otherAuthorizer != witnessAuthorizer) {
                revert MixedAuthorizerError();
            }
            if (otherMessageData.sequence != messagesData[i - 1].sequence + 1) {
                revert InvalidSequenceError();
            }
        }

        validationSetIDs.add(validationId);
        validationRecords[validationId] = ValidationRecord({
            attestationId: validationId,
            timestampInit: Time.timestamp(),
            phase: ValidationPhase.Awaiting,
            targetEpoch: targetEpoch,
            validator: msg.sender,
            witnessAuthorizer: witnessAuthorizer,
            protocolDestination: msgSender,
            authorizedMessages: messagesData
        });

        emit ValidationInitiated(validationId, msg.sender, witnessAuthorizer);
    }

     function processTimedOutValidation(bytes32 validationId) public {
        if (!validationSetIDs.contains(validationId)) {
            revert ValidationNotFoundError();
        }

        ValidationRecord storage record = validationRecords[validationId];

        if (record.phase != ValidationPhase.Awaiting) {
            revert ValidationAlreadySettledError();
        }

        if (record.timestampInit + validatorParams.CHALLENGE_TIMEOUT_PERIOD() >= Time.timestamp()) {
            revert ValidationStillActiveError();
        }

        _finalizeValidation(ValidationPhase.Rejected, record);
    }

     function concludeAwaitingValidation(bytes32 validationId, ValidationEvidence calldata evidence) public {
        if (validationRecords[validationId].targetEpoch <_getCurrentEpoch() - validatorParams.CHAIN_HISTORY_LIMIT()) {
            revert SegmentTooAgedError();
        }

        uint256 previousSegmentHeight = evidence.incorporationHeight - 1;
        if (
            previousSegmentHeight > block.number ||
            previousSegmentHeight < block.number - validatorParams.CHAIN_HISTORY_LIMIT()
        ) {
            revert InvalidSegmentHeightError();
        }

        bytes32 trustedPreviousSegmentHash = blockhash(evidence.incorporationHeight);
        _verifyAndFinalize(validationId, trustedPreviousSegmentHash, evidence);
    }


  
}