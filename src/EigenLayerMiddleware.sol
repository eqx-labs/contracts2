// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";
import {EnumerableMap} from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

import {MapWithTimeData} from "./lib/MapWithTimeData.sol";
import {IParameters} from "./interfaces/IParameters.sol";
import {IMiddleware} from "./interfaces/IMiddleware.sol";
import {IManager} from "./interfaces/IManager.sol";

import {IServiceManager} from "@eigenlayer-middleware/src/interfaces/IServiceManager.sol";
import {IStrategyManager} from "@eigenlayer/src/contracts/interfaces/IStrategyManager.sol";
import {IAVSDirectory} from "@eigenlayer/src/contracts/interfaces/IAVSDirectory.sol";
import {IDelegationManager} from "@eigenlayer/src/contracts/interfaces/IDelegationManager.sol";
import {ISignatureUtils} from "@eigenlayer/src/contracts/interfaces/ISignatureUtils.sol";
import {IStrategy} from "@eigenlayer/src/contracts/interfaces/IStrategy.sol";
import {AVSDirectoryStorage} from "@eigenlayer/src/contracts/core/AVSDirectoryStorage.sol";
import {DelegationManagerStorage} from "@eigenlayer/src/contracts/core/DelegationManagerStorage.sol";
import {StrategyManagerStorage} from "@eigenlayer/src/contracts/core/StrategyManagerStorage.sol";

