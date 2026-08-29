# Lido Staking Module Discovery

Node Operator search and pagination for CSM and Curated Module v2 through a single, efficient contract.

## Why SMDiscovery?

- **CSM & CMv2 Support**: Works with the Community Staking Module (full support, incl. deposit queue) and Curated Module v2 (discovery only — no queue operations)
- **Dynamic Routing**: Module and Accounting addresses resolved via StakingRouter and cached on demand
- **Simple**: No ownership, view-only functions, explicit cache management
- **Interface Detection**: Gracefully handles CSM-specific features (deposit queues) via `try/catch`
- **Future-Proof**: Compatible with any module implementing `IStakingModule` and exposing `ACCOUNTING()`

## Architecture

### Core Contract: SMDiscovery.sol

**Cache management**

- `updateModuleCache(moduleId)` — resolve the module address from StakingRouter *and* its `ACCOUNTING()` address, then cache both. Permissionless; must be called once per module before any query. Reverts if the module is already cached or doesn't implement `ACCOUNTING()`.

**Discovery (any cached module)**

- `findNodeOperatorsByAddress(moduleId, address, offset, limit, searchMode)` — search a range for operator IDs matching an address
- `getNodeOperatorsByAddress(moduleId, address, offset, limit)` — operator details matching a current (manager/reward) address
- `getNodeOperatorsByProposedAddress(moduleId, address, offset, limit)` — operator details matching a proposed (manager/reward) address
- `getAllNodeOperators(moduleId, offset, limit)` — full info (current + proposed addresses + curve) for every operator in a range
- `getOperatorsByCurveId(moduleId, curveId, offset, limit)` — operators assigned to a specific bond curve
- `getOperatorsWithLockedBond(moduleId, offset, limit)` — operators with a non-zero locked bond

> **Pagination note:** `getOperatorsByCurveId` and `getOperatorsWithLockedBond` paginate over operator-ID space `[offset, offset+limit)` and then filter. A returned page may therefore be shorter than `limit` — or empty — even when more matches exist beyond the window. Advance `offset` to keep scanning.

Bond-curve IDs and locked-bond data are read from the module's Accounting contract (cached during `updateModuleCache`).

### CSM-Specific Features

When querying CSM modules, additional functions are available:

- `getNodeOperatorsDepositableValidatorsCount(moduleId, offset, limit)` — paginated depositable validator counts per operator
- `getDepositQueueBatches(moduleId, queuePriority, cursorIndex, limit)` — traverse the deposit queue via linked-list, following `batch.next()`

**Note:** These queue operations only work with CSM. Calling them on a module without the CSM queue interface reverts with `ModuleDoesNotSupportQueueOperations`.

### Return Types

| Struct | Fields | Returned by |
|--------|--------|-------------|
| `NodeOperatorShort` | `id`, `managerAddress`, `rewardAddress`, `extendedManagerPermissions`, `curveId` | `getNodeOperatorsByAddress`, `getOperatorsByCurveId` |
| `NodeOperatorProposed` | `id`, `proposedManagerAddress`, `proposedRewardAddress`, `extendedManagerPermissions`, `curveId` | `getNodeOperatorsByProposedAddress` |
| `NodeOperatorInfo` | `id`, `managerAddress`, `rewardAddress`, `extendedManagerPermissions`, `proposedManagerAddress`, `proposedRewardAddress`, `curveId` | `getAllNodeOperators` |
| `NodeOperatorLockedBond` | `id`, `amount`, `until` | `getOperatorsWithLockedBond` |
| `Batch` | packed `uint256` (`nodeOperatorId`, `keysCount`, `next`); read `.next()` for the linked-list pointer | `getDepositQueueBatches` |

`SearchMode` enum: `CURRENT_ADDRESSES`, `PROPOSED_ADDRESSES`, `ALL_ADDRESSES`.

> `NodeOperatorLockedBond.until` is the timestamp the lock is retained until; compare it against `block.timestamp` to distinguish active from expired locks (`amount` may remain non-zero after expiry).

### Module IDs

#### Mainnet (Chain ID: 1)

| Module                          | ID | Contract Address                             |
|---------------------------------|----|----------------------------------------------|
| Community Staking Module (CSM)  | 3  | `0xdA7dE2ECdDfccC6c3AF10108Db212ACBBf9EA83F` |
| Curated Module (CM)             | 4  | `0xDa5F930cE326EB5205085D66c72A4E79d60cB8C1` |

#### Hoodi Testnet (Chain ID: 560048)

| Module                          | ID | Contract Address                             |
|---------------------------------|----|----------------------------------------------|
| Community Staking Module (CSM)  | 4  | `0x79CEf36D84743222f37765204Bec41E92a93E59d` |
| Curated Module (CM)             | 5  | `0x87EB69Ae51317405FD285efD2326a4a11f6173b9` |
| Community Staking 0x02 (CSM v2) | 6  | `0xbb7dd81FAC80f3Effa10eA8b973c15AE65a4CAf9` |

## Deployment

For mainnet, follow [docs/mainnet-deployment.md](docs/mainnet-deployment.md) — a step-by-step
runbook covering pre-flight, dry run, broadcast, Etherscan verification of both contracts,
the multisig upgrade handoff, and ossification.

