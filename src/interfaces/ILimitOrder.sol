// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {PoolId} from "v4-core/types/PoolId.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";

/// @notice A bucket is a structure that holds limit orders of different users for a certain range of ticks
/// @dev The bucket is identified by the `poolId`, `tick` (lower tick) and `zeroForOne` flag.
/// A bucket is “filled” when the position has been converted into the output token for that order’s direction.
/// @param filled Whether the liquidity in the bucket has been filled
/// @param amount0 The amount of token0 in the bucket 
/// @param amount1 The amount of token1 in the bucket
/// @param liquidity The total liquidity in the bucket
/// @param userLiquidity The liquidity of the user in the bucket (user address => liquidity)
struct Bucket {
    bool filled;
    uint256 amount0;
    uint256 amount1;
    uint128 liquidity;
    mapping(address => uint128) userLiquidity;
}

/// @title ILimitOrder
/// @author @ohMySol
/// @notice Interface that defines the functions for the `LimitOrder` hook contract
interface ILimitOrder {
    /// @notice The latest tick of the pool
    /// @param poolId The ID of the pool
    /// @return The latest tick of the pool
    function ticks(PoolId poolId) external view returns (int24);

    /// @notice The slot of the bucket
    /// @param bucketId The ID of the bucket
    /// @return The slot of the bucket
    function slots(bytes32 bucketId) external view returns (uint256);

    /// @notice The callback function that is called by the pool manager when the limit order is placed or cancelled
    /// @dev Function selects which logic to execute based on the action that is stored in the `ActionLib` library.
    /// - if the action is `ActionLib.PLACE_LMT_ORDER`, the function will place the limit order
    /// - if the action is `ActionLib.CANCEL_LMT_ORDER`, the function will cancel the limit order
    /// 
    ///IMPORTANT:
    /// - the function should be called by the PoolManager contract
    /// - the action should be set before calling this function (using the `setAction` modifier)
    ///
    /// @param data The data passed to the callback
    /// @return The data returned by the callback
    function unlockCallback(bytes calldata data) external returns (bytes memory);

    /// @notice Places a limit order for msg.sender 
    /// @dev Function calls `unlock()` on PoolManager which will do a callback to this contract into `unlockCallback()`,
    /// where the liquidity will be placed in the specified price range (`tickLower` - `tickLower` + `poolKey.tickSpacing`).
    /// After callback is done, the bucket will be created and the limit order liquidity will be recorded in the bucket.
    /// 
    ///IMPORTANT:
    /// - `tickLower` should be a multiple of `poolKey.tickSpacing`
    /// - `zeroForOne` true if the limit order selling token0 for token1; false if selling token1 for token0
    /// - `liquidity` can not be zero
    ///
    /// @param poolKey The key of the pool
    /// @param tickLower The lower tick of the limit order
    /// @param zeroForOne The direction of the limit order
    /// @param liquidity The liquidity of the limit order
    function placeLimitOrder(PoolKey calldata poolKey, int24 tickLower, bool zeroForOne, uint128 liquidity) external payable;

    /// @notice Cancels a limit order for msg.sender
    /// @dev Function calls `unlock()` on PoolManager which will do a callback to this contract into `unlockCallback()`,
    /// where the liquidity will be removed from the specified price range (`tickLower` - `tickLower` + `poolKey.tickSpacing`).
    /// After callback is done, the bucket will be updated and the limit order liquidity will be removed from the bucket.
    ///
    ///IMPORTANT:
    /// - the bucket should not be filled
    /// - user should have enough liquidity in the bucket
    ///
    /// @param poolKey The key of the pool
    /// @param tickLower The lower tick of the limit order
    /// @param zeroForOne The direction of the limit order
    function cancelLimitOrder(PoolKey calldata poolKey, int24 tickLower, bool zeroForOne) external;

    /// @notice The function is called by msg.sender to withdraw the swapped tokens after the limit order was executed (filled)
    /// @dev Function gets the bucket (which is already filled) and calculates an amount of tokens to transfer to msg.sender.
    ///
    ///IMPORTANT:
    /// - the bucket should be filled
    /// - user should have enough liquidity in the bucket
    ///
    /// @param poolKey The key of the pool
    /// @param tickLower The lower tick of the limit order
    /// @param zeroForOne The direction of the limit order
    /// @param slot The slot of the bucket
    function take(PoolKey calldata poolKey, int24 tickLower, bool zeroForOne, uint256 slot) external;

    /// @notice Returns the ID of the bucket.
    /// @dev The bucket ID is a keccak256 hash of `poolId`, `tick` and `zeroForOne`.
    /// It is used to identify the bucket in the `buckets` mapping and to identify the slot, where the bucket is stored.
    /// 
    /// It is worth to mention an importantance of the `zeroForOne` parameter in the bucket identification, because without it 
    /// you can’t interpret `Bucket.filled` value correctly. If you dont't include `zeroForOne` in the hash, then these 2 cases will collide into the same bucket:
    /// - bucket for range [tickLower, tickLower + tickSpacing] intended to sell token0
    /// - bucket for the exact same range intended to sell token1
    /// So, `zeroForOne` helps to differentiate between these 2 cases.
    /// 
    /// @param poolId The ID of the pool where the bucket is located
    /// @param tick The tick where the bucket is stored. We use the lower tick to identify the bucket
    /// @param zeroForOne The direction of the limit order (direction of the swap)
    /// @return The ID of the bucket
    function getBucketId(PoolId poolId, int24 tick, bool zeroForOne) external pure returns (bytes32);
}