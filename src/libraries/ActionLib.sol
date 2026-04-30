// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title ActionLib
/// @author @ohMySol
/// @notice Library that defines the actions for the LimitOrder hook
library ActionLib {
    /// @notice The action to place a limit order
    uint256 internal constant PLACE_LMT_ORDER = 1;

    /// @notice The action to cancel a limit order
    uint256 internal constant CANCEL_LMT_ORDER = 2;

    /// @notice The slot to store the action
    bytes32 internal constant SLOT = 0;

    /// @notice Returns the action stored in the `SLOT`
    /// @return action The action stored in the `SLOT`
    function getAction() internal view returns (uint256 action) {
        assembly {
            action := tload(SLOT)
        }
    }

    /// @notice Sets the action in the `SLOT`
    /// @param action The action to set
    function setAction(uint256 action) internal {
        assembly {
            tstore(SLOT, action)
        }
    }
}