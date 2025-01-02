// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/// @title EnumerableMap Library
/// @notice A library that allows the management of a mapping with enumerable keys.
/// @dev Uses OpenZeppelin's EnumerableSet to store keys and a custom struct for values.
library EnumerableMap {
    using EnumerableSet for EnumerableSet.Bytes32Set;

    /// @notice Error to indicate that a key was not found in the map.
    error KeyNotFound();

    /// @notice Struct representing an operator's details.
    /// @dev Includes RPC endpoint, middleware contract address, and registration timestamp.
    struct Operator {
        string rpc;        // RPC endpoint of the operator
        address middleware; // Middleware contract address
        uint256 timestamp; // Registration timestamp
    }

    /// @notice Struct representing the mapping and keys storage.
    /// @dev Keys are stored as an enumerable set for iteration support.
    struct OperatorMap {
        EnumerableSet.Bytes32Set _keys;       // Storage for keys (as bytes32)
        mapping(bytes32 key => Operator) _values; // Mapping from key to Operator struct
    }

    /// @notice Adds or updates a key-value pair in the map.
    /// @param self The OperatorMap storage reference.
    /// @param key The address to be used as the key.
    /// @param value The Operator struct to be associated with the key.
    /// @return True if the key was newly added, false if it was updated.
    function set(OperatorMap storage self, address key, Operator memory value) internal returns (bool) {
        bytes32 keyBytes = bytes32(uint256(uint160(key)));
        self._values[keyBytes] = value;
        return self._keys.add(keyBytes);
    }

    /// @notice Removes a key-value pair from the map.
    /// @param self The OperatorMap storage reference.
    /// @param key The address to be removed as the key.
    /// @return True if the key was successfully removed, false otherwise.
    function remove(OperatorMap storage self, address key) internal returns (bool) {
        bytes32 keyBytes = bytes32(uint256(uint160(key)));
        delete self._values[keyBytes];
        return self._keys.remove(keyBytes);
    }

    /// @notice Checks if a key exists in the map.
    /// @param self The OperatorMap storage reference.
    /// @param key The address to check for existence.
    /// @return True if the key exists, false otherwise.
    function contains(OperatorMap storage self, address key) internal view returns (bool) {
        return self._keys.contains(bytes32(uint256(uint160(key))));
    }

    /// @notice Returns the number of key-value pairs in the map.
    /// @param self The OperatorMap storage reference.
    /// @return The number of key-value pairs.
    function length(OperatorMap storage self) internal view returns (uint256) {
        return self._keys.length();
    }

    /// @notice Retrieves the key and value at a specific index in the map.
    /// @param self The OperatorMap storage reference.
    /// @param index The index of the key-value pair to retrieve.
    /// @return The key (as an address) and the associated Operator struct.
    function at(OperatorMap storage self, uint256 index) internal view returns (address, Operator memory) {
        bytes32 key = self._keys.at(index);
        return (address(uint160(uint256(key))), self._values[key]);
    }

    /// @notice Retrieves the value associated with a key.
    /// @param self The OperatorMap storage reference.
    /// @param key The address to retrieve the associated value for.
    /// @return The Operator struct associated with the key.
    /// @dev Reverts with `KeyNotFound` if the key does not exist.
    function get(OperatorMap storage self, address key) internal view returns (Operator memory) {
        if (!contains(self, key)) {
            revert KeyNotFound();
        }
        return self._values[bytes32(uint256(uint160(key)))];
    }

    /// @notice Retrieves all keys in the map as an array of addresses.
    /// @param self The OperatorMap storage reference.
    /// @return An array of all keys (as addresses).
    function keys(OperatorMap storage self) internal view returns (address[] memory) {
        address[] memory result = new address[](self._keys.length());
        for (uint256 i = 0; i < self._keys.length(); i++) {
            result[i] = address(uint160(uint256(self._keys.at(i))));
        }
        return result;
    }
}
