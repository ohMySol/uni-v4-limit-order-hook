// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title EventsLib
/// @author @ohMySol
/// @notice A library that defines the events for the `LimitOrder` hook contract. Events are named in the following format:
/// `LimitOrder_{EventName}`.
library EventsLib {
    /// @notice Emitted when a limit order is placed
    event LimitOrder_Placed(
        address indexed sender,
        bytes32 indexed poolId,
        uint256 indexed slot,
        int24 tickLower,
        bool zeroForOne,
        uint128 liquidity
    );

    /// @notice Emitted when a limit order is cancelled
    event LimitOrder_Cancelled(
        address indexed sender,
        bytes32 indexed poolId,
        uint256 indexed slot,
        int24 tickLower,
        bool zeroForOne
    );

    /// @notice Emitted when swapped tokens from limit order are taken
    event LimitOrder_Taken(
        address indexed sender,
        bytes32 indexed poolId,
        uint256 indexed slot,
        int24 tickLower,
        bool zeroForOne,
        uint256 amount0,
        uint256 amount1
    );

    /// @notice Emitted when a limit order bucket is filled (liquidity removed and proceeds recorded)
    event LimitOrder_Filled(
        bytes32 indexed poolId,
        uint256 indexed slot,
        int24 tickLower,
        bool zeroForOne,
        uint256 amount0,
        uint256 amount1
    );
}