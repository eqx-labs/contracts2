// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {OperatorMapWithTime} from "./lib/OperatorMapWithTime.sol"; 
import {EnumerableMap} from "./lib/EnumerableMap.sol";

import {IParameters} from "./interfaces/IParameters.sol";
import {IMiddleware} from "./interfaces/IMiddleware.sol";
import {IValidator} from "./interfaces/IValidator.sol";
import {IManager} from "./interfaces/IManager.sol";

/// @title  Manager
/// @notice The  Manager contract is responsible for managing operators & restaking middlewares, and is the
/// entrypoint contract for all related queries for off-chain consumers.
/// @dev This contract is upgradeable using the UUPSProxy pattern. Storage layout remains fixed across upgrades
/// with the use of storage gaps.
/// See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
/// To validate the storage layout, use the Openzeppelin Foundry Upgrades toolkit.
/// You can also validate manually with forge: forge inspect <contract> storage-layout --pretty
contract Registry is IManager, OwnableUpgradeable, UUPSUpgradeable {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableMap for EnumerableMap.OperatorMap;
    using OperatorMapWithTime for EnumerableMap.OperatorMap;

    // ========= STORAGE =========
    /// @notice Start timestamp of the first epoch.
    uint48 public START_TIMESTAMP;

    /// @notice  Parameters contract.
    IParameters public parameters;

    /// @notice Validators registry, where validators are registered via their
    /// BLS pubkey and are assigned a sequence number.
    IValidator public validators;

    IMiddleware public middleware;

    /// @notice Set of operator addresses that have opted in to  Protocol.
    EnumerableMap.OperatorMap private operators;

    /// @notice Set of restaking protocols supported. Each address corresponds to the
    /// associated  Middleware contract.
    EnumerableSet.AddressSet private restakingProtocols;

    // --> Storage layout marker: 7 slots

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     * This can be validated with the Openzeppelin Foundry Upgrades toolkit.
     *
     * Total storage slots: 50
     */
    uint256[43] private __gap;

    modifier onlyMiddleware() {
        if (!restakingProtocols.contains(msg.sender)) {
            revert UnauthorizedMiddleware();
        }
        _;
    }

    // ========= INITIALIZER & PROXY FUNCTIONALITY ========== //

    /// @notice The initializer for the Manager contract.
    /// @param _validators The address of the validators registry.
    function initialize(address _owner, address _parameters, address _validators) public initializer {
        __Ownable_init(_owner);

        parameters = IParameters(_parameters);
        validators = IValidator(_validators);

        START_TIMESTAMP = Time.timestamp();
    }

    function initializeV2(address _owner, address _parameters, address _validators) public reinitializer(2) {
        __Ownable_init(_owner);

        parameters = IParameters(_parameters);
        validators = IValidator(_validators);

        START_TIMESTAMP = Time.timestamp();
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    // ========= VIEW FUNCTIONS =========

    function getEpochStartTs(
        uint48 epoch
    ) public view returns (uint48 timestamp) {
        return START_TIMESTAMP + epoch * parameters.EPOCH_DURATION();
    }

    /// @notice Get the epoch at a given timestamp.
    function getEpochAtTs(
        uint48 timestamp
    ) public view returns (uint48 epoch) {
        return (timestamp - START_TIMESTAMP) / parameters.EPOCH_DURATION();
    }

    /// @notice Get the current epoch.
    function getCurrentEpoch() public view returns (uint48 epoch) {
        return getEpochAtTs(Time.timestamp());
    }

    /// @notice Check if an operator address is authorized to work for a validator,
    /// given the validator's pubkey hash. This function performs a lookup in the
    /// validators registry to check if they explicitly authorized the operator.
    /// @param operator The operator address to check the authorization for.
    /// @param pubkeyHash The pubkey hash of the validator to check the authorization for.
    /// @return True if the operator is authorized, false otherwise.
    function isOperatorAuthorizedForValidator(address operator, bytes20 pubkeyHash) public view returns (bool) {
        if (operator == address(0) || pubkeyHash == bytes20(0)) {
            revert InvalidQuery();
        }

        return validators.getValidatorByPubkeyHash(pubkeyHash).authorizedOperator == operator;
    }

    /// @notice Returns the addresses of the middleware contracts of restaking protocols supported.
    function getSupportedRestakingProtocols() public view returns (address[] memory middlewares) {
        return restakingProtocols.values();
    }

    /// @notice Returns whether an operator is registered.
    function isOperator(
        address operator
    ) public view returns (bool) {
        return operators.contains(operator);
    }

    /// @notice Get the status of multiple proposers, given their pubkey hashes.
    /// @param pubkeyHashes The pubkey hashes of the proposers to get the status for.
    /// @return statuses The statuses of the proposers, including their operator and active stake.
    function getProposerStatuses(
        bytes20[] calldata pubkeyHashes
    ) public view returns (ProposerStatus[] memory statuses) {
        statuses = new ProposerStatus[](pubkeyHashes.length);
        for (uint256 i = 0; i < pubkeyHashes.length; ++i) {
            statuses[i] = getProposerStatus(pubkeyHashes[i]);
        }
    }

    /// @notice Get the status of a proposer, given their pubkey hash.
    /// @param pubkeyHash The pubkey hash of the proposer to get the status for.
    /// @return status The status of the proposer, including their operator and active stake.
    function getProposerStatus(
        bytes20 pubkeyHash
    ) public view returns (ProposerStatus memory status) {
        if (pubkeyHash == bytes20(0)) {
            revert InvalidQuery();
        }

        uint48 epochStartTs = getEpochStartTs(getEpochAtTs(Time.timestamp()));
        // NOTE: this will revert when the proposer does not exist.
        IValidator.ValidatorInfo memory validator = validators.getValidatorByPubkeyHash(pubkeyHash);

        EnumerableMap.Operator memory operatorData = operators.get(validator.authorizedOperator);

        status.pubkeyHash = pubkeyHash;
        status.operator = validator.authorizedOperator;
        status.operatorRPC = operatorData.rpc;

        (uint48 enabledTime, uint48 disabledTime) = operators.getTimes(validator.authorizedOperator);
        if (!_wasEnabledAt(enabledTime, disabledTime, epochStartTs)) {
            return status;
        }

        (status.collaterals, status.amounts) =
            IMiddleware(operatorData.middleware).getOperatorCollaterals(validator.authorizedOperator);

        // NOTE: check if the sum of the collaterals covers the minimum operator stake required.

        uint256 totalOperatorStake = 0;
        for (uint256 i = 0; i < status.amounts.length; ++i) {
            totalOperatorStake += status.amounts[i];
        }

        if (totalOperatorStake < parameters.MINIMUM_OPERATOR_STAKE()) {
            status.active = false;
        } else {
            status.active = true;
        }

        return status;
    }

    /// @notice Get the amount staked by an operator for a given collateral asset.
    function getOperatorStake(address operator, address collateral) public view returns (uint256) {
        EnumerableMap.Operator memory operatorData = operators.get(operator);

        return IMiddleware(operatorData.middleware).getOperatorStake(operator, collateral);
    }

    /// @notice Get the total amount staked of a given collateral asset.
    function getTotalStake(
        address collateral
    ) public view returns (uint256 amount) {
        // Loop over all of the operators, get their middleware, and retrieve their staked amount.
        for (uint256 i = 0; i < operators.length(); ++i) {
            (address operator, EnumerableMap.Operator memory operatorData) = operators.at(i);
            amount += IMiddleware(operatorData.middleware).getOperatorStake(operator, collateral);
        }

        return amount;
    }

    // ========= OPERATOR FUNCTIONS ====== //

    /// @notice Registers an operator. Only callable by a supported middleware contract.
    function registerOperator(address operatorAddr, string calldata rpc) external onlyMiddleware {
        if (operators.contains(operatorAddr)) {
            revert OperatorAlreadyRegistered();
        }

        // Create an already enabled operator
        EnumerableMap.Operator memory operator = EnumerableMap.Operator(rpc, msg.sender, Time.timestamp());

        operators.set(operatorAddr, operator);
    }

    /// @notice De-registers an operator. Only callable by a supported middleware contract.
    function deregisterOperator(
        address operator
    ) public onlyMiddleware {
        operators.remove(operator);
    }

    /// @notice Allow an operator to signal indefinite opt-out fromx Protocol.
    /// @dev Pausing activity does not prevent the operator from being slashable for
    /// the current network epoch until the end of the slashing window.
    function pauseOperator(
        address operator
    ) external onlyMiddleware {
        // SAFETY: This will revert if the operator key is not present.
        operators.disable(operator);
    }

    /// @notice Allow a disabled operator to signal opt-in to  Protocol.
    function unpauseOperator(
        address operator
    ) external onlyMiddleware {
        // SAFETY: This will revert if the operator key is not present.
        operators.enable(operator);
    }

    /// @notice Check if an operator is currently enabled to work in  Protocol.
    /// @param operator The operator address to check the enabled status for.
    /// @return True if the operator is enabled, false otherwise.
    function isOperatorEnabled(
        address operator
    ) public view returns (bool) {
        if (!operators.contains(operator)) {
            revert OperatorNotRegistered();
        }

        (uint48 enabledTime, uint48 disabledTime) = operators.getTimes(operator);
        return enabledTime != 0 && disabledTime == 0;
    }

    // ========= ADMIN FUNCTIONS ========= //

    /// @notice Add a restaking protocol 
    /// @param protocolMiddleware The address of the restaking protocol  middleware
    function addRestakingProtocol(
        address protocolMiddleware
    ) public onlyOwner {
        restakingProtocols.add(protocolMiddleware);
    }

    /// @notice Remove a restaking protocol from 
    /// @param protocolMiddleware The address of the restaking protocol  middleware
    function removeRestakingProtocol(
        address protocolMiddleware
    ) public onlyOwner {
        restakingProtocols.remove(protocolMiddleware);
    }

    // ========= HELPER FUNCTIONS =========

    /// @notice Check if a map entry was active at a given timestamp.
    /// @param enabledTime The enabled time of the map entry.
    /// @param disabledTime The disabled time of the map entry.
    /// @param timestamp The timestamp to check the map entry status at.
    /// @return True if the map entry was active at the given timestamp, false otherwise.
    function _wasEnabledAt(uint48 enabledTime, uint48 disabledTime, uint48 timestamp) private pure returns (bool) {
        return enabledTime != 0 && enabledTime <= timestamp && (disabledTime == 0 || disabledTime >= timestamp);
    }
}



// forge create src/Registry.sol:Registry --rpc-url http://5.78.46.151:32809 --private-key bcdf20249abf0ed6d944c0288fad489e33f66b3960d9e6229c1cd214ed3bbe31 --broadcast