// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

// Credits: Symbiotic contributors.
// Ref: https://github.com/symbioticfi/cosmos-sdk/blob/c25b6d5f320eb8ea4189584fa04d28c47362c2a7/middleware/src/libraries/MapWithTimeData.sol

import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";
import {EnumerableMap} from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";

/// @title MapWithTimeData Library
/// @notice A library for managing a mapping of addresses with associated timestamps for enable and disable states.
/// @dev Extends the EnumerableMap library to include time-based state management.
library MapWithTimeData {
    using EnumerableMap for EnumerableMap.AddressToUintMap;

    /// @notice Error indicating an address is already added to the map.
    error AlreadyAdded();
    /// @notice Error indicating an address is not currently enabled.
    error NotEnabled();
    /// @notice Error indicating an address is already enabled.
    error AlreadyEnabled();

    /// @dev Mask for extracting the enabled time (first 48 bits of the value).
    uint256 private constant ENABLED_TIME_MASK = 0xFFFFFFFFFFFFFFFFFFFFFFFF;
    /// @dev Mask for extracting the disabled time (next 48 bits of the value).
    uint256 private constant DISABLED_TIME_MASK = 0xFFFFFFFFFFFFFFFFFFFFFFFF << 48;

    /// @notice Adds an address to the map with an initial value of 0 (not enabled or disabled).
    /// @param self The AddressToUintMap storage reference.
    /// @param addr The address to be added.
    /// @dev Reverts with `AlreadyAdded` if the address is already in the map.
    function add(EnumerableMap.AddressToUintMap storage self, address addr) internal {
        if (!self.set(addr, uint256(0))) {
            revert AlreadyAdded();
        }
    }

    /// @notice Disables an address by setting its disabled timestamp.
    /// @param self The AddressToUintMap storage reference.
    /// @param addr The address to disable.
    /// @dev Reverts with `NotEnabled` if the address is not enabled or already disabled.
    function disable(EnumerableMap.AddressToUintMap storage self, address addr) internal {
        uint256 value = self.get(addr);

        // Ensure the address is enabled but not already disabled
        if (uint48(value) == 0 || uint48(value >> 48) != 0) {
            revert NotEnabled();
        }

        // Set the disabled timestamp
        value |= uint256(Time.timestamp()) << 48;
        self.set(addr, value);
    }

    /// @notice Enables an address by setting its enabled timestamp and clearing the disabled timestamp.
    /// @param self The AddressToUintMap storage reference.
    /// @param addr The address to enable.
    /// @dev Reverts with `AlreadyEnabled` if the address is already enabled and not disabled.
    function enable(EnumerableMap.AddressToUintMap storage self, address addr) internal {
        uint256 value = self.get(addr);

        // Ensure the address is not already enabled without being disabled
        if (uint48(value) != 0 && uint48(value >> 48) == 0) {
            revert AlreadyEnabled();
        }

        // Set the enabled timestamp and clear the disabled timestamp
        value = uint256(Time.timestamp());
        self.set(addr, value);
    }

    /// @notice Retrieves the address, enabled timestamp, and disabled timestamp at a specific index.
    /// @param self The AddressToUintMap storage reference.
    /// @param idx The index of the entry to retrieve.
    /// @return key The address at the specified index.
    /// @return enabledTime The enabled timestamp for the address.
    /// @return disabledTime The disabled timestamp for the address.
    function atWithTimes(
        EnumerableMap.AddressToUintMap storage self,
        uint256 idx
    ) internal view returns (address key, uint48 enabledTime, uint48 disabledTime) {
        uint256 value;
        (key, value) = self.at(idx);
        enabledTime = uint48(value);
        disabledTime = uint48(value >> 48);
    }

    /// @notice Retrieves the enabled and disabled timestamps for a given address.
    /// @param self The AddressToUintMap storage reference.
    /// @param addr The address to retrieve timestamps for.
    /// @return enabledTime The enabled timestamp for the address.
    /// @return disabledTime The disabled timestamp for the address.
    function getTimes(
        EnumerableMap.AddressToUintMap storage self,
        address addr
    ) internal view returns (uint48 enabledTime, uint48 disabledTime) {
        uint256 value = self.get(addr);
        enabledTime = uint48(value);
        disabledTime = uint48(value >> 48);
    }
}
