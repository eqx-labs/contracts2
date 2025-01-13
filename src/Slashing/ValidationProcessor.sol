// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";

import {RLPReader} from "../library/rlp/RLPReader.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {TransactionDecoder} from "../library/TransactionDecoder.sol";
import {ValidationUtility} from "./ValidationUtility.sol";
import {IParameters} from "../interfaces/IParameters.sol";

contract ValidationProcessor is
    OwnableUpgradeable,
    UUPSUpgradeable,
    ValidationUtility
{
    using TransactionDecoder for TransactionDecoder.Transaction;

    uint256[46] private __gap;

    function initialize(
        address _owner,
        address _parameters
    ) public initializer {
        __Ownable_init(_owner);
        validatorParams = IParameters(_parameters);
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    function concludeAwaitingValidation(
        bytes32 validationId,
        ValidationEvidence calldata evidence
    ) public {
        if (
            validationRecords[validationId].targetEpoch <
            _getCurrentEpoch() - validatorParams.CHAIN_HISTORY_LIMIT()
        ) {
            revert SegmentTooAgedError();
        }

        uint256 previousSegmentHeight = evidence.incorporationHeight - 1;
        if (
            previousSegmentHeight > block.number ||
            previousSegmentHeight <
            block.number - validatorParams.CHAIN_HISTORY_LIMIT()
        ) {
            revert InvalidSegmentHeightError();
        }

        bytes32 trustedPreviousSegmentHash = blockhash(
            evidence.incorporationHeight
        );
        verifyAndFinalize(validationId, trustedPreviousSegmentHash, evidence);
    }

    function _getTimestampFromEpoch(
        uint256 _epoch
    ) internal view returns (uint256) {
        return
            validatorParams.CONSENSUS_LAUNCH_TIMESTAMP() +
            _epoch *
            validatorParams.VALIDATOR_EPOCH_TIME();
    }

    function _getConsensusRootAt(
        uint256 _epoch
    ) internal view returns (bytes32) {
        uint256 slotTimestamp = validatorParams.CONSENSUS_LAUNCH_TIMESTAMP() +
            _epoch *
            validatorParams.VALIDATOR_EPOCH_TIME();
        return _getConsensusRootFromTimestamp(slotTimestamp);
    }

    function _getConsensusRootFromTimestamp(
        uint256 _timestamp
    ) internal view returns (bytes32) {
        (bool success, bytes memory data) = validatorParams
            .CONSENSUS_BEACON_ROOT_ADDRESS()
            .staticcall(abi.encode(_timestamp));

        if (!success || data.length == 0) {
            revert ConsensusRootMissingError();
        }

        return abi.decode(data, (bytes32));
    }

    function _getLatestBeaconBlockRoot() internal view returns (bytes32) {
        uint256 latestSlot = _getEpochFromTimestamp(block.timestamp);
        return _getConsensusRootAt(latestSlot);
    }

    function _isWithinEIP4788Window(
        uint256 _timestamp
    ) internal view returns (bool) {
        return
            _getEpochFromTimestamp(_timestamp) <=
            _getCurrentEpoch() + validatorParams.BEACON_TIME_WINDOW();
    }
}