abstract contract Middleware is IMiddleware, IServiceManager, OwnableUpgradeable, UUPSUpgradeable {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableMap for EnumerableMap.AddressToUintMap;
    using MapWithTimeData for EnumerableMap.AddressToUintMap;

    // Storage variables
    uint48 public GENESIS_TIME;
    IParameters public systemParams;
    IManager public systemManager;
    EnumerableMap.AddressToUintMap private activeStrategies;
    IAVSDirectory public DIRECTORY;
    DelegationManagerStorage public DELEGATION;
    StrategyManagerStorage public STRATEGY;
    bytes32 public PROTOCOL_ID;
    uint256[41] private __gap;

    // Custom errors
    error InvalidStrategy();
    error StrategyAlreadyExists();
    error StrategyNotFound();
    error OperatorExists();
    error OperatorNotFound();
    error InvalidOperator();
    error Unauthorized();
    error QueryError();
    error NotActive();

    // Initialization functions
    function initializeSystem(
        address owner,
        address params,
        address manager,
        address avsDirectory,
        address delegationManager,
        address strategyManager
    ) public initializer {
        __Ownable_init(owner);
        systemParams = IParameters(params);
        systemManager = IManager(manager);
        GENESIS_TIME = Time.timestamp();

        DIRECTORY = IAVSDirectory(avsDirectory);
        DELEGATION = DelegationManagerStorage(delegationManager);
        STRATEGY = StrategyManagerStorage(strategyManager);
        PROTOCOL_ID = keccak256("CUSTOM_PROTOCOL");
    }

    function upgradeSystemToV2(
        address owner,
        address params,
        address manager,
        address avsDirectory,
        address delegationManager,
        address strategyManager
    ) public reinitializer(2) {
        __Ownable_init(owner);
        systemParams = IParameters(params);
        systemManager = IManager(manager);
        GENESIS_TIME = Time.timestamp();

        DIRECTORY = IAVSDirectory(avsDirectory);
        DELEGATION = DelegationManagerStorage(delegationManager);
        STRATEGY = StrategyManagerStorage(strategyManager);
        PROTOCOL_ID = keccak256("CUSTOM_PROTOCOL");
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // Time-related functions
    function calculateEpochStart(uint48 epoch) public view returns (uint48) {
        return GENESIS_TIME + epoch * systemParams.EPOCH_DURATION();
    }

    function getEpochForTimestamp(uint48 timestamp) public view returns (uint48) {
        return (timestamp - GENESIS_TIME) / systemParams.EPOCH_DURATION();
    }

    function getCurrentEpochNumber() public view returns (uint48) {
        return getEpochForTimestamp(Time.timestamp());
    }

    // Strategy management functions
    function getRegisteredStrategies() public view returns (address[] memory) {
        return activeStrategies.keys();
    }

    function addNewStrategy(address strategy) public onlyOwner {
        if (activeStrategies.contains(strategy)) {
            revert StrategyAlreadyExists();
        }

        if (!STRATEGY.strategyIsWhitelistedForDeposit(IStrategy(strategy))) {
            revert InvalidStrategy();
        }

        activeStrategies.add(strategy);
        activeStrategies.enable(strategy);
    }

    function removeStrategy(address strategy) public onlyOwner {
        if (!activeStrategies.contains(strategy)) {
            revert StrategyNotFound();
        }
        activeStrategies.remove(strategy);
    }

    // Operator management functions
    function onboardOperator(
        string calldata rpcEndpoint,
        ISignatureUtils.SignatureWithSaltAndExpiry calldata signature
    ) public {
        if (systemManager.isOperator(msg.sender)) {
            revert OperatorExists();
        }

        if (!DELEGATION.isOperator(msg.sender)) {
            revert InvalidOperator();
        }

        registerOperatorToAVS(msg.sender, signature);
        systemManager.registerOperator(msg.sender, rpcEndpoint);
    }

    function offboardOperator() public {
        if (!systemManager.isOperator(msg.sender)) {
            revert OperatorNotFound();
        }

        deregisterOperatorFromAVS(msg.sender);
        systemManager.deregisterOperator(msg.sender);
    }

    function suspendOperator() public {
        systemManager.pauseOperator(msg.sender);
    }

    function resumeOperator() public {
        systemManager.unpauseOperator(msg.sender);
    }

    function disableStrategy() public {
        if (!activeStrategies.contains(msg.sender)) {
            revert StrategyNotFound();
        }
        activeStrategies.disable(msg.sender);
    }

    function enableStrategy() public {
        if (!activeStrategies.contains(msg.sender)) {
            revert StrategyNotFound();
        }
        activeStrategies.enable(msg.sender);
    }

    function checkStrategyStatus(address strategy) public view returns (bool) {
        (uint48 enableTime, uint48 disableTime) = activeStrategies.getTimes(strategy);
        return enableTime != 0 && disableTime == 0;
    }

    // Stake management functions
    function getOperatorStakeInfo(
        address operator
    ) public view returns (address[] memory, uint256[] memory) {
        address[] memory tokens = new address[](activeStrategies.length());
        uint256[] memory stakeAmounts = new uint256[](activeStrategies.length());

        uint48 epochStart = calculateEpochStart(getEpochForTimestamp(Time.timestamp()));

        for (uint256 i = 0; i < activeStrategies.length(); ++i) {
            (address strategy, uint48 enableTime, uint48 disableTime) = activeStrategies.atWithTimes(i);

            if (!_isActiveAtTimestamp(enableTime, disableTime, epochStart)) {
                continue;
            }

            IStrategy strategyContract = IStrategy(strategy);
            tokens[i] = address(strategyContract.underlyingToken());
            uint256 shares = DELEGATION.operatorShares(operator, strategyContract);
            stakeAmounts[i] = strategyContract.sharesToUnderlyingView(shares);
        }

        return (tokens, stakeAmounts);
    }

    function getOperatorTokenBalance(
        address operator, 
        address token
    ) public view returns (uint256) {
        return getOperatorTokenBalanceAt(operator, token, Time.timestamp());
    }

    function getOperatorTokenBalanceAt(
        address operator,
        address token,
        uint48 timestamp
    ) public view returns (uint256 totalBalance) {
        if (timestamp > Time.timestamp() || timestamp < GENESIS_TIME) {
            revert QueryError();
        }

        uint48 epochStart = calculateEpochStart(getEpochForTimestamp(timestamp));

        for (uint256 i = 0; i < activeStrategies.length(); i++) {
            (address strategy, uint48 enableTime, uint48 disableTime) = activeStrategies.atWithTimes(i);

            if (token != address(IStrategy(strategy).underlyingToken())) {
                continue;
            }

            if (!_isActiveAtTimestamp(enableTime, disableTime, epochStart)) {
                continue;
            }

            uint256 shares = DELEGATION.operatorShares(operator, IStrategy(strategy));
            totalBalance += IStrategy(strategy).sharesToUnderlyingView(shares);
        }

        return totalBalance;
    }

    // AVS Directory functions
    function updateMetadataURI(string calldata uri) public onlyOwner {
        DIRECTORY.updateAVSMetadataURI(uri);
    }

    // Internal helper functions
    function _isActiveAtTimestamp(
        uint48 enableTime,
        uint48 disableTime,
        uint48 timestamp
    ) private pure returns (bool) {
        return enableTime != 0 && enableTime <= timestamp && (disableTime == 0 || disableTime >= timestamp);
    }

    // EigenLayer Service Manager interface implementations
    function registerOperatorToAVS(
        address operator,
        ISignatureUtils.SignatureWithSaltAndExpiry memory signature
    ) public override {
        DIRECTORY.registerOperatorToAVS(operator, signature);
    }

    function deregisterOperatorFromAVS(address operator) public override {
        if (msg.sender != operator) {
            revert Unauthorized();
        }
        DIRECTORY.deregisterOperatorFromAVS(operator);
    }

    function getOperatorRestakedStrategies(
        address operator
    ) external view override returns (address[] memory) {
        address[] memory restakedStrategies = new address[](activeStrategies.length());
        uint48 epochStart = calculateEpochStart(getEpochForTimestamp(Time.timestamp()));

        for (uint256 i = 0; i < activeStrategies.length(); ++i) {
            (address strategy, uint48 enableTime, uint48 disableTime) = activeStrategies.atWithTimes(i);

            if (!_isActiveAtTimestamp(enableTime, disableTime, epochStart)) {
                continue;
            }

            if (DELEGATION.operatorShares(operator, IStrategy(strategy)) > 0) {
                restakedStrategies[restakedStrategies.length] = strategy;
            }
        }

        return restakedStrategies;
    }

    function getRestakeableStrategies() external view override returns (address[] memory) {
        return activeStrategies.keys();
    }

    function avsDirectory() external view override returns (address) {
        return address(DIRECTORY);
    }
}