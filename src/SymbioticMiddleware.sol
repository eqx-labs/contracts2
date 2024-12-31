// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import {Time} from "node_modules/@openzeppelin/contracts/utils/types/Time.sol";
import {EnumerableMap} from "node_modules/@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import {EnumerableSet} from "node_modules/@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IERC20} from "node_modules/@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {OwnableUpgradeable} from "node_modules/@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "node_modules/@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

import {IBaseDelegator} from "@symbiotic/interfaces/delegator/IBaseDelegator.sol";
import {Subnetwork} from "@symbiotic/contracts/libraries/Subnetwork.sol";
import {IVault} from "@symbiotic/interfaces/vault/IVault.sol";
import {IRegistry} from "@symbiotic/interfaces/common/IRegistry.sol";
import {IOptInService} from "@symbiotic/interfaces/service/IOptInService.sol";
import {ISlasher} from "@symbiotic/interfaces/slasher/ISlasher.sol";
import {IVetoSlasher} from "@symbiotic/interfaces/slasher/IVetoSlasher.sol";
import {IEntity} from "@symbiotic/interfaces/common/IEntity.sol";

import {MapWithTimeData} from "./lib/MapWithTimeData.sol";
import {IParameters} from "./interfaces/IParameters.sol";
import {IMiddleware} from "./interfaces/IMiddleware.sol";
import {IManager} from "./interfaces/IManager.sol";

