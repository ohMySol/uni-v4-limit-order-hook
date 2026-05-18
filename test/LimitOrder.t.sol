// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";

import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

import {PoolManager} from "v4-core/PoolManager.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {SwapParams, ModifyLiquidityParams} from "v4-core/types/PoolOperation.sol";

import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "v4-core/types/BalanceDelta.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
 
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";

import {LimitOrder} from "../src/LimitOrder.sol";
import {EventsLib} from "../src/libraries/Events.sol";
import {ErrorsLib} from "../src/libraries/Errors.sol";

contract LimitOrderTest is Test, Deployers {
    using StateLibrary for IPoolManager;
    using CurrencyLibrary for Currency;
    using BalanceDeltaLibrary for BalanceDelta;
    using PoolIdLibrary for PoolId;

    // Tokens
    Currency public token0;
    Currency public token1;

    // Pool
    PoolKey public poolKey;

    // Limit Order Hook
    LimitOrder public hook;

    // Users
    address public alice;
    address public bob;

    function setUp() public {
        // 1. Deploy v4 core contracts
        deployFreshManagerAndRouters();

        // 2. Deploy and approve test tokens
        (token0, token1) = deployMintAndApprove2Currencies();

        // 3. Deploy the Limit Order hook
        // `|` - is a bitwise OR. It combines both flags listed inside () into a single number, where both bits are set.
        uint160 flags = uint160(Hooks.AFTER_INITIALIZE_FLAG | Hooks.AFTER_SWAP_FLAG);
        // Create a specific address whose lower bits already encode the permissions.
        address hookAddress = address(flags);
        // `deployCodeTo` - allows to deploy contract at an arbitrary address.
        // It compiles the `LimitOrder.sol` with the given constructor arguments into bytecode.
        // And after that injects this bytecode directly at `hookAddress`. 
        deployCodeTo("LimitOrder.sol", abi.encode(manager, ""), hookAddress);

        hook = LimitOrder(payable(hookAddress));

        // 4. Init pool with the hook
        // Fee = 3000 = 0.3%
        // Tick Spacing for this pool will be 60 (3000 / 100 * 2).
        // `SQRT_PRICE_1_1` - 1_1 in this context means the price of token1 in terms of token0. So 1_1 means that 1 token1 is worth 1 token0.
        (poolKey,) = initPool(token0, token1, hook, 3000, SQRT_PRICE_1_1);

        // 5. Set up users and their balances
        alice = vm.addr(1);
        bob = vm.addr(2);

        MockERC20(Currency.unwrap(token0)).mint(alice, 1_000_000e18);
        MockERC20(Currency.unwrap(token0)).mint(bob, 1_000_000e18);
        MockERC20(Currency.unwrap(token1)).mint(alice, 1_000_000e18);
        MockERC20(Currency.unwrap(token1)).mint(bob, 1_000_000e18);
        vm.startPrank(alice);
        MockERC20(Currency.unwrap(token0)).approve(address(hook), 1_000_000e18);
        MockERC20(Currency.unwrap(token1)).approve(address(hook), 1_000_000e18);
        vm.startPrank(bob);
        MockERC20(Currency.unwrap(token0)).approve(address(hook), 1_000_000e18);
        MockERC20(Currency.unwrap(token1)).approve(address(hook), 1_000_000e18);
        vm.stopPrank();
    }
    
    /* HELPER FUNCTIONS */

    /**
     * @dev A helper function to calculate the liquidity amount for a given amount of token0 or token1 and a tick range.
     * @param tickLower The lower tick of the range
     * @param tickUpper The upper tick of the range
     * @param amount0 Desired amount of token0 to provide as liquidity (set to 0 if providing only token1)
     * @param amount1 Desired amount of token1 to provide as liquidity (set to 0 if providing only token0)
     */
    function getLiquidityForAmount(
        int24 tickLower, 
        int24 tickUpper, 
        uint256 amount0, 
        uint256 amount1
    ) internal view returns (uint128 liquidity) {
        uint160 sqrtPriceLower = TickMath.getSqrtPriceAtTick(tickLower);
        uint160 sqrtPriceUpper = TickMath.getSqrtPriceAtTick(tickUpper);
        
        if (amount0 > 0 && amount1 == 0) {
            liquidity = LiquidityAmounts.getLiquidityForAmount0(
                sqrtPriceLower, 
                sqrtPriceUpper,
                amount0
            );
        } else if (amount1 > 0 && amount0 == 0) {
            liquidity = LiquidityAmounts.getLiquidityForAmount1(
                sqrtPriceLower, 
                sqrtPriceUpper,
                amount1
            );
        } else {
            revert("Only one of the amounts should be non-zero");
        }
    }

    /* INITIALIZATION TESTS*/
    
    function test_Hook_Initized_Successfully() public {
        assertEq(address(hook.poolManager()), address(manager));
    }

    function test_After_Initialization_Hook_Set_Correct_Tick() public {
        PoolId poolId = poolKey.toId();
        // Get tick that was set in the pool (should be 0, since we initialized the pool at price 1_1, which corresponds to tick 0).
        (,int24 tick,,) = manager.getSlot0(poolId);

        assertEq(tick, hook.ticks(poolId));
    }

    /* PLACE LIMIT ORDER TESTS */

    function test_User_Place_Limit_Order_Successfully() public {
        // Tick above current price (0) → position is 100% token0, selling token0 for token1
        int24 tickLower = 60;
        int24 tickUpper = tickLower + poolKey.tickSpacing; // 120
        uint128 liquidity = getLiquidityForAmount(tickLower, tickUpper, 1e18, 0);

        PoolId poolId = poolKey.toId();
        bytes32 bucketId = hook.getBucketId(poolId, tickLower, true);
        uint256 slot = hook.slots(bucketId); // 0 — first generation of this bucket

        uint256 aliceToken0Before = token0.balanceOf(alice);

        // Verify event is emitted with correct params before the call
        vm.expectEmit(true, true, true, true, address(hook));
        emit EventsLib.LimitOrder_Placed(alice, PoolId.unwrap(poolId), slot, tickLower, true, liquidity);

        vm.prank(alice);
        hook.placeLimitOrder(poolKey, tickLower, true, liquidity);

        // 1. Slot must not have advanced - bucket is active, not filled yet
        assertEq(hook.slots(bucketId), 0);

        // 2. Bucket reflects the placed liquidity and is not filled
        (bool filled, , , , , uint128 bucketLiquidity) = hook.buckets(bucketId, slot);
        assertFalse(filled);
        assertEq(bucketLiquidity, liquidity);

        // 3. Alice's userLiquidity inside the bucket equals what she deposited
        (uint128 userLiquidity,,,,) = hook.getUserBucketInfo(bucketId, slot, alice);
        assertEq(userLiquidity, liquidity);

        // 4. Alice's token0 balance decreased (tokens moved to the pool)
        uint256 aliceToken0After = token0.balanceOf(alice);
        assertEq(aliceToken0After, aliceToken0Before - 1e18);
    }

    function test_Set_Action_Resets_After_Call() public {
        int24 tickLower1 = 60;
        int24 tickLower2 = 120;
        uint128 liq1 = getLiquidityForAmount(tickLower1, tickLower1 + poolKey.tickSpacing, 1e18, 0);
        uint128 liq2 = getLiquidityForAmount(tickLower2, tickLower2 + poolKey.tickSpacing, 1e18, 0);

        vm.startPrank(alice);
        hook.placeLimitOrder(poolKey, tickLower1, true, liq1); // sets action = 1, resets to 0 after successful execution
        hook.placeLimitOrder(poolKey, tickLower2, true, liq2); // would revert if action wasn't reset
        vm.stopPrank();
    }

    function test_PlaceLimitOrder_Revert_If_TickLower_Is_Not_Multiple_Of_TickSpacing() public {
        int24 tickLower = 61;
        int24 tickUpper = tickLower + 2; // 61 - not a multiple of tick spacing (60)
        uint128 liquidity = getLiquidityForAmount(tickLower, tickUpper, 1e18, 0);

        vm.prank(alice);
        vm.expectRevert(ErrorsLib.LimitOrder_InvalidTickLower.selector);
        hook.placeLimitOrder(poolKey, tickLower, true, liquidity);
    }

    function test_PlaceLimitOrder_Revert_If_Provided_Liquidity_Is_Zero() public {
        int24 tickLower = 60;

        vm.expectRevert(ErrorsLib.LimitOrder_MissingLiquidity.selector);
        hook.placeLimitOrder(poolKey, tickLower, true, 0);
    }

    // zeroForOne = true means selling token0 for token1. Valid range is ABOVE current tick (0).
    // Placing at tickLower = -60 puts the range [-60, 0] BELOW current tick --> token1 is involved --> TickCrossed.
    function test_PlaceLimitOrder_ZeroForOne_Reverts_TickCrossed_When_Range_Below_Current_Tick() public {
        int24 tickLower = -60; // range [-60, 0] is below current tick 0
        int24 tickUpper = tickLower + poolKey.tickSpacing; // 0
        uint128 liquidity = getLiquidityForAmount(tickLower, tickUpper, 0, 1e18);

        vm.prank(alice);
        vm.expectRevert(ErrorsLib.LimitOrder_TickCrossed.selector);
        hook.placeLimitOrder(poolKey, tickLower, true, liquidity);
    }

    // zeroForOne = false means selling token1 for token0. Valid range is BELOW current tick (0).
    // Placing at tickLower=60 puts the range [60, 120] ABOVE current tick --> token0 is involved --> TickCrossed.
    function test_PlaceLimitOrder_OneForZero_Reverts_TickCrossed_When_Range_Above_Current_Tick() public {
        int24 tickLower = 60; // range [60, 120] is above current tick 0
        int24 tickUpper = tickLower + poolKey.tickSpacing; // 120
        uint128 liquidity = getLiquidityForAmount(tickLower, tickUpper, 1e18, 0);

        vm.prank(alice);
        vm.expectRevert(ErrorsLib.LimitOrder_TickCrossed.selector);
        hook.placeLimitOrder(poolKey, tickLower, false, liquidity);
    }

    // Sending ETH with an ERC20-ERC20 order must revert — no ETH should be sent for token-only pools.
    function test_PlaceLimitOrder_Reverts_When_EthSentForERC20() public {
        int24 tickLower = 60;
        int24 tickUpper = tickLower + poolKey.tickSpacing; // 120   
        uint128 liquidity = getLiquidityForAmount(tickLower, tickUpper, 1e18, 0);

        vm.deal(alice, 1 ether);
        vm.prank(alice);
        vm.expectRevert(ErrorsLib.LimitOrder_EthWasSent.selector);
        hook.placeLimitOrder{value: 1 ether}(poolKey, tickLower, true, liquidity);
    }

    // Sending less ETH than required for a native-token (ETH/ERC20) pool must revert.
    function test_PlaceLimitOrder_Reverts_When_InsufficientNativeTokenSent() public {
        // Set up a native token (ETH / token1) pool using the same hook.
        PoolKey memory nativeKey;
        (nativeKey,) = initPool(CurrencyLibrary.ADDRESS_ZERO, token1, hook, 3000, SQRT_PRICE_1_1);

        // Range [60, 120] is above current tick 0 --> position is 100% ETH (currency0).
        int24 tickLower = 60;
        int24 tickUpper = tickLower + nativeKey.tickSpacing; // 120
        uint128 liquidity = getLiquidityForAmount(tickLower, tickUpper, 1e18, 0);

        // Approve token1 for the hook (needed for alice's existing approvals to extend to this pool).
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        vm.expectRevert(ErrorsLib.LimitOrder_InsufficientFunds.selector);
        // 1 wei sent, but ~1e18 ETH required
        hook.placeLimitOrder{value: 1 wei}(nativeKey, tickLower, true, liquidity);
    }

    /* CANCEL LIMIT ORDER */

    function test_Order_Cancelled_Successfully() public {
        int24 tickLower = 60; // range [60, 120] is above current tick 0
        int24 tickUpper = tickLower + poolKey.tickSpacing; // 120
        uint128 liquidity = getLiquidityForAmount(tickLower, tickUpper, 1e18, 0); // corresponds to 1 token0

        // 1. Place limit order above the current price - selling token0 for token1
        uint256 aliceBalanceBeforePlacingOrder = token0.balanceOf(alice);

        vm.prank(alice);
        hook.placeLimitOrder(poolKey, tickLower, true, liquidity);
        // Balance should be decreased by 1 token (1e18)
        uint256 aliceBalanceAfterPlacingOrder = token0.balanceOf(alice);
        assertEq(aliceBalanceAfterPlacingOrder, aliceBalanceBeforePlacingOrder - 1e18);

        PoolId poolId = poolKey.toId();
        bytes32 bucketId = hook.getBucketId(poolId, tickLower, true);
        uint256 slot = hook.slots(bucketId); // 0 — first generation of this bucket

        // 2. Cancel the order
        // Verify event is emitted with correct params before the call
        vm.expectEmit(true, true, true, true, address(hook));
        emit EventsLib.LimitOrder_Cancelled(alice, PoolId.unwrap(poolId), slot, tickLower, true);

        uint256 aliceBalanceBeforeCancelOrder = token0.balanceOf(alice);

        vm.prank(alice);
        hook.cancelLimitOrder(poolKey, tickLower, true);

        uint256 aliceBalanceAfterCancelOrder = token0.balanceOf(alice);
        // Balance should be back to what it was before placing the order (1e18 back to Alice)
        assertApproxEqAbs(aliceBalanceAfterCancelOrder, aliceBalanceBeforeCancelOrder + 1e18, 1);

        // 3. Verify Alice liquidity in the bucket is removed and tokens returned to Alice + bucket liquidity reduced
        (uint128 userLiquidity,,,,) = hook.getUserBucketInfo(bucketId, slot, alice);
        assertEq(userLiquidity, 0);
        (bool filled,,,,, uint128 bucketLiquidityAfter) = hook.buckets(bucketId, slot);
        assertFalse(filled);
        assertEq(bucketLiquidityAfter, 0);
    }
}