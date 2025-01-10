// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import {EnumerableMap} from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";
import {IStrategy} from "@eigenlayer/src/contracts/interfaces/IStrategy.sol";
import {StrategyManagerStorage} from "@eigenlayer/src/contracts/core/StrategyManagerStorage.sol";
import {DelegationManagerStorage} from "@eigenlayer/src/contracts/core/DelegationManagerStorage.sol";
import {MapWithTimeData} from "../lib/MapWithTimeData.sol";
import {TimeUtils} from "./TimeUtils.sol";
import {IParameters} from "../interfaces/IParameters.sol";

library StrategyManager {
    using EnumerableMap for EnumerableMap.AddressToUintMap;
    using MapWithTimeData for EnumerableMap.AddressToUintMap;

    error ParticipantExists();
    error ParticipantNotFound();
    error StrategyNotAllowed();

    function registerStrategy(
        EnumerableMap.AddressToUintMap storage strategies,
        StrategyManagerStorage strategyManager,
        address strategy
    ) internal {
        if (strategies.contains(strategy)) {
            revert ParticipantExists();
        }

        if (
            !strategyManager.strategyIsWhitelistedForDeposit(
                IStrategy(strategy)
            )
        ) {
            revert StrategyNotAllowed();
        }

        strategies.add(strategy);
        strategies.enable(strategy);
    }

    function deregisterStrategy(
        EnumerableMap.AddressToUintMap storage strategies,
        address strategy
    ) internal {
        if (!strategies.contains(strategy)) {
            revert ParticipantNotFound();
        }

        strategies.remove(strategy);
    }

    function pauseStrategy(
        EnumerableMap.AddressToUintMap storage strategies,
        address strategy
    ) internal {
        if (!strategies.contains(strategy)) {
            revert ParticipantNotFound();
        }

        strategies.disable(strategy);
    }

    function unpauseStrategy(
        EnumerableMap.AddressToUintMap storage strategies,
        address strategy
    ) internal {
        if (!strategies.contains(strategy)) {
            revert ParticipantNotFound();
        }

        strategies.enable(strategy);
    }

    function getProviderCollateralAt(
        EnumerableMap.AddressToUintMap storage strategies,
        DelegationManagerStorage delegationManager,
        address provider,
        address tokenAddress,
        uint48 timestamp,
        uint48 startTimestamp,
        IParameters parameters
    ) internal view returns (uint256 amount) {
        uint48 periodStartTs = TimeUtils.getPeriodStartTime(
            startTimestamp,
            TimeUtils.getPeriodByTimestamp(timestamp, startTimestamp, parameters),
            parameters
        );

        for (uint256 i = 0; i < strategies.length(); i++) {
            (
                address strategy,
                uint48 enabledTime,
                uint48 disabledTime
            ) = strategies.atWithTimes(i);

            if (
                tokenAddress != address(IStrategy(strategy).underlyingToken())
            ) {
                continue;
            }

            if (!TimeUtils.wasEnabledAt(enabledTime, disabledTime, periodStartTs)) {
                continue;
            }

            uint256 shares = delegationManager.operatorShares(
                provider,
                IStrategy(strategy)
            );
            amount += IStrategy(strategy).sharesToUnderlyingView(shares);
        }

        return amount;
    }
}