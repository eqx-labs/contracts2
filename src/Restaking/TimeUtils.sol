// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";
import {IParameters} from "../interfaces/IParameters.sol";

library TimeUtils {
    function getPeriodStartTime(
        uint48 startTimestamp,
        uint48 periodIndex,
        IParameters parameters
    ) internal view returns (uint48) {
        return startTimestamp + periodIndex * parameters.VALIDATOR_EPOCH_TIME();
    }

    function getPeriodByTimestamp(
        uint48 timestamp,
        uint48 startTimestamp,
        IParameters parameters
    ) internal view returns (uint48) {
        return (timestamp - startTimestamp) / parameters.VALIDATOR_EPOCH_TIME();
    }

    function getActivePeriod(
        uint48 startTimestamp,
        IParameters parameters
    ) internal view returns (uint48) {
        return getPeriodByTimestamp(Time.timestamp(), startTimestamp, parameters);
    }

    function wasEnabledAt(
        uint48 enabledTime,
        uint48 disabledTime,
        uint48 timestamp
    ) internal pure returns (bool) {
        return
            enabledTime != 0 &&
            enabledTime <= timestamp &&
            (disabledTime == 0 || disabledTime >= timestamp);
    }
}