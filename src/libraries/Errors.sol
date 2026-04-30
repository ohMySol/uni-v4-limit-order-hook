// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title ErrorsLib
/// @author @ohMySol
/// @notice A library that defines the errors for the `LimitOrder` hook contract
library ErrorsLib {
    /// @notice Thrown when `tickLower` is not a multiple of `poolKey.tickSpacing`
    error LimitOrder_InvalidTickLower();

    /// @notice Thrown when `liquidity` passed to `placeLimitOrder` is zero
    error LimitOrder_MissingLiquidity();

    /// @notice Thrown when `action` is already set
    error LimitOrder_ActionAlreadySet();

    /// @notice Thrown when `action` is invalid
    error LimitOrder_InvalidAction();

    /// @notice Thrown when `tickLower` is crossed
    error LimitOrder_TickCrossed();

    /// @notice Thrown when the user passed not enough funds to pay for the limit order
    error LimitOrder_InsufficientFunds();

    /// @notice Thrown when the transfer of funds fails
    error LimitOrder_TransferFailed();

    /// @notice Thrown when the user sent ETH instead of the required currency
    error LimitOrder_EthWasSent();
}