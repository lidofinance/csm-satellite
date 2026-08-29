# SMDiscovery behind an upgradeable proxy

Status: implemented.

## Problem

Every additive view method means a fresh `SMDiscovery` deployment: new address, new
verification, a `updateModuleCache()` transaction per module per chain, plus edits to
`CLAUDE.md`, `README.md`, `artifacts/`, `script/update-module-cache.sh` and the consuming
frontend config. `TODO.md` queues roughly ten more methods, so this cycle repeats.

The address is currently consumed only by a Lido-controlled frontend/SDK, where a redeploy
costs a config PR. The decision is therefore driven less by integrator breakage than by
timing: introducing a proxy now costs one final address change, while introducing it after
the address reaches dashboards, docs or third parties costs coordination we do not control.

## Decision

Put `SMDiscovery` behind Lido's `OssifiableProxy` — the same proxy CSM's own contracts use.
Upgrade admin is a team-controlled multisig, justified because the contract holds no funds
and has no permissions over any Lido contract. `proxy__ossify()` is the endgame once the ABI
stabilises.

Rejected alternatives:

- **Hand-rolled minimal ERC1967 proxy** (zero new dependencies) — trades an audited artifact
  for an unreviewed one. The dependency is cheaper than the risk.
- **OZ `TransparentUpgradeableProxy`** — needs OpenZeppelin anyway, adds a separate
  `ProxyAdmin`, diverges from Lido convention for no gain.
- **UUPS** — puts upgrade logic in the implementation, so a future release that forgets to
  inherit it bricks the contract permanently.
- **CREATE2** — fixes the address for a given bytecode; changed code still changes the address.

## Why this is cheap here

`SMDiscovery` requires **no modification at all**:

- `STAKING_ROUTER` is `immutable`, so it lives in the implementation's bytecode and resolves
  correctly through `delegatecall`. It does not need to move to storage.
- `moduleCache` is populated by the permissionless `updateModuleCache()`, not by the
  constructor. No `initialize()`, no initializer modifier, no uninitialized-implementation
  hazard.
- The contract inherits nothing and has a single mapping at slot 0, so no storage gap is
  needed.

## Storage layout rules

| Slot | Variable | Notes |
|------|----------|-------|
| 0 | `mapping(uint256 => ModuleCacheData) moduleCache` | 2 slots per entry; the two `address` fields do not pack |

Append new variables only. Never reorder, never retype, never change `ModuleCacheData`'s
field order or types.

## Components

```
lib/openzeppelin-contracts         new submodule, pinned to v5.4.0 (CSM's own pin)
src/lib/proxy/OssifiableProxy.sol  vendored from lidofinance/community-staking-module;
                                   sole modification is the pragma, 0.8.33 -> 0.8.24
src/SMDiscovery.sol                unchanged
remappings.txt                     @openzeppelin/contracts/=lib/openzeppelin-contracts/contracts/
```

The exact `proxy__*` signatures are taken from the vendored source.

The upstream file is GPL-3.0. This repository is already GPL-3.0 (`LICENSE`, and
`src/interfaces/IStakingRouter.sol` carries the same header), so vendoring raises no
licensing question. OpenZeppelin is pinned at `v5.4.0`; other files in the package go up to `^0.8.27`, but among the files this proxy actually imports (`ERC1967Proxy.sol`, `ERC1967Utils.sol`, `Proxy.sol`, `StorageSlot.sol`, `IERC1967.sol`) the strictest pragma is `^0.8.22`.

The OZ version pin is load-bearing, not incidental. OZ v5.6.0 added an
`ERC1967ProxyUninitialized` guard that reverts when `ERC1967Proxy` is constructed with empty
`_data`. This design passes empty `_data` on purpose, because `SMDiscovery` has no initializer
and must not gain one, so any OZ >= 5.6.0 breaks construction outright. The guard exists to stop
an attacker front-running an uninitialized proxy's `initialize()`; that window does not exist
here, since there is no initializer to call and the admin is set atomically in
`OssifiableProxy`'s constructor. Pin to v5.4.0, the tag CSM pins.

## Deploy and upgrade scripts

`DeployBase.s.sol` gains a `proxyAdmin` field read via `vm.envOr("PROXY_ADMIN", address(0))`
and rejected with `ProxyAdminNotSet()` if still zero. There is no fallback to `msg.sender`, so
an admin key is never assigned implicitly. Local anvil runs (`just deploy`) therefore need
`PROXY_ADMIN` set in `.env`, which `just`'s `set dotenv-load` already picks up. The script
deploys the implementation, then the proxy, then initialises the module cache *through the
proxy address*.

New `UpgradeBase.s.sol` with `UpgradeMainnet` / `UpgradeHoodi` subclasses, reading the proxy
address via the same `vm.envOr(..., address(0))` / `ProxyAddressNotSet()` pattern rather than
hardcoding it per chain. It deploys only a new implementation, then branches:

- caller is the proxy admin (hoodi, team EOA) — broadcast `proxy__upgradeTo` directly;
- caller is not (mainnet, multisig) — log the target and the `proxy__upgradeTo` calldata.

`justfile` gains `upgrade-live`, `upgrade-live-dry` and `upgrade-live-no-confirm`, mirroring
the existing deploy recipes.

## Tests

Extending `test/`, following the existing fork-test pattern that skips when `RPC_URL` is unset.

- `Proxy.t.sol` — cache survives an upgrade; non-admin cannot upgrade; `proxy__ossify()`
  permanently blocks further upgrades; `STAKING_ROUTER` resolves correctly through
  `delegatecall`.
- `SelectorCollision.t.sol` — no `SMDiscovery` selector equals any `proxy__*` selector.
  `OssifiableProxy` is non-transparent, so its own functions are dispatched ahead of the
  fallback and permanently shadow a colliding implementation function, silently rather than
  by reverting. This test guards every method still queued in `TODO.md`.
- `QueueDetection.t.sol` — parameterise `setUp` to run the existing assertions against both a
  direct and a proxied instance. `_tryGetMaxQueuePriority` performs a `this.`-prefixed external
  self-call, which behind a proxy re-enters the proxy and delegatecalls back. This is expected
  to work, but a silent failure would disable CSM queue detection entirely.

## Migration

Hoodi first, validated, then mainnet. Each chain's address changes exactly once.

The existing `SMDiscovery` deployments stay live and are marked deprecated in the docs rather
than decommissioned; they are view-only and harmless.

Follow-up edits: `CLAUDE.md` deployed-contracts table split into Proxy and Implementation
columns; `script/update-module-cache.sh` case statement pointed at the proxies; `README.md`;
`artifacts/{chain}/`. Verification covers both the implementation and the proxy, on both
explorers for hoodi.

`update-module-cache.sh` remains necessary for the first cache initialisation and for when
StakingRouter's module address changes — it is simply no longer part of every release.

## Accepted risk

A multisig that can swap the implementation can make the contract return fabricated data.
No funds are at risk, but a UI rendering `rewardAddress` or bond data from it could be made
to mislead users. `proxy__ossify()` closes this once the ABI settles.
