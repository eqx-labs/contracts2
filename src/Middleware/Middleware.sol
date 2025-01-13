// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";
import {EnumerableMap as OEnumerableMap} from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

import {TimeUtils} from "./TimeUtils.sol";
import {StrategyManager} from "./StrategyManager.sol";
import {OperatorManager} from "./OperatorManager.sol";
import {IParameters} from "../interfaces/IParameters.sol";
import {IConsensusRestaking} from "../interfaces/IRestaking.sol";
import {IValidatorRegistrySystem} from "../interfaces/IRegistry.sol";
import {IStrategy} from "@eigenlayer/src/contracts/interfaces/IStrategy.sol"; 
import {IServiceManager} from "@eigenlayer-middleware/src/interfaces/IServiceManager.sol";
import {IAVSDirectory} from "@eigenlayer/src/contracts/interfaces/IAVSDirectory.sol";
import {ISignatureUtils} from "@eigenlayer/src/contracts/interfaces/ISignatureUtils.sol";
import {DelegationManagerStorage} from "@eigenlayer/src/contracts/core/DelegationManagerStorage.sol";
import {StrategyManagerStorage} from "@eigenlayer/src/contracts/core/StrategyManagerStorage.sol";
import {MapWithTimeData} from "../library/MapWithTimeData.sol";

