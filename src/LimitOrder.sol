// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseHook} from "v4-hooks-public/src/base/BaseHook.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";

import {SwapParams, ModifyLiquidityParams} from "v4-core/types/PoolOperation.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "v4-core/types/BalanceDelta.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {SafeCast} from "v4-core/libraries/SafeCast.sol";

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {ILimitOrder, Bucket} from "./interfaces/ILimitOrder.sol";

import {EventsLib} from "./libraries/Events.sol";
import {ErrorsLib} from "./libraries/Errors.sol";

/// @title Limit Order Hook
/// @author @ohMySol
/// @notice A hook that allows users to create limit orders on Uniswap V4 pools
/// @dev This hook is a basic implementation of a limit order hook for Uniswap V4 pools. 
/// User can create limit orders and cancel them if the order is not executed. 
/// Limit orders are represented by a liquditity provided in a certain range of ticks (lower and upper tick). This tick
/// range should be greater or lower than the current tick in the pool to be a valid limit order.
/// Once the limit order is created, it will be executed when the price of the pool is within the range of the limit order.
///
/// Example: ETH/USDC pool; current price of ETH in terms of USDC is $4500; you want to sell 1 ETH when the price is $5000.
/// So you provide a liquidity as 100% ETH at the lower tick corresponding to $5000. 
/// Lower tick = $5000 means that your liquidity (1 ETH) will be inactive when the price is below $5000. Once the price is $5000
/// and above, your liquidity becomes active and it will be swapped for USDC.
contract LimitOrder is BaseHook, ILimitOrder {
    using SafeCast for int128;
    using SafeCast for uint128;
    using CurrencyLibrary for Currency;
    using BalanceDeltaLibrary for BalanceDelta;
    using PoolIdLibrary for PoolId;

    /* STATE VARIABLES */

    /// @inheritdoc ILimitOrder
    mapping(PoolId poolId => int24 tick) public ticks;
    
    /// @inheritdoc ILimitOrder
    mapping(bytes32 bucketId => uint256 slot) public slots;
    
    /// @notice The mapping which stores the bucket values
    mapping(bytes32 bucketId => mapping(uint256 slot => Bucket bucket)) public buckets;

    /// @notice Constructor to initialize the hook with the pool manager
    /// @param _poolManager The address of the pool manager
    constructor(address _poolManager) BaseHook(IPoolManager(_poolManager)) {
        poolManager = IPoolManager(_poolManager);
    }

    /// @notice Receive function to allow the hook to receive native token
    receive() external payable {}

    /* HOOK FUNCTIONS */

    /// @inheritdoc BaseHook
    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: true,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: false,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    /// @inheritdoc BaseHook
    /// @dev After pool initialization this hook will fetch the current tick of the pool and store it in the `ticks` mapping
    function _afterInitialize(
        address sender, 
        PoolKey calldata poolKey, 
        uint160 sqrtPriceX96, 
        int24 tick
    ) internal virtual override returns (bytes4) {
        PoolId poolId = poolKey.toId();
        ticks[poolId] = tick;
        return this.afterInitialize.selector;
    }

    /// @inheritdoc BaseHook
    function _afterSwap(
        address sender, 
        PoolKey calldata key, 
        SwapParams calldata params, 
        BalanceDelta delta, 
        bytes calldata hookData
    )
        internal virtual override returns (bytes4, int128)
    {
        return (bytes4(0), 0);
    }

    /* LIMIT ORDER FUNCTIONS */

    /// @inheritdoc ILimitOrder
    function placeLimitOrder(
        PoolKey calldata poolKey, 
        int24 tickLower, 
        bool zeroForOne,
        uint128 liquidity
    ) external payable {}

    /// @inheritdoc ILimitOrder
    function cancelLimitOrder(
        PoolKey calldata poolKey, 
        int24 tickLower, 
        bool zeroForOne
    ) external {}

    /// @inheritdoc ILimitOrder
    function take(
        PoolKey calldata poolKey, 
        int24 tickLower, 
        bool zeroForOne,
        uint256 slot
    ) external {}
}