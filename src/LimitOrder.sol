// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BaseHook} from "v4-hooks-public/src/base/BaseHook.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";

import {SwapParams, ModifyLiquidityParams} from "v4-core/types/PoolOperation.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "v4-core/types/BalanceDelta.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {ILimitOrder, Bucket} from "./interfaces/ILimitOrder.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

import {EventsLib} from "./libraries/Events.sol";
import {ErrorsLib} from "./libraries/Errors.sol";
import {ActionLib} from "./libraries/ActionLib.sol";
import {SafeCast} from "./libraries/SafeCast.sol";


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

    /* MODIFIERS */

    /// @notice Modifier to set the action for the limit order
    /// @dev Modiifier set `action` to the `ActionLib.SLOT` and reset it to 0 after the function call.
    /// It is used to identify the action in the `unlockCallback` function. It also works as a reentrancy guard.
    /// @param action The action to set (ActionLib.PLACE_LMT_ORDER or ActionLib.CANCEL_LMT_ORDER)
    modifier setAction(uint256 action) {
        if (ActionLib.getAction() != 0) revert ErrorsLib.LimitOrder_ActionAlreadySet();
        if (action < 1 || action > 2) revert ErrorsLib.LimitOrder_InvalidAction();
        ActionLib.setAction(action);
        _;
        ActionLib.setAction(0);
    }

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
    ) internal virtual override returns (bytes4, int128) {
        return (bytes4(0), 0);
    }

    /// @inheritdoc ILimitOrder
    function unlockCallback(bytes calldata data) external onlyPoolManager returns (bytes memory) {
        if (ActionLib.getAction() == ActionLib.PLACE_LMT_ORDER) {
            (
                address msgSender,
                uint256 msgValue,
                PoolKey memory poolKey,
                int24 tickLower,
                bool zeroForOne,
                uint128 liquidity
            ) = abi.decode(data, (address, uint256, PoolKey, int24, bool, uint128));

            (BalanceDelta delta,) = poolManager.modifyLiquidity({
                    key: poolKey,
                    params: ModifyLiquidityParams({
                        tickLower: tickLower,
                        tickUpper: tickLower + poolKey.tickSpacing,
                        liquidityDelta: int256(uint256(liquidity)), // safe cast 
                        salt: bytes32(0)
                    }),
                    hookData: ""
                }
            );

            int128 amount0 = delta.amount0();
            int128 amount1 = delta.amount1();

            // determine the currency and amount to pay for the limit order
            Currency currency;
            uint256 amountToPay;
            // if the order is currency0 --> currency1, the amount0 should be negative and amount1 should be zero,
            // and vice versa for currency1 --> currency0
            if (zeroForOne) {
                if (amount0 > 0 && amount1 != 0) revert ErrorsLib.LimitOrder_TickCrossed();
                currency = poolKey.currency0;
                amountToPay = (-amount0).toUint256();
            } else {
                if (amount1 > 0 && amount0 != 0) revert ErrorsLib.LimitOrder_TickCrossed();
                currency = poolKey.currency1;
                amountToPay = (-amount1).toUint256();
            }

            // sync the pool
            poolManager.sync(currency);

            if (currency.isAddressZero()) {
                if (msgValue < amountToPay) revert ErrorsLib.LimitOrder_InsufficientFunds();
                
                poolManager.settle{value: amountToPay}();

                if (msgValue > amountToPay) {
                    (bool success,) = payable(msgSender).call{value: msgValue - amountToPay}("");
                    if (!success) revert ErrorsLib.LimitOrder_TransferFailed();
                }
            } else {
                if (msgValue != 0) revert ErrorsLib.LimitOrder_EthWasSent();
                IERC20(Currency.unwrap(currency)).transferFrom(msgSender, address(poolManager), amountToPay);
                poolManager.settle();
            }

            return "";
        } else if (ActionLib.getAction() == ActionLib.CANCEL_LMT_ORDER) {}
    }

    /* LIMIT ORDER FUNCTIONS */

    /// @inheritdoc ILimitOrder
    function placeLimitOrder(
        PoolKey calldata poolKey, 
        int24 tickLower, 
        bool zeroForOne,
        uint128 liquidity
    ) external payable setAction(ActionLib.PLACE_LMT_ORDER) {
        if (tickLower % poolKey.tickSpacing != 0) revert ErrorsLib.LimitOrder_InvalidTickLower();
        if (liquidity == 0) revert ErrorsLib.LimitOrder_MissingLiquidity();

        // Calling `unlock()` first because it is reentrancy safe, and it is more efficient in case of revert.
        poolManager.unlock(
            abi.encode(
                msg.sender,
                msg.value,
                poolKey,
                tickLower,
                zeroForOne,
                liquidity
            )
        );

        bytes32 bucketId = getBucketId(poolKey.toId(), tickLower, zeroForOne);
        uint256 slot = slots[bucketId];
        
        Bucket storage bucket = buckets[bucketId][slot];
        bucket.liquidity += liquidity;
        bucket.userLiquidity[msg.sender] += liquidity;

        emit EventsLib.LimitOrder_Place(
            msg.sender,
            PoolId.unwrap(poolKey.toId()), 
            slot,
            tickLower, 
            zeroForOne, 
            liquidity
        );
    }

    /// @inheritdoc ILimitOrder
    function cancelLimitOrder(
        PoolKey calldata poolKey, 
        int24 tickLower, 
        bool zeroForOne
    ) external setAction(ActionLib.CANCEL_LMT_ORDER) {}

    /// @inheritdoc ILimitOrder
    function take(
        PoolKey calldata poolKey, 
        int24 tickLower, 
        bool zeroForOne,
        uint256 slot
    ) external {}

    /* HELPER FUNCTIONS */

    /// @inheritdoc ILimitOrder
    function getBucketId(PoolId poolId, int24 tick, bool zeroForOne) public pure returns (bytes32) {
        return keccak256(abi.encode(PoolId.unwrap(poolId), tick, zeroForOne));
    }
}