### Local Fork
```bash
just deploy
```

### Live Network
```bash
# Dry run (recommended first)
CHAIN=mainnet just deploy-live-dry

# Deploy to mainnet
CHAIN=mainnet RPC_URL=<your-rpc> just deploy-live

# Verify on block explorer
CHAIN=mainnet RPC_URL=<your-rpc> just verify-live
```

### Upgrading

`SMDiscovery` sits behind an `OssifiableProxy`, so a new release replaces the
implementation and leaves the address alone.

```bash
# Dry run (recommended first) — pass --sender <admin> to exercise the upgrade path,
# since forge script's default sender is never the proxy admin
CHAIN=mainnet PROXY_ADDRESS=<proxy> just upgrade-live-dry --sender <admin>

# Deploy the new implementation and upgrade
CHAIN=mainnet RPC_URL=<your-rpc> PROXY_ADDRESS=<proxy> just upgrade-live
```

If the broadcaster is the proxy admin, the upgrade is sent directly. Otherwise the
script deploys the implementation and logs the `proxy__upgradeTo` calldata for the
admin multisig to submit. `STAKING_ROUTER` is read back from the existing proxy, so the
new implementation is always deployed against the router already in use — it is never
taken from a hardcoded constant.

### Environment Variables

- `CHAIN`: Target chain (`mainnet`, `hoodi`) - defaults to `mainnet`
- `RPC_URL`: RPC endpoint for live deployments
- `ANVIL_IP_ADDR`: Anvil host address (defaults to `127.0.0.1`)
- `PROXY_ADMIN`: Admin address for the OssifiableProxy - required by `just deploy` (including local Anvil, since `set dotenv-load` applies to both)
- `PROXY_ADDRESS`: Existing proxy to upgrade - required by `just upgrade-live`

## Usage Example

```solidity
// SMDiscovery sits behind an OssifiableProxy; point the ABI at the proxy address
SMDiscovery discovery = SMDiscovery(proxyAddress);

// Initialize cache for each module you need (resolves module + Accounting)
discovery.updateModuleCache(3); // CSM (mainnet)

// Search for Node Operator IDs by address
uint256[] memory operatorIds = discovery.findNodeOperatorsByAddress(
    3,                                      // moduleId (CSM on mainnet)
    0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb,
    0,                                      // offset
    100,                                    // limit
    SearchMode.CURRENT_ADDRESSES            // search mode enum
);

// Get operator details by current address
SMDiscovery.NodeOperatorShort[] memory operators =
    discovery.getNodeOperatorsByAddress(3, targetAddress, 0, 100);

// Filter operators by bond curve
SMDiscovery.NodeOperatorShort[] memory onCurve =
    discovery.getOperatorsByCurveId(3, 1 /* curveId */, 0, 100);

// Find operators with a locked bond
SMDiscovery.NodeOperatorLockedBond[] memory locked =
    discovery.getOperatorsWithLockedBond(3, 0, 100);

// Get CSM-specific data (deposit queue); Batch is imported from IBatch.sol
Batch[] memory batches =
    discovery.getDepositQueueBatches(
        3,          // moduleId
        0,          // queuePriority (0 = highest priority)
        0,          // cursorIndex (0 = start from queue head)
        10          // limit
    );
```

## Build Commands

```bash
just                # Clean and build (default)
just build          # Build contracts
just clean          # Clean artifacts
```

## Contract Addresses

| Chain          | StakingRouter                                | SMDiscovery (proxy)                          | Implementation                               |
|----------------|----------------------------------------------|----------------------------------------------|----------------------------------------------|
| Mainnet (1)    | `0xFdDf38947aFB03C621C71b06C9C70bce73f12999` | `0x106b2E4506f3b3D0A6Dfb41bCB4A64C10Fe32b92` | `0x51E161a6989867E9EE640dFcCE15b9A983936d63` |
| Hoodi (560048) | `0xCc820558B39ee15C7C45B59390B503b83fb499A8` | `0x9f869227c456feD9A50e272224E438b0e79c6387` | `0xB8929265b77c5Eb6F66A607D9e4002A58142A8bD` |

Consumers should use the **proxy** address; the implementation is listed only for explorer
verification and changes on every release.

Proxy admins are currently the deploying EOAs — mainnet `0x3E8f6E55601BEF766634e43B26c99C4C01F71863`,
hoodi `0x937B9327225f1756f9bb807C0f2Db37bDA002F30`. Moving the mainnet admin to a multisig
is a `proxy__changeAdmin` call and does not require a redeploy.

Pre-proxy deployments, now superseded by the proxies above and kept only for reference:
mainnet `0x6a9c16626D64dFe7A185eb6378F8eB901f96281C`,
hoodi `0xb3dFdcE02a83454F38Fd127E6261F7AdcDA86B47`.

## Testing

15 tests across 6 files cover proxy mechanics, selector collisions, storage layout, queue detection, and the deploy/upgrade scripts — see `CLAUDE.md`'s Testing section for the breakdown. Framework: Foundry with forge-std.

```bash
forge test                          # Run all tests
forge test --match-test testName    # Specific test
forge test --gas-report             # With gas reporting
```

## License

GPL-3.0 — see [LICENSE](LICENSE).
