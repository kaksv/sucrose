// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseHook} from "@openzeppelin/uniswap-hooks/src/base/BaseHook.sol";

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager, SwapParams, ModifyLiquidityParams} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary, toBeforeSwapDelta} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";

contract LimitOrderHook is BaseHook {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    struct LimitOrder {
        address user;
        bool zeroForOne; // true: sell token0 for token1, false: sell token1 for token0
        uint256 amountIn;
        int24 targetTick;
        uint256 minAmountOut;
        bool active;
    }

    mapping(PoolId => LimitOrder[]) public orders;

    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {}

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: true,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function getOrder(PoolId poolId, uint256 index) external view returns (LimitOrder memory) {
        return orders[poolId][index];
    }

    function placeOrder(
        PoolKey calldata key,
        bool zeroForOne,
        uint256 amountIn,
        int24 targetTick,
        uint256 minAmountOut
    ) external {
        PoolId poolId = key.toId();
        orders[poolId].push(LimitOrder({
            user: msg.sender,
            zeroForOne: zeroForOne,
            amountIn: amountIn,
            targetTick: targetTick,
            minAmountOut: minAmountOut,
            active: true
        }));

        // Transfer tokens to hook
        Currency tokenIn = zeroForOne ? key.currency0 : key.currency1;
        poolManager.take(tokenIn, msg.sender, amountIn);
    }

    function _beforeSwap(address, PoolKey calldata key, SwapParams calldata params, bytes calldata)
        internal
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        PoolId poolId = key.toId();
        (uint160 sqrtPriceX96, int24 currentTick,,) = poolManager.getSlot0(poolId);

        int128 deltaSpecified = 0;
        int128 deltaUnspecified = 0;

        for (uint i = 0; i < orders[poolId].length; i++) {
            LimitOrder storage order = orders[poolId][i];
            if (!order.active) continue;

            bool shouldFill = false;
            if (order.zeroForOne) {
                // Selling token0 for token1, fill when tick <= targetTick
                shouldFill = params.zeroForOne && currentTick <= order.targetTick;
            } else {
                // Selling token1 for token0, fill when tick >= targetTick
                shouldFill = !params.zeroForOne && currentTick >= order.targetTick;
            }

            if (shouldFill) {
                // Calculate amount to fill
                uint256 amountToFill = order.amountIn;
                if (amountToFill > uint128(type(int128).max)) amountToFill = uint128(type(int128).max);

                // For simplicity, assume we fill the entire order and provide equivalent output
                // In reality, you'd calculate the expected output based on the order
                if (order.zeroForOne) {
                    deltaSpecified = -int128(uint128(amountToFill)); // Take token0
                    deltaUnspecified = int128(uint128(amountToFill)); // Provide token1 (simplified)
                } else {
                    deltaSpecified = int128(uint128(amountToFill)); // Provide token0
                    deltaUnspecified = -int128(uint128(amountToFill)); // Take token1
                }

                order.active = false; // Mark as filled
                break; // Fill only one order for now
            }
        }

        BeforeSwapDelta delta = toBeforeSwapDelta(deltaSpecified, deltaUnspecified);

        return (BaseHook.beforeSwap.selector, delta, 0);
    }
}
