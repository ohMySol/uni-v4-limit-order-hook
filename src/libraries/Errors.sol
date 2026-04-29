// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title ErrorsLib
/// @author @ohMySol
/// @notice A library that defines the errors for the `LimitOrder` hook contract
library ErrorsLib {
    /// @notice Thrown when `tickLower` is not a multiple of `poolKey.tickSpacing`
    error LimitOrder_InvalidTickLower();

    /// @notice Thrown when `liquidity` passed to `placeLimitOrder` is zero
    error LimitOrder_MissingLiquidity();
}