contract ConsensusEigenLayerMiddleware is
    IConsensusRestaking,
    IServiceManager,
    OwnableUpgradeable,
    UUPSUpgradeable
{
    using OEnumerableMap for OEnumerableMap.AddressToUintMap;
    using MapWithTimeData for OEnumerableMap.AddressToUintMap;

    uint48 public START_TIMESTAMP;
    IParameters public parameters;
    IValidatorRegistrySystem public registry;
    OEnumerableMap.AddressToUintMap private strategies;
    IAVSDirectory public AVS_DIRECTORY;
    DelegationManagerStorage public DELEGATION_MANAGER;
    StrategyManagerStorage public STRATEGY_MANAGER;
    bytes32 public PROTOCOL_IDENTIFIER;

    uint256[41] private __gap;

    // error MalformedRequest();

    function initialize(
        address _owner,
        address _parameters,
        address _registry,
        address _eigenlayerAVSDirectory,
        address _eigenlayerDelegationManager,
        address _eigenlayerStrategyManager
    ) public initializer {
        __Ownable_init(_owner);
        parameters = IParameters(_parameters);
        registry = IValidatorRegistrySystem(_registry);
        START_TIMESTAMP = Time.timestamp();

        AVS_DIRECTORY = IAVSDirectory(_eigenlayerAVSDirectory);
        DELEGATION_MANAGER = DelegationManagerStorage(_eigenlayerDelegationManager);
        STRATEGY_MANAGER = StrategyManagerStorage(_eigenlayerStrategyManager);
        PROTOCOL_IDENTIFIER = keccak256("CONSENSUS_PROTOCOL");
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // Time-related functions
    function getPeriodStartTime(uint48 periodIndex) public view returns (uint48) {
        return TimeUtils.getPeriodStartTime(START_TIMESTAMP, periodIndex, parameters);
    }

    function getPeriodByTimestamp(uint48 timestamp) public view returns (uint48) {
        return TimeUtils.getPeriodByTimestamp(timestamp, START_TIMESTAMP, parameters);
    }

    function getActivePeriod() public view returns (uint48) {
        return TimeUtils.getActivePeriod(START_TIMESTAMP, parameters);
    }

    // Strategy management functions
    function registerStrategy(address strategy) public onlyOwner {
        StrategyManager.registerStrategy(strategies, STRATEGY_MANAGER, strategy);
    }

    function deregisterStrategy(address strategy) public onlyOwner {
        StrategyManager.deregisterStrategy(strategies, strategy);
    }

    function pauseStrategy() public {
        StrategyManager.pauseStrategy(strategies, msg.sender);
    }

    function unpauseStrategy() public {
        StrategyManager.unpauseStrategy(strategies, msg.sender);
    }

    // Operator management functions
    function enrollValidatorNode(
        string calldata serviceEndpoint,
        ISignatureUtils.SignatureWithSaltAndExpiry calldata providerSignature
    ) public {
        OperatorManager.enrollValidatorNode(
            registry,
            DELEGATION_MANAGER,
            AVS_DIRECTORY,
            msg.sender,
            serviceEndpoint,
            providerSignature
        );
    }

    function removeValidatorNode() public {
        OperatorManager.removeValidatorNode(
            registry,
            AVS_DIRECTORY,
            msg.sender
        );
    }


    function suspendValidatorNode() public {
        registry.suspendValidatorNode(msg.sender);
    }

    function reactivateValidatorNode() public {
        registry.reactivateValidatorNode(msg.sender);
    }

    function getWhitelistedStrategies() public view returns (address[] memory) {
        return strategies.keys();
    }

    function getProviderCollateral(
        address provider,
        address tokenAddress
    ) public view returns (uint256) {
        uint48 timestamp = Time.timestamp();
        return getProviderCollateralAt(provider, tokenAddress, timestamp);
    }

    function getProviderCollateralTokens(
        address provider
    ) public view returns (address[] memory, uint256[] memory) {
        address[] memory collateralTokens = new address[](strategies.length());
        uint256[] memory amounts = new uint256[](strategies.length());

        uint48 periodStartTs = getPeriodStartTime(
            getPeriodByTimestamp(Time.timestamp())
        );

        for (uint256 i = 0; i < strategies.length(); ++i) {
            (
                address strategy,
                uint48 enabledTime,
                uint48 disabledTime
            ) = strategies.atWithTimes(i);

            if (!TimeUtils.wasEnabledAt(enabledTime, disabledTime, periodStartTs)) {
                continue;
            }

            IStrategy strategyImpl = IStrategy(strategy);
            address collateral = address(strategyImpl.underlyingToken());
            collateralTokens[i] = collateral;

            uint256 shares = DELEGATION_MANAGER.operatorShares(
                provider,
                strategyImpl
            );
            amounts[i] = strategyImpl.sharesToUnderlyingView(shares);
        }

        return (collateralTokens, amounts);
    }

    function getProviderCollateralAt(
        address provider,
        address tokenAddress,
        uint48 timestamp
    ) public view returns (uint256) {
        if (timestamp > Time.timestamp() || timestamp < START_TIMESTAMP) {
            revert MalformedRequest();
        }

        return StrategyManager.getProviderCollateralAt(
            strategies,
            DELEGATION_MANAGER,
            provider,
            tokenAddress,
            timestamp,
            START_TIMESTAMP,
            parameters
        );
    }

    function isStrategyEnabled(address strategy) public view returns (bool) {
        (uint48 enabledTime, uint48 disabledTime) = strategies.getTimes(strategy);
        return TimeUtils.wasEnabledAt(enabledTime, disabledTime, Time.timestamp());
    }

    // EigenLayer ServiceManager Interface Implementation
    function registerOperatorToAVS(
        address operator,
        ISignatureUtils.SignatureWithSaltAndExpiry memory operatorSignature
    ) public override {
        AVS_DIRECTORY.registerOperatorToAVS(operator, operatorSignature);
    }

    function deregisterOperatorFromAVS(address operator) public override {
        if (msg.sender != operator) {
            revert OperationForbidden();
        }
        AVS_DIRECTORY.deregisterOperatorFromAVS(operator);
    }

    function getOperatorRestakedStrategies(
        address operator
    ) external view override returns (address[] memory) {
        address[] memory restakedStrategies = new address[](strategies.length());
        uint256 count = 0;
        uint48 periodStartTs = getPeriodStartTime(
            getPeriodByTimestamp(Time.timestamp())
        );

        for (uint256 i = 0; i < strategies.length(); ++i) {
            (
                address strategy,
                uint48 enabledTime,
                uint48 disabledTime
            ) = strategies.atWithTimes(i);

            if (!TimeUtils.wasEnabledAt(enabledTime, disabledTime, periodStartTs)) {
                continue;
            }

            if (
                DELEGATION_MANAGER.operatorShares(
                    operator,
                    IStrategy(strategy)
                ) > 0
            ) {
                restakedStrategies[count] = strategy;
                count++;
            }
        }

        // Resize array to actual count
        assembly {
            mstore(restakedStrategies, count)
        }

        return restakedStrategies;
    }

    function getRestakeableStrategies()
        external
        view
        override
        returns (address[] memory)
    {
        return strategies.keys();
    }

    function avsDirectory() external view override returns (address) {
        return address(AVS_DIRECTORY);
    }

    function updateAVSMetadataURI(
        string calldata metadataURI
    ) public onlyOwner {
        AVS_DIRECTORY.updateAVSMetadataURI(metadataURI);
    }

    // Optional: Add any additional helper functions or internal methods here

}