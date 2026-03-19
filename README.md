# Uniswap v4 Limit Order Hook

**A Uniswap v4 Hook that enables on-chain limit orders 🦄**

### Get Started

This project implements a Uniswap v4 Hook that allows users to place limit orders that execute automatically during swaps when the price reaches specific tick levels. This provides centralized exchange-like limit order functionality fully on-chain.

Start by creating a new repository using the "Use this template" button at the top right of this page. Alternatively you can also click this link:

[![Use this Template](https://img.shields.io/badge/Use%20this%20Template-101010?style=for-the-badge&logo=github)](https://github.com/uniswapfoundation/v4-template/generate)

1. The limit order hook [LimitOrderHook.sol](src/LimitOrderHook.sol) demonstrates the `beforeSwap()` hook with `BeforeSwapDelta` to intercept and modify swaps for order execution
2. The test template [LimitOrderHook.t.sol](test/LimitOrderHook.t.sol) preconfigures the v4 pool manager, test tokens, and test liquidity with limit order scenarios.

<details>
<summary>Updating to v4-template:latest</summary>

This template is actively maintained -- you can update the v4 dependencies, scripts, and helpers:

```bash
git remote add template https://github.com/uniswapfoundation/v4-template
git fetch template
git merge template/main <BRANCH> --allow-unrelated-histories
```

</details>

### Requirements

This template is designed to work with Foundry (stable). If you are using Foundry Nightly, you may encounter compatibility issues. You can update your Foundry installation to the latest stable version by running:

```
foundryup
```

To set up the project, run the following commands in your terminal to install dependencies and run the tests:

```
forge install
forge test
```

### How It Works

The LimitOrderHook allows users to place limit orders that execute automatically when the pool price reaches the specified tick level during swaps.

#### Placing Orders
Users can place limit orders by calling `placeOrder()` with:
- `zeroForOne`: Direction of the order (true for selling token0, false for selling token1)
- `amountIn`: Amount of tokens to sell
- `targetTick`: The tick price at which to execute the order
- `minAmountOut`: Minimum output amount expected

When an order is placed, the hook takes the input tokens from the user using `poolManager.take()`.

#### Order Execution
During swaps, the `beforeSwap()` hook checks if any pending orders should be filled based on the current tick and swap direction:
- For sell orders (zeroForOne=true): Executes when current tick ≤ targetTick
- For buy orders (zeroForOne=false): Executes when current tick ≥ targetTick

When an order is filled, the hook returns a `BeforeSwapDelta` to modify the swap amounts, effectively executing the limit order by adjusting the token flows.

#### Key Features
- **On-chain execution**: Orders execute automatically during regular swaps
- **Tick-based pricing**: Uses Uniswap's tick system for precise price levels
- **Gas efficient**: Integrates with existing swap flows
- **Permissioned**: Uses specific hook flags for controlled execution

### Deployment

The hook requires specific permissions encoded in its deployment address:
- `beforeSwap`: To intercept swaps
- `beforeSwapReturnDelta`: To modify swap amounts for order execution

### Deployment on Unichain Testnet

This hook is designed to work on the Unichain testnet. To deploy:

1. Set up your environment variables for the testnet
2. Use the deployment scripts in `script/` directory
3. The hook will be deployed with the correct permissions for limit order execution

Note: Ensure your deployment address has the required hook flags encoded for `beforeSwap` and `beforeSwapReturnDelta` permissions.

1. Start Anvil (or fork a specific chain using anvil):

```bash
anvil
```

or

```bash
anvil --fork-url <YOUR_RPC_URL>
```

2. Execute scripts:

```bash
forge script script/00_DeployHook.s.sol \
    --rpc-url http://localhost:8545 \
    --private-key <PRIVATE_KEY> \
    --broadcast
```

### Using **RPC URLs** (actual transactions):

:::info
It is best to not store your private key even in .env or enter it directly in the command line. Instead use the `--account` flag to select your private key from your keystore.
:::

### Follow these steps if you have not stored your private key in the keystore:

<details>

1. Add your private key to the keystore:

```bash
cast wallet import <SET_A_NAME_FOR_KEY> --interactive
```

2. You will prompted to enter your private key and set a password, fill and press enter:

```
Enter private key: <YOUR_PRIVATE_KEY>
Enter keystore password: <SET_NEW_PASSWORD>
```

You should see this:

```
`<YOUR_WALLET_PRIVATE_KEY_NAME>` keystore was saved successfully. Address: <YOUR_WALLET_ADDRESS>
```

::: warning
Use `history -c` to clear your command history.
:::

</details>

1. Execute scripts:

```bash
forge script script/00_DeployHook.s.sol \
    --rpc-url <YOUR_RPC_URL> \
    --account <YOUR_WALLET_PRIVATE_KEY_NAME> \
    --sender <YOUR_WALLET_ADDRESS> \
    --broadcast
```

You will prompted to enter your wallet password, fill and press enter:

```
Enter keystore password: <YOUR_PASSWORD>
```

### Key Modifications to note:

1. Update the `token0` and `token1` addresses in the `BaseScript.sol` file to match the tokens you want to use in the network of your choice for sepolia and mainnet deployments.
2. Update the `token0Amount` and `token1Amount` in the `CreatePoolAndAddLiquidity.s.sol` file to match the amount of tokens you want to provide liquidity with.
3. Update the `token0Amount` and `token1Amount` in the `AddLiquidity.s.sol` file to match the amount of tokens you want to provide liquidity with.
4. Update the `amountIn` and `amountOutMin` in the `Swap.s.sol` file to match the amount of tokens you want to swap.

### Verifying the hook contract

```bash
forge verify-contract \
  --rpc-url <URL> \
  --chain <CHAIN_NAME_OR_ID> \
  # Generally etherscan
  --verifier <Verification_Provider> \
  # Use --etherscan-api-key <ETHERSCAN_API_KEY> if you are using etherscan
  --verifier-api-key <Verification_Provider_API_KEY> \
  --constructor-args <ABI_ENCODED_ARGS> \
  --num-of-optimizations <OPTIMIZER_RUNS> \
  <Contract_Address> \
  <path/to/Contract.sol:ContractName>
  --watch
```

### Troubleshooting

<details>

#### Permission Denied

When installing dependencies with `forge install`, Github may throw a `Permission Denied` error

Typically caused by missing Github SSH keys, and can be resolved by following the steps [here](https://docs.github.com/en/github/authenticating-to-github/connecting-to-github-with-ssh)

Or [adding the keys to your ssh-agent](https://docs.github.com/en/authentication/connecting-to-github-with-ssh/generating-a-new-ssh-key-and-adding-it-to-the-ssh-agent#adding-your-ssh-key-to-the-ssh-agent), if you have already uploaded SSH keys

#### Anvil fork test failures

Some versions of Foundry may limit contract code size to ~25kb, which could prevent local tests to fail. You can resolve this by setting the `code-size-limit` flag

```
anvil --code-size-limit 40000
```

#### Hook deployment failures

Hook deployment failures are caused by incorrect flags or incorrect salt mining

1. Verify the flags are in agreement:
   - `getHookCalls()` returns the correct flags
   - `flags` provided to `HookMiner.find(...)`
2. Verify salt mining is correct:
   - In **forge test**: the _deployer_ for: `new Hook{salt: salt}(...)` and `HookMiner.find(deployer, ...)` are the same. This will be `address(this)`. If using `vm.prank`, the deployer will be the pranking address
   - In **forge script**: the deployer must be the CREATE2 Proxy: `0x4e59b44847b379578588920cA78FbF26c0B4956C`
     - If anvil does not have the CREATE2 deployer, your foundry may be out of date. You can update it with `foundryup`

</details>

### Additional Resources

- [Uniswap v4 docs](https://docs.uniswap.org/contracts/v4/overview)
- [v4-periphery](https://github.com/uniswap/v4-periphery)
- [v4-core](https://github.com/uniswap/v4-core)
- [v4-by-example](https://v4-by-example.org)
