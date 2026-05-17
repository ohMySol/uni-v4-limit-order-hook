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
        emit EventsLib.LimitOrder_Place(alice, PoolId.unwrap(poolId), slot, tickLower, true, liquidity);

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
        assertLt(aliceToken0After, aliceToken0Before);
    }
}