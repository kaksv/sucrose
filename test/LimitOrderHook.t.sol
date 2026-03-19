// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {Constants} from "@uniswap/v4-core/test/utils/Constants.sol";

import {EasyPosm} from "./utils/libraries/EasyPosm.sol";

import {LimitOrderHook} from "../src/LimitOrderHook.sol";
import {BaseTest} from "./utils/BaseTest.sol";

contract LimitOrderHookTest is BaseTest {
    using EasyPosm for IPositionManager;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    Currency currency0;
    Currency currency1;

    PoolKey poolKey;

    LimitOrderHook hook;
    PoolId poolId;

    uint256 tokenId;
    int24 tickLower;
    int24 tickUpper;

    function setUp() public {
        // Deploys all required artifacts.
        deployArtifactsAndLabel();

        (currency0, currency1) = deployCurrencyPair();

        // Deploy the hook to an address with the correct flags
        address flags = address(
            uint160(
                Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
            ) ^ (0x4444 << 144) // Namespace the hook to avoid collisions
        );
        bytes memory constructorArgs = abi.encode(poolManager); // Add all the necessary constructor arguments from the hook
        deployCodeTo("LimitOrderHook.sol:LimitOrderHook", constructorArgs, flags);
        hook = LimitOrderHook(flags);

        // Create the pool
        poolKey = PoolKey(currency0, currency1, 3000, 60, IHooks(hook));
        poolId = poolKey.toId();
        poolManager.initialize(poolKey, Constants.SQRT_PRICE_1_1);

        // Provide full-range liquidity to the pool
        tickLower = TickMath.minUsableTick(poolKey.tickSpacing);
        tickUpper = TickMath.maxUsableTick(poolKey.tickSpacing);

        uint128 liquidityAmount = 100e18;

        (uint256 amount0Expected, uint256 amount1Expected) = LiquidityAmounts.getAmountsForLiquidity(
            Constants.SQRT_PRICE_1_1,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            liquidityAmount
        );

        (tokenId,) = positionManager.mint(
            poolKey,
            tickLower,
            tickUpper,
            liquidityAmount,
            amount0Expected + 1,
            amount1Expected + 1,
            address(this),
            block.timestamp,
            Constants.ZERO_BYTES
        );
    }

    function testPlaceLimitOrder() public {
        // Approve poolManager to spend tokens
        currency0.approve(address(poolManager), type(uint256).max);
        currency1.approve(address(poolManager), type(uint256).max);

        // Place a limit order: sell token0 for token1 when tick <= -1000
        int24 targetTick = -1000;
        uint256 amountIn = 1e18;
        uint256 minAmountOut = 0;

        hook.placeOrder(poolKey, true, amountIn, targetTick, minAmountOut);

        // Check that order was placed
        LimitOrderHook.LimitOrder memory order = hook.getOrder(poolId, 0);
        assertEq(order.user, address(this));
        assertEq(order.zeroForOne, true);
        assertEq(order.amountIn, amountIn);
        assertEq(order.targetTick, targetTick);
        assertEq(order.active, true);
    }

    function testExecuteLimitOrder() public {
        // First place an order
        int24 targetTick = TickMath.getTickAtSqrtPrice(Constants.SQRT_PRICE_1_1) - 100; // Below current tick
        uint256 amountIn = 1e18;
        uint256 minAmountOut = 0;

        // Approve poolManager to spend tokens
        currency0.approve(address(poolManager), type(uint256).max);
        currency1.approve(address(poolManager), type(uint256).max);

        hook.placeOrder(poolKey, true, amountIn, targetTick, minAmountOut);

        // Perform a swap that should trigger the order
        uint256 swapAmountIn = 10e18;
        BalanceDelta swapDelta = swapRouter.swapExactTokensForTokens({
            amountIn: swapAmountIn,
            amountOutMin: 0,
            zeroForOne: true,
            poolKey: poolKey,
            hookData: Constants.ZERO_BYTES,
            receiver: address(this),
            deadline: block.timestamp + 1
        });

        // Check that the order was executed (marked inactive)
        LimitOrderHook.LimitOrder memory executedOrder = hook.getOrder(poolId, 0);
        assertEq(executedOrder.active, false);
    }
}