contract SymbioticMiddleware is IMiddleware, OwnableUpgradeable, UUPSUpgradeable {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableMap for EnumerableMap.AddressToUintMap;
    using MapWithTimeData for EnumerableMap.AddressToUintMap;
    using Subnetwork for address;

    // Constants
    uint256 public DIRECT_SLASH_TYPE = 0;
    uint256 public VETOED_SLASH_TYPE = 1;

    // State Variables
    uint48 public GENESIS_TIME;
    IParameters public protocolParams;
    IManager public protocolManager;
    EnumerableMap.AddressToUintMap private authorizedVaults;
    address public NETWORK_ADDRESS;
    address public OPERATOR_REGISTRY_ADDRESS;
    address public VAULT_FACTORY_ADDRESS;
    address public OPERATOR_OPTIN_ADDRESS;
    bytes32 public PROTOCOL_ID;

    // Storage gap for upgrades
    uint256[38] private __gap;

    // Errors
    error InvalidVaultAddress();
    error ExcessiveSlashAmount();
    error UnsupportedSlasherType();
    error InvalidOperator();
    error AlreadyRegistered();
    error NotRegistered();
    error OperatorNotOptedIn();
    error InvalidTimeQuery();

    function setupContract(
        address owner,
        address params,
        address manager,
        address networkAddr,
        address operatorRegistry,
        address operatorOptIn,
        address vaultFactory
    ) public initializer {
        __Ownable_init(owner);
        protocolParams = IParameters(params);
        protocolManager = IManager(manager);
        GENESIS_TIME = Time.timestamp();

        NETWORK_ADDRESS = networkAddr;
        OPERATOR_REGISTRY_ADDRESS = operatorRegistry;
        OPERATOR_OPTIN_ADDRESS = operatorOptIn;
        VAULT_FACTORY_ADDRESS = vaultFactory;
        PROTOCOL_ID = keccak256("SYMBIOTIC");
    }

    function upgradeContractV2(
        address owner,
        address params,
        address manager,
        address networkAddr,
        address operatorRegistry,
        address operatorOptIn,
        address vaultFactory
    ) public reinitializer(2) {
        __Ownable_init(owner);
        protocolParams = IParameters(params);
        protocolManager = IManager(manager);
        GENESIS_TIME = Time.timestamp();

        NETWORK_ADDRESS = networkAddr;
        OPERATOR_REGISTRY_ADDRESS = operatorRegistry;
        OPERATOR_OPTIN_ADDRESS = operatorOptIn;
        VAULT_FACTORY_ADDRESS = vaultFactory;
        PROTOCOL_ID = keccak256("SYMBIOTIC");
    }

    function _authorizeUpgrade(address newImpl) internal override onlyOwner {}

    // Time-related functions
    function calculateEpochStart(uint48 epoch) public view returns (uint48) {
        return GENESIS_TIME + epoch * protocolParams.EPOCH_DURATION();
    }

    function getEpochForTimestamp(uint48 timestamp) public view returns (uint48) {
        return (timestamp - GENESIS_TIME) / protocolParams.EPOCH_DURATION();
    }

    function getCurrentEpochNumber() public view returns (uint48) {
        return getEpochForTimestamp(Time.timestamp());
    }

    function listAuthorizedVaults() public view returns (address[] memory) {
        return authorizedVaults.keys();
    }

    // Admin functions
    function addVault(address vault) public onlyOwner {
        if (authorizedVaults.contains(vault)) {
            revert AlreadyRegistered();
        }

        if (!IRegistry(VAULT_FACTORY_ADDRESS).isEntity(vault)) {
            revert InvalidVaultAddress();
        }

        authorizedVaults.add(vault);
        authorizedVaults.enable(vault);
    }

    function removeVault(address vault) public onlyOwner {
        if (!authorizedVaults.contains(vault)) {
            revert NotRegistered();
        }

        authorizedVaults.remove(vault);
    }

    // Operator management
    function onboardOperator(string calldata rpcEndpoint) public {
        if (protocolManager.isOperator(msg.sender)) {
            revert AlreadyRegistered();
        }

        if (!IRegistry(OPERATOR_REGISTRY_ADDRESS).isEntity(msg.sender)) {
            revert InvalidOperator();
        }

        if (!IOptInService(OPERATOR_OPTIN_ADDRESS).isOptedIn(msg.sender, NETWORK_ADDRESS)) {
            revert OperatorNotOptedIn();
        }

        protocolManager.registerOperator(msg.sender, rpcEndpoint);
    }

    function offboardOperator() public {
        if (!protocolManager.isOperator(msg.sender)) {
            revert NotRegistered();
        }

        protocolManager.deregisterOperator(msg.sender);
    }

    function suspendOperatorActivity() public {
        protocolManager.pauseOperator(msg.sender);
    }

    function resumeOperatorActivity() public {
        protocolManager.unpauseOperator(msg.sender);
    }

    function suspendVaultActivity() public {
        if (!authorizedVaults.contains(msg.sender)) {
            revert NotRegistered();
        }

        authorizedVaults.disable(msg.sender);
    }

    function resumeVaultActivity() public {
        if (!authorizedVaults.contains(msg.sender)) {
            revert NotRegistered();
        }

        authorizedVaults.enable(msg.sender);
    }

    function checkVaultStatus(address vault) public view returns (bool) {
        (uint48 enableTime, uint48 disableTime) = authorizedVaults.getTimes(vault);
        return enableTime != 0 && disableTime == 0;
    }

    function fetchOperatorCollateral(address operator) public view returns (address[] memory, uint256[] memory) {
        address[] memory tokens = new address[](authorizedVaults.length());
        uint256[] memory amounts = new uint256[](authorizedVaults.length());

        uint48 epochStart = calculateEpochStart(getEpochForTimestamp(Time.timestamp()));

        for (uint256 i = 0; i < authorizedVaults.length(); ++i) {
            (address vault, uint48 enableTime, uint48 disableTime) = authorizedVaults.atWithTimes(i);

            if (!isActiveAtTimestamp(enableTime, disableTime, epochStart)) {
                continue;
            }

            address token = IVault(vault).collateral();
            tokens[i] = token;

            amounts[i] = IBaseDelegator(IVault(vault).delegator()).stakeAt(
                NETWORK_ADDRESS.subnetwork(0),
                operator,
                epochStart,
                new bytes(0)
            );
        }

        return (tokens, amounts);
    }

    function getOperatorStakeNow(address operator, address token) public view returns (uint256) {
        uint48 currentTime = Time.timestamp();
        return getOperatorStakeAtTime(operator, token, currentTime);
    }

    function getOperatorStakeAtTime(
        address operator,
        address token,
        uint48 timestamp
    ) public view returns (uint256 totalStake) {
        if (timestamp > Time.timestamp() || timestamp < GENESIS_TIME) {
            revert InvalidTimeQuery();
        }

        uint48 epochStart = calculateEpochStart(getEpochForTimestamp(timestamp));

        for (uint256 i = 0; i < authorizedVaults.length(); ++i) {
            (address vault, uint48 enableTime, uint48 disableTime) = authorizedVaults.atWithTimes(i);

            if (token != IVault(vault).collateral()) {
                continue;
            }

            if (!isActiveAtTimestamp(enableTime, disableTime, epochStart)) {
                continue;
            }

            totalStake += IBaseDelegator(IVault(vault).delegator()).stakeAt(
                NETWORK_ADDRESS.subnetwork(0),
                operator,
                epochStart,
                new bytes(0)
            );
        }

        return totalStake;
    }

    function penalizeOperator(
        uint48 timestamp,
        address operator,
        address token,
        uint256 amount
    ) public onlyOwner {
        uint48 epochStart = calculateEpochStart(getEpochForTimestamp(timestamp));

        for (uint256 i = 0; i < authorizedVaults.length(); ++i) {
            (address vault, uint48 enableTime, uint48 disableTime) = authorizedVaults.atWithTimes(i);

            if (!isActiveAtTimestamp(enableTime, disableTime, epochStart)) {
                continue;
            }

            if (token != IVault(vault).collateral()) {
                continue;
            }

            uint256 operatorStake = getOperatorStakeAtTime(operator, token, epochStart);

            if (amount > operatorStake) {
                revert ExcessiveSlashAmount();
            }

            uint256 vaultStake = IBaseDelegator(IVault(vault).delegator()).stakeAt(
                NETWORK_ADDRESS.subnetwork(0),
                operator,
                epochStart,
                new bytes(0)
            );

            executeVaultPenalty(epochStart, vault, operator, (amount * vaultStake) / operatorStake);
        }
    }

    function isActiveAtTimestamp(
        uint48 enableTime,
        uint48 disableTime,
        uint48 timestamp
    ) private pure returns (bool) {
        return enableTime != 0 && enableTime <= timestamp && (disableTime == 0 || disableTime >= timestamp);
    }

    function executeVaultPenalty(
        uint48 timestamp,
        address vault,
        address operator,
        uint256 amount
    ) private {
        address slasher = IVault(vault).slasher();
        uint256 slasherType = IEntity(slasher).TYPE();

        if (slasherType == DIRECT_SLASH_TYPE) {
            ISlasher(slasher).slash(
                NETWORK_ADDRESS.subnetwork(0),
                operator,
                amount,
                timestamp,
                new bytes(0)
            );
        } else if (slasherType == VETOED_SLASH_TYPE) {
            IVetoSlasher(slasher).requestSlash(
                NETWORK_ADDRESS.subnetwork(0),
                operator,
                amount,
                timestamp,
                new bytes(0)
            );
        } else {
            revert UnsupportedSlasherType();
        }
    }
}