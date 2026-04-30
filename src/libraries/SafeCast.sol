// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title SafeCast
/// @author @ohMySol
/// @notice Contains methods for safely casting between types
library SafeCast {
    /// @notice Casts an `int128` to a `uint256`
    /// @param x The `int128` to cast
    /// @return The `uint256` value
    function toUint256(int128 x) internal pure returns (uint256) {
        require(x >= 0, "x < 0");
        return uint256(uint128(x));
    }

    /// @notice Casts a `uint128` to a `int256`
    /// @param x The `uint128` to cast
    /// @return The `int256` value
    function toInt256(uint128 x) internal pure returns (int256) {
        return int256(uint256(x));
    }

    /// @notice Casts an `int128` to a `int256`
    /// @param x The `int128` to cast
    /// @return The `int256` value
    function toInt256(int128 x) internal pure returns (int256) {
        require(x >= 0, "x < 0");
        return int256(x);
    }
}