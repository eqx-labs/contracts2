// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {OperatorMapWithTime} from "./lib/OperatorMapWithTime.sol"; 
import {EnumerableMap} from "./lib/EnumerableMap.sol";

import {ISystemParameters} from "./interfaces/IParameters.sol";
import {IMiddleware} from "./interfaces/IEigenlayerRestaking.sol";
import {IValidator} from "./interfaces/IValidator.sol";
import {IManager} from "./interfaces/IRegistry.sol";

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

    // =========== CONSTANTS ========= //
    /// @dev See EIP-4788 for more info
    address internal constant BEACON_ROOTS_CONTRACT =
        0x000F3df6D732807Ef1319fB7B8bB8522d0Beac02;

    /// @notice The EIP-4788 time window in slots
    uint256 internal constant EIP4788_WINDOW = 8191;
    // =========== STORAGE =========== //

    // --> Storage layout marker: 0 bits

    /// @notice Duration of an epoch in seconds.
    uint48 public EPOCH_DURATION;

    /// @notice Duration of the slashing window in seconds.
    uint48 public SLASHING_WINDOW;

    /// @notice Whether to allow unsafe registration of validators
    /// @dev Until the BLS12_381 precompile is live, we need to allow unsafe registration
    /// which means we don't check the BLS signature of the validator pubkey.
    bool public ALLOW_UNSAFE_REGISTRATION;
    // --> Storage layout marker: 48 + 48 + 8 = 104 bits

    /// @notice The maximum duration of a challenge before it is automatically considered valid.
    uint48 public MAX_CHALLENGE_DURATION;

    /// @notice The challenge bond required to open a challenge.
    uint256 public CHALLENGE_BOND;

    /// @notice The maximum number of blocks to look back for block hashes in the EVM.
    uint256 public BLOCKHASH_EVM_LOOKBACK;

    /// @notice The number of slots to wait before considering a block justified by LMD-GHOST.
    uint256 public JUSTIFICATION_DELAY;

    /// @notice The timestamp of the eth2 genesis block.
    uint256 public ETH2_GENESIS_TIMESTAMP;

    /// @notice The duration of a slot in seconds.
    uint256 public SLOT_TIME;

    /// @notice The minimum stake required for an operator to be considered active in wei.
    uint256 public MINIMUM_OPERATOR_STAKE;
    // --> Storage layout marker: 7 words

    uint256[43] private __gap;

    // ========= STORAGE =========
    /// @notice Start timestamp of the first epoch.
    uint48 public START_TIMESTAMP;

    /// @notice  Parameters contract.
    ISystemParameters public parameters;

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

    modifier onlyMiddleware() {
        if (!restakingProtocols.contains(msg.sender)) {
            revert UnauthorizedMiddleware();
        }
        _;
    }

    // ========= INITIALIZER & PROXY FUNCTIONALITY ========== //

    /// @notice The initializer for the Manager contract.
    /// @param _validators The address of the validators registry.
    function initialize(
        address _owner,
        address _parameters,
        address _validators,
        uint48 _epochDuration,
        uint48 _slashingWindow,
        uint48 _maxChallengeDuration,
        bool _allowUnsafeRegistration,
        uint256 _challengeBond,
        uint256 _blockhashEvmLookback,
        uint256 _justificationDelay,
        uint256 _eth2GenesisTimestamp,
        uint256 _slotTime,
        uint256 _minimumOperatorStake
    ) public initializer {
        __Ownable_init(_owner);

        parameters = ISystemParameters(_parameters);
        validators = IValidator(_validators);

        START_TIMESTAMP = Time.timestamp();
        EPOCH_DURATION = _epochDuration;
        SLASHING_WINDOW = _slashingWindow;
        ALLOW_UNSAFE_REGISTRATION = _allowUnsafeRegistration;
        MAX_CHALLENGE_DURATION = _maxChallengeDuration;
        CHALLENGE_BOND = _challengeBond;
        BLOCKHASH_EVM_LOOKBACK = _blockhashEvmLookback;
        JUSTIFICATION_DELAY = _justificationDelay;
        ETH2_GENESIS_TIMESTAMP = _eth2GenesisTimestamp;
        SLOT_TIME = _slotTime;
        MINIMUM_OPERATOR_STAKE = _minimumOperatorStake;
    }

    function initializeV2(
        address _owner,
        address _parameters,
        address _validators
    ) public reinitializer(2) {
        __Ownable_init(_owner);

        parameters = ISystemParameters(_parameters);
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
        return START_TIMESTAMP + epoch * parameters.getEpochDuration();
    }

    /// @notice Get the epoch at a given timestamp.
    function getEpochAtTs(uint48 timestamp) public view returns (uint48 epoch) {
        return (timestamp - START_TIMESTAMP) / parameters.getEpochDuration();
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
    function isOperatorAuthorizedForValidator(
        address operator,
        bytes20 pubkeyHash
    ) public view returns (bool) {
        if (operator == address(0) || pubkeyHash == bytes20(0)) {
            revert InvalidQuery();
        }

        return
            validators
                .getValidatorByPubkeyHash(pubkeyHash)
                .authorizedOperator == operator;
    }

    /// @notice Returns the addresses of the middleware contracts of restaking protocols supported.
    function getSupportedRestakingProtocols()
        public
        view
        returns (address[] memory middlewares)
    {
        return restakingProtocols.values();
    }

    /// @notice Returns whether an operator is registered.
    function isOperator(address operator) public view returns (bool) {
        return operators.contains(operator);
    }

    /// @notice Get the status of multiple proposers, given their pubkey hashes.
    /// @param pubkeyHashes The pubkey hashes of the proposers to get the status for.
    /// @return statuses The statuses of the proposers, including their operator and active stake.




    /// @notice Get the amount staked by an operator for a given collateral asset.
    function getOperatorStake(
        address operator,
        address collateral
    ) public view returns (uint256) {
        EnumerableMap.Operator memory operatorData = operators.get(operator);

        return
            IMiddleware(operatorData.middleware).getOperatorStake(
                operator,
                collateral
            );
    }

    /// @notice Get the total amount staked of a given collateral asset.
    function getTotalStake(
        address collateral
    ) public view returns (uint256 amount) {
        // Loop over all of the operators, get their middleware, and retrieve their staked amount.
        for (uint256 i = 0; i < operators.length(); ++i) {
            (
                address operator,
                EnumerableMap.Operator memory operatorData
            ) = operators.at(i);
            amount += IMiddleware(operatorData.middleware).getOperatorStake(
                operator,
                collateral
            );
        }

        return amount;
    }


 

    // ========= ADMIN FUNCTIONS ========= //

    /// @notice Add a restaking protocol
    /// @param protocolMiddleware The address of the restaking protocol  middleware
    function addRestakingProtocol(address protocolMiddleware) public onlyOwner {
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
    function _wasEnabledAt(
        uint48 enabledTime,
        uint48 disabledTime,
        uint48 timestamp
    ) private pure returns (bool) {
        return
            enabledTime != 0 &&
            enabledTime <= timestamp &&
            (disabledTime == 0 || disabledTime >= timestamp);
    }

    // ========= ADMIN METHODS ========= //

    /// @notice Enable or disable the use of the BLS precompile
    /// @param allowUnsafeRegistration Whether to allow unsafe registration of validators
    function setAllowUnsafeRegistration(
        bool allowUnsafeRegistration
    ) public onlyOwner {
        ALLOW_UNSAFE_REGISTRATION = allowUnsafeRegistration;
    }

    /// @notice Set the max challenge duration.
    /// @param maxChallengeDuration The maximum duration of a challenge before it is automatically considered valid.
    function setMaxChallengeDuration(
        uint48 maxChallengeDuration
    ) public onlyOwner {
        MAX_CHALLENGE_DURATION = maxChallengeDuration;
    }

    /// @notice Set the required challenge bond.
    /// @param challengeBond The challenge bond required to open a challenge.
    function setChallengeBond(uint256 challengeBond) public onlyOwner {
        CHALLENGE_BOND = challengeBond;
    }

    /// @notice Set the minimum operator stake.
    /// @param minimumOperatorStake The minimum stake required for an operator to be considered active in wei.
    function setMinimumOperatorStake(
        uint256 minimumOperatorStake
    ) public onlyOwner {
        MINIMUM_OPERATOR_STAKE = minimumOperatorStake;
    }

    /// @notice Set the justification delay.
    /// @param justificationDelay The number of slots to wait before considering a block final.
    function setJustificationDelay(
        uint256 justificationDelay
    ) public onlyOwner {
        JUSTIFICATION_DELAY = justificationDelay;
    }


    function registerNewOperator(address operatorAddress, string calldata rpcUrl) external onlyMiddleware {
        if (operators.contains(operatorAddress)) {
            revert OperatorAlreadyRegistered();
        }

        // Create an already enabled operator
        EnumerableMap.Operator memory operator = EnumerableMap.Operator(rpcUrl, msg.sender, Time.timestamp());

        operators.set(operatorAddress, operator);
    }

     function removeOperator(
        address operator
    ) public onlyMiddleware {
        operators.remove(operator);
    }
    function suspendOperator(
        address operator
    ) external onlyMiddleware {
        // SAFETY: This will revert if the operator key is not present.
        operators.disable(operator);
    }
    function resumeOperator(
        address operator
    ) external onlyMiddleware {
        // SAFETY: This will revert if the operator key is not present.
        operators.enable(operator);
    }

     function isOperatorRegistered(
        address operator
    ) public view returns (bool) {
        if (!operators.contains(operator)) {
            revert OperatorNotRegistered();
        }

        (uint48 enabledTime, uint48 disabledTime) = operators.getTimes(operator);
        return enabledTime != 0 && disabledTime == 0;
    }

  function getValidatorProposerStatuses(
        bytes20[] calldata pubkeyHashes
    ) public view returns (ValidatorProposerStatus[] memory statuses) {
        statuses = new ValidatorProposerStatus[](pubkeyHashes.length);
        for (uint256 i = 0; i < pubkeyHashes.length; ++i) {
            statuses[i] = getProposerStatus(pubkeyHashes[i]);
        }
    }

    function getValidatorProposerStatus(
        bytes20 pubkeyHash
    ) public view returns (ValidatorProposerStatus memory status) {
        if (pubkeyHash == bytes20(0)) {
            revert InvalidQuery();
        }

        uint48 epochStartTs = getEpochStartTs(getEpochAtTs(Time.timestamp()));
        // NOTE: this will revert when the proposer does not exist.
        IValidator.ValidatorInfo memory validator = validators.getValidatorByPubkeyHash(pubkeyHash);

        EnumerableMap.Operator memory operatorData = operators.get(validator.authorizedOperator);

        status.validatorPubkeyHash = pubkeyHash;
        status.operatorAddress = validator.authorizedOperator;
        status.operatorRpcUrl = operatorData.rpc;

        (uint48 enabledTime, uint48 disabledTime) = operators.getTimes(validator.authorizedOperator);
        if (!_wasEnabledAt(enabledTime, disabledTime, epochStartTs)) {
            return status;
        }

        (status.collateralTokens, status.collateralAmounts) =
            IMiddleware(operatorData.middleware).getOperatorCollaterals(validator.authorizedOperator);

        // NOTE: check if the sum of the collaterals covers the minimum operator stake required.

        uint256 totalOperatorStake = 0;
        for (uint256 i = 0; i < status.collateralAmounts.length; ++i) {
            totalOperatorStake += status.collateralAmounts[i];
        }

        if (totalOperatorStake < parameters.getMinimumOperatorStake()) {
            status.isActive = false;
        } else {
            status.isActive = true;
        }

        return status;
    }
   function getRestakingMiddlewareProtocols() public view returns (address[] memory middlewares) {
        return restakingProtocols.values();
    }

}



