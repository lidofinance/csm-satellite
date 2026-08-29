# SMDiscovery Proxy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Put `SMDiscovery` behind Lido's `OssifiableProxy` so its address survives future releases.

**Architecture:** Vendor `OssifiableProxy` from CSM over an OpenZeppelin v5.4.0 submodule. `SMDiscovery.sol` itself is not modified — it needs no initializer because `STAKING_ROUTER` is `immutable` (lives in implementation bytecode, resolves through `delegatecall`) and `moduleCache` is filled by the permissionless `updateModuleCache()`. Deploy and upgrade scripts read the proxy admin and proxy address from environment variables.

**Tech Stack:** Solidity 0.8.24, Foundry, OpenZeppelin Contracts v5.4.0, Just.

**Spec:** `docs/proxy-design.md`

## Global Constraints

- Solidity pragma is exactly `0.8.24` for every file in `src/` and `script/`. The vendored proxy ships with `0.8.33` and MUST be relaxed to `0.8.24`; OZ v5.4.0's strictest pragma is `^0.8.22`, so this compiles.
- OpenZeppelin pinned at tag `v5.4.0` — the exact version CSM pins. **Do not bump this.**
  OZ `v5.6.0` added an `ERC1967ProxyUninitialized` guard that reverts when `ERC1967Proxy` is
  constructed with empty `_data`, unless `_unsafeAllowUninitialized()` is overridden. This design
  passes empty `_data` on purpose (SMDiscovery has no initializer and must not gain one), so any
  OZ >= 5.6.0 breaks construction. Pinning to CSM's tag also keeps the vendored file identical to
  the audited artifact. Do not use a floating branch.
- Remapping is exactly `@openzeppelin/contracts/=lib/openzeppelin-contracts/contracts/`.
- The repo is GPL-3.0 (settled in commit `e9ad76c`: `LICENSE`, README and every `.sol` header now agree). The vendored `OssifiableProxy.sol` keeps its original GPL-3.0 header and Lido copyright line. Every new file uses `// SPDX-License-Identifier: GPL-3.0`.
- `SMDiscovery.sol` MUST NOT be modified by any task in this plan. If a task appears to require changing it, stop and report.
- `moduleCache` stays at storage slot 0. New state variables may only be appended.
- **Exactly one test function may write any given environment variable.** `vm.setEnv` mutates
  process-global state and forge runs tests in parallel, so two tests writing the same variable
  race. `foundry.toml`'s `threads` key does NOT fix this — it is parsed but ignored at run time on
  Foundry 1.7.1. `test/DeployScript.t.sol` owns `PROXY_ADMIN`; `test/UpgradeScript.t.sol` owns
  `PROXY_ADDRESS`. Never write either from `setUp()`.
- Proxy mechanics are tested with local mocks, not forks. Only `QueueDetection.t.sol` uses a fork, and it keeps its existing skip-when-`RPC_URL`-unset behaviour.

## Out of Scope

This plan delivers code, tests, and documentation structure. Actually broadcasting to hoodi and mainnet is a separate operations step run through the repo's `deploy` skill, because the resulting proxy addresses cannot be known while writing this plan. Tasks that reference those addresses parameterise them through environment variables rather than hardcoding placeholders.

---

### Task 1: Vendor OssifiableProxy and prove immutables survive delegatecall

**Files:**
- Create: `lib/openzeppelin-contracts` (submodule, tag `v5.4.0`)
- Modify: `remappings.txt` (currently empty)
- Create: `src/lib/proxy/OssifiableProxy.sol`
- Create: `test/mocks/StakingRouterMock.sol`
- Create: `test/mocks/StakingModuleMock.sol`
- Test: `test/Proxy.t.sol`

**Interfaces:**
- Consumes: `SMDiscovery(address _stakingRouter)`, `SMDiscovery.STAKING_ROUTER()`, `SMDiscovery.updateModuleCache(uint256)`, `SMDiscovery.moduleCache(uint256) returns (address,address)` — all existing.
- Produces:
  - `OssifiableProxy(address implementation_, address admin_, bytes memory data_)`
  - `OssifiableProxy.proxy__upgradeTo(address)`, `.proxy__ossify()`, `.proxy__changeAdmin(address)`, `.proxy__getAdmin() returns (address)`, `.proxy__getImplementation() returns (address)`, `.proxy__getIsOssified() returns (bool)`
  - Errors `OssifiableProxy.NotAdmin`, `OssifiableProxy.ProxyIsOssified`
  - `StakingRouterMock.setModule(uint256 id, address moduleAddress)`
  - `StakingModuleMock(address accounting_)`
  - Note: `OssifiableProxy` declares `receive() external payable`, so casting an address to it requires `OssifiableProxy(payable(addr))`.

- [ ] **Step 1: Add the OpenZeppelin submodule pinned to v5.4.0**

```bash
git submodule add https://github.com/OpenZeppelin/openzeppelin-contracts lib/openzeppelin-contracts
git -C lib/openzeppelin-contracts checkout v5.4.0
git -C lib/openzeppelin-contracts submodule update --init --recursive
```

Verify the pin resolved: `git -C lib/openzeppelin-contracts describe --tags` must print `v5.4.0`.

- [ ] **Step 2: Write the remapping**

Overwrite `remappings.txt` with exactly:

```
@openzeppelin/contracts/=lib/openzeppelin-contracts/contracts/
```

- [ ] **Step 3: Write the mocks**

`test/mocks/StakingRouterMock.sol`:

```solidity
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import {IStakingRouter} from "../../src/interfaces/IStakingRouter.sol";

contract StakingRouterMock {
    mapping(uint256 => address) internal _modules;

    function setModule(uint256 id, address moduleAddress) external {
        _modules[id] = moduleAddress;
    }

    function getStakingModule(
        uint256 id
    ) external view returns (IStakingRouter.StakingModule memory sm) {
        sm.id = uint24(id);
        sm.stakingModuleAddress = _modules[id];
    }
}
```

`test/mocks/StakingModuleMock.sol`:

```solidity
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

contract StakingModuleMock {
    address public accountingAddress;

    constructor(address accounting_) {
        accountingAddress = accounting_;
    }

    // solhint-disable-next-line func-name-mixedcase
    function ACCOUNTING() external view returns (address) {
        return accountingAddress;
    }
}
```

- [ ] **Step 4: Write the failing test**

`test/Proxy.t.sol`:

```solidity
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {SMDiscovery} from "../src/SMDiscovery.sol";
import {OssifiableProxy} from "../src/lib/proxy/OssifiableProxy.sol";
import {StakingRouterMock} from "./mocks/StakingRouterMock.sol";
import {StakingModuleMock} from "./mocks/StakingModuleMock.sol";

contract ProxyTest is Test {
    uint256 internal constant MODULE_ID = 3;
    address internal constant ADMIN = address(0xA11CE);
    address internal constant ACCOUNTING = address(0xACC0);

    StakingRouterMock internal router;
    StakingModuleMock internal module;
    SMDiscovery internal implementation;
    OssifiableProxy internal proxy;
    SMDiscovery internal discovery;

    function setUp() public {
        router = new StakingRouterMock();
        module = new StakingModuleMock(ACCOUNTING);
        router.setModule(MODULE_ID, address(module));

        implementation = new SMDiscovery(address(router));
        proxy = new OssifiableProxy(address(implementation), ADMIN, "");
        discovery = SMDiscovery(address(proxy));
    }

    function test_immutableStakingRouter_resolvesThroughDelegatecall()
        external
        view
    {
        assertEq(address(discovery.STAKING_ROUTER()), address(router));
    }

    function test_proxy_reportsAdminAndImplementation() external view {
        assertEq(proxy.proxy__getAdmin(), ADMIN);
        assertEq(proxy.proxy__getImplementation(), address(implementation));
        assertFalse(proxy.proxy__getIsOssified());
    }

    function test_updateModuleCache_writesThroughProxy() external {
        discovery.updateModuleCache(MODULE_ID);
        (address moduleAddress, address accountingAddress) = discovery
            .moduleCache(MODULE_ID);
        assertEq(moduleAddress, address(module));
        assertEq(accountingAddress, ACCOUNTING);
    }
}
```

- [ ] **Step 5: Run test to verify it fails**

Run: `forge test --match-path test/Proxy.t.sol -vv`

Expected: compilation failure — `Source "src/lib/proxy/OssifiableProxy.sol" not found`.

- [ ] **Step 6: Vendor the proxy**

Create `src/lib/proxy/OssifiableProxy.sol` with the source below. This is `lidofinance/community-staking-module`'s `src/lib/proxy/OssifiableProxy.sol` with exactly one modification: the pragma is `0.8.24` instead of `0.8.33`, to match this repo's pinned compiler. Do not make any other change.

```solidity
// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

// Vendored from lidofinance/community-staking-module src/lib/proxy/OssifiableProxy.sol.
// Only modification: pragma relaxed from 0.8.33 to this repo's pinned 0.8.24.
pragma solidity 0.8.24;

import {StorageSlot} from "@openzeppelin/contracts/utils/StorageSlot.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {IERC1967} from "@openzeppelin/contracts/interfaces/IERC1967.sol";

/// @notice An ossifiable proxy contract. Extends the ERC1967Proxy contract by
///     adding admin functionality
contract OssifiableProxy is ERC1967Proxy {
    event ProxyOssified();

    error NotAdmin();
    error ProxyIsOssified();

    /// @dev Validates that proxy is not ossified and that method is called by the admin
    ///     of the proxy
    modifier onlyAdmin() {
        _onlyAdmin();
        _;
    }

    /// @dev Initializes the upgradeable proxy with the initial implementation and admin
    /// @param implementation_ Address of the implementation
    /// @param admin_ Address of the admin of the proxy
    /// @param data_ Data used in a delegate call to implementation. The delegate call will be
    ///     skipped if the data is empty bytes
    constructor(
        address implementation_,
        address admin_,
        bytes memory data_
    ) ERC1967Proxy(implementation_, data_) {
        ERC1967Utils.changeAdmin(admin_);
    }

    /// @notice Fallback function that delegates calls to the address returned by `_implementation()`.
    // Will run if call data is empty.
    // The only use of this function is to suppress the solidity warning "This contract has a payable fallback function, but no receive ether function"
    // See https://forum.openzeppelin.com/t/proxy-sol-fallback/36951/7 for details
    // Previously it was implemented in the Proxy contract, but it was removed in the OZ 5.0
    receive() external payable virtual {
        _fallback();
    }

    /// @notice Allows to transfer admin rights to zero address and prevent future
    ///     upgrades of the proxy
    // solhint-disable-next-line func-name-mixedcase
    function proxy__ossify() external onlyAdmin {
        address prevAdmin = ERC1967Utils.getAdmin();
        StorageSlot.getAddressSlot(ERC1967Utils.ADMIN_SLOT).value = address(0);
        emit IERC1967.AdminChanged(prevAdmin, address(0));
        emit ProxyOssified();
    }

    /// @notice Changes the admin of the proxy
    /// @param newAdmin_ Address of the new admin
    // solhint-disable-next-line func-name-mixedcase
    function proxy__changeAdmin(address newAdmin_) external onlyAdmin {
        ERC1967Utils.changeAdmin(newAdmin_);
    }

    /// @notice Upgrades the implementation of the proxy
    /// @param newImplementation_ Address of the new implementation
    // solhint-disable-next-line func-name-mixedcase
    function proxy__upgradeTo(address newImplementation_) external onlyAdmin {
        ERC1967Utils.upgradeToAndCall(newImplementation_, bytes(""));
    }

    /// @notice Upgrades the proxy to a new implementation, optionally performing an additional
    ///     setup call.
    /// @param newImplementation_ Address of the new implementation
    /// @param setupCalldata_ Data for the setup call. The call is skipped if setupCalldata_ is empty
    // solhint-disable-next-line func-name-mixedcase
    function proxy__upgradeToAndCall(
        address newImplementation_,
        bytes calldata setupCalldata_
    ) external onlyAdmin {
        ERC1967Utils.upgradeToAndCall(newImplementation_, setupCalldata_);
    }

    /// @notice Returns the current admin of the proxy
    // solhint-disable-next-line func-name-mixedcase
    function proxy__getAdmin() external view returns (address) {
        return ERC1967Utils.getAdmin();
    }

    /// @notice Returns the current implementation address
    // solhint-disable-next-line func-name-mixedcase
    function proxy__getImplementation() external view returns (address) {
        return _implementation();
    }

    /// @notice Returns whether the implementation is locked forever
    // solhint-disable-next-line func-name-mixedcase
    function proxy__getIsOssified() external view returns (bool) {
        return ERC1967Utils.getAdmin() == address(0);
    }

    function _onlyAdmin() internal view {
        address admin = ERC1967Utils.getAdmin();
        if (admin == address(0)) revert ProxyIsOssified();
        if (admin != msg.sender) revert NotAdmin();
    }
}
```

- [ ] **Step 7: Run test to verify it passes**

Run: `forge test --match-path test/Proxy.t.sol -vv`

Expected: 3 tests PASS.

- [ ] **Step 8: Commit**

```bash
git add .gitmodules lib/openzeppelin-contracts remappings.txt src/lib/proxy/OssifiableProxy.sol test/mocks/ test/Proxy.t.sol
git commit --no-gpg-sign -m "feat: vendor OssifiableProxy and add proxy smoke tests"
```

---

### Task 2: Prove the cache survives upgrades and admin control holds

**Files:**
- Create: `test/mocks/SMDiscoveryV2Mock.sol`
- Modify: `test/Proxy.t.sol` (append tests to the existing `ProxyTest` contract)

**Interfaces:**
- Consumes: everything Task 1 produced, plus `ProxyTest`'s `setUp()` fields `router`, `module`, `implementation`, `proxy`, `discovery`, and constants `MODULE_ID`, `ADMIN`, `ACCOUNTING`.
- Produces: `SMDiscoveryV2Mock(address stakingRouter)` with `VERSION() returns (uint256)` == 2.

- [ ] **Step 1: Write the failing tests**

Append to `test/Proxy.t.sol`. Also add the import `import {SMDiscoveryV2Mock} from "./mocks/SMDiscoveryV2Mock.sol";` at the top.

```solidity
    function test_upgrade_preservesModuleCache() external {
        discovery.updateModuleCache(MODULE_ID);
        (address moduleBefore, address accountingBefore) = discovery
            .moduleCache(MODULE_ID);

        SMDiscoveryV2Mock v2 = new SMDiscoveryV2Mock(address(router));
        vm.prank(ADMIN);
        proxy.proxy__upgradeTo(address(v2));

        (address moduleAfter, address accountingAfter) = discovery.moduleCache(
            MODULE_ID
        );
        assertEq(moduleAfter, moduleBefore);
        assertEq(accountingAfter, accountingBefore);
        assertEq(proxy.proxy__getImplementation(), address(v2));
        assertEq(SMDiscoveryV2Mock(address(proxy)).VERSION(), 2);
    }

    function test_upgrade_revertsForNonAdmin() external {
        SMDiscoveryV2Mock v2 = new SMDiscoveryV2Mock(address(router));
        vm.prank(address(0xBEEF));
        vm.expectRevert(OssifiableProxy.NotAdmin.selector);
        proxy.proxy__upgradeTo(address(v2));
    }

    function test_ossify_blocksFurtherUpgrades() external {
        vm.prank(ADMIN);
        proxy.proxy__ossify();
        assertTrue(proxy.proxy__getIsOssified());
        assertEq(proxy.proxy__getAdmin(), address(0));

        SMDiscoveryV2Mock v2 = new SMDiscoveryV2Mock(address(router));
        vm.prank(ADMIN);
        vm.expectRevert(OssifiableProxy.ProxyIsOssified.selector);
        proxy.proxy__upgradeTo(address(v2));
    }

    function test_ossify_revertsForNonAdmin() external {
        vm.prank(address(0xBEEF));
        vm.expectRevert(OssifiableProxy.NotAdmin.selector);
        proxy.proxy__ossify();
    }

    function test_ossifiedProxy_stillServesReads() external {
        discovery.updateModuleCache(MODULE_ID);
        vm.prank(ADMIN);
        proxy.proxy__ossify();
        assertEq(address(discovery.STAKING_ROUTER()), address(router));
        (address moduleAddress, ) = discovery.moduleCache(MODULE_ID);
        assertEq(moduleAddress, address(module));
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `forge test --match-path test/Proxy.t.sol -vv`

Expected: compilation failure — `Source "test/mocks/SMDiscoveryV2Mock.sol" not found`.

- [ ] **Step 3: Write the V2 mock**

`test/mocks/SMDiscoveryV2Mock.sol`. Note it appends only a `constant` (no storage), which is the append-only pattern the design requires.

```solidity
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import {SMDiscovery} from "../../src/SMDiscovery.sol";

/// @dev Stand-in for a future SMDiscovery release, used to exercise upgrades.
contract SMDiscoveryV2Mock is SMDiscovery {
    uint256 public constant VERSION = 2;

    constructor(address stakingRouter) SMDiscovery(stakingRouter) {}
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `forge test --match-path test/Proxy.t.sol -vv`

Expected: 8 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add test/mocks/SMDiscoveryV2Mock.sol test/Proxy.t.sol
git commit --no-gpg-sign -m "test: cover cache preservation, admin control and ossification"
```

---

### Task 3: Guard against selector shadowing and verify queue detection through the proxy

**Files:**
- Create: `test/SelectorCollision.t.sol`
- Modify: `test/QueueDetection.t.sol`

**Interfaces:**
- Consumes: `OssifiableProxy`, `SMDiscovery`, existing `QueueDetection.t.sol` constants.
- Produces: nothing consumed by later tasks.

**Why this task exists:** `OssifiableProxy` is non-transparent, so its own functions are dispatched ahead of the fallback and permanently shadow any implementation function with a matching selector — silently, not by reverting. The collision test reads both contracts' `methodIdentifiers` from the build artifacts, so it covers every method still queued in `TODO.md` without needing maintenance.

- [ ] **Step 1: Write the failing collision test**

`test/SelectorCollision.t.sol`:

```solidity
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";

/// @dev OssifiableProxy is non-transparent: its own selectors are matched before the
///      fallback, so a colliding implementation function would be silently unreachable.
contract SelectorCollisionTest is Test {
    function test_noProxySelectorShadowsImplementation() external {
        string[] memory implSigs = _signatures(
            "out/SMDiscovery.sol/SMDiscovery.json"
        );
        string[] memory proxySigs = _signatures(
            "out/OssifiableProxy.sol/OssifiableProxy.json"
        );

        assertGt(implSigs.length, 0, "no implementation methods found");
        assertGt(proxySigs.length, 0, "no proxy methods found");

        for (uint256 i = 0; i < implSigs.length; i++) {
            bytes4 implSelector = bytes4(keccak256(bytes(implSigs[i])));
            for (uint256 j = 0; j < proxySigs.length; j++) {
                bytes4 proxySelector = bytes4(keccak256(bytes(proxySigs[j])));
                assertTrue(
                    implSelector != proxySelector,
                    string.concat(
                        "selector collision: ",
                        implSigs[i],
                        " vs ",
                        proxySigs[j]
                    )
                );
            }
        }
    }

    function _signatures(
        string memory artifactPath
    ) internal view returns (string[] memory) {
        string memory json = vm.readFile(artifactPath);
        return vm.parseJsonKeys(json, ".methodIdentifiers");
    }
}
```

- [ ] **Step 2: Run it and confirm it passes on current code**

Run: `forge build && forge test --match-path test/SelectorCollision.t.sol -vv`

Expected: PASS. This test guards an invariant that already holds, so a green run is the correct first result. `forge build` must precede it because it reads `out/`; `fs_permissions` in `foundry.toml` already grants read access to `./out`.

- [ ] **Step 3: Prove the test can actually fail**

Temporarily add this function to `test/mocks/SMDiscoveryV2Mock.sol`:

```solidity
    function proxy__getAdmin() external pure returns (address) {
        return address(0);
    }
```

Then change `_signatures("out/SMDiscovery.sol/SMDiscovery.json")` to `_signatures("out/SMDiscoveryV2Mock.sol/SMDiscoveryV2Mock.json")` and run `forge build && forge test --match-path test/SelectorCollision.t.sol`.

Expected: FAIL with `selector collision: proxy__getAdmin() vs proxy__getAdmin()`.

**Then revert both temporary edits** and re-run to confirm PASS. This step exists because a test that has never failed is not yet known to work.

- [ ] **Step 4: Parameterise QueueDetection over direct and proxied instances**

Rewrite `test/QueueDetection.t.sol` as follows. The behavioural assertions are unchanged; they now run against both instances. This matters because `_tryGetMaxQueuePriority` performs a `this.`-prefixed external self-call, which behind a proxy re-enters the proxy and delegatecalls back.

```solidity
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import "../src/SMDiscovery.sol";
import {Batch} from "../src/interfaces/IBatch.sol";
import {OssifiableProxy} from "../src/lib/proxy/OssifiableProxy.sol";

/// @dev Regression test for the CSM queue-detection probe (see _tryGetMaxQueuePriority).
///      Runs against a pinned Hoodi fork; skipped when RPC_URL is unset or points elsewhere.
///      Each case runs against both a direct and a proxied instance.
contract QueueDetectionTest is Test {
    uint256 internal constant HOODI_CHAIN_ID = 560048;
    uint256 internal constant HOODI_FORK_BLOCK = 3495000;
    address internal constant STAKING_ROUTER =
        0xCc820558B39ee15C7C45B59390B503b83fb499A8;
    uint256 internal constant CSM_MODULE_ID = 4;
    uint256 internal constant CMV2_MODULE_ID = 5;
    address internal constant CMV2_ADDRESS =
        0x87EB69Ae51317405FD285efD2326a4a11f6173b9;
    address internal constant PROXY_ADMIN = address(0xA11CE);

    SMDiscovery[] internal instances;

    function setUp() external {
        string memory rpcUrl = vm.envOr("RPC_URL", string(""));
        if (bytes(rpcUrl).length == 0) {
            vm.skip(true);
            return;
        }

        vm.createSelectFork(rpcUrl, HOODI_FORK_BLOCK);
        if (block.chainid != HOODI_CHAIN_ID) {
            vm.skip(true);
            return;
        }

        SMDiscovery implementation = new SMDiscovery(STAKING_ROUTER);
        OssifiableProxy proxy = new OssifiableProxy(
            address(implementation),
            PROXY_ADMIN,
            ""
        );

        instances.push(new SMDiscovery(STAKING_ROUTER));
        instances.push(SMDiscovery(address(proxy)));

        for (uint256 i = 0; i < instances.length; i++) {
            instances[i].updateModuleCache(CSM_MODULE_ID);
            instances[i].updateModuleCache(CMV2_MODULE_ID);
        }
    }

    function test_csmQueueBatches_returnsNonEmpty() external view {
        for (uint256 i = 0; i < instances.length; i++) {
            Batch[] memory batches = instances[i].getDepositQueueBatches(
                CSM_MODULE_ID,
                5,
                0,
                10
            );
            assertGt(batches.length, 0);
        }
    }

    function test_csmQueueBatches_revertsOnPriorityAboveRegistryBound()
        external
    {
        for (uint256 i = 0; i < instances.length; i++) {
            vm.expectRevert(
                abi.encodeWithSelector(InvalidQueuePriority.selector, 6, 5)
            );
            instances[i].getDepositQueueBatches(CSM_MODULE_ID, 6, 0, 10);
        }
    }

    function test_cmv2QueueBatches_revertsAsUnsupported() external {
        for (uint256 i = 0; i < instances.length; i++) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    ModuleDoesNotSupportQueueOperations.selector,
                    CMV2_ADDRESS
                )
            );
            instances[i].getDepositQueueBatches(CMV2_MODULE_ID, 0, 0, 10);
        }
    }
}
```

- [ ] **Step 5: Run the fork tests**

Run: `RPC_URL=<hoodi rpc> forge test --match-path test/QueueDetection.t.sol -vv`

Expected: 3 tests PASS, each exercising both instances. If `RPC_URL` is unavailable, run `forge test --match-path test/QueueDetection.t.sol` and confirm the tests SKIP rather than fail, then report that the fork run could not be performed.

- [ ] **Step 6: Run the whole suite**

Run: `forge test -vv`

Expected: all tests pass or skip; no failures.

- [ ] **Step 7: Commit**

```bash
git add test/SelectorCollision.t.sol test/QueueDetection.t.sol
git commit --no-gpg-sign -m "test: guard selector shadowing, run queue detection through proxy"
```

---

### Task 4: Make deployment proxy-aware

**Files:**
- Modify: `script/DeployBase.s.sol`
- Test: `test/DeployScript.t.sol` (create)

**Interfaces:**
- Consumes: `OssifiableProxy` constructor from Task 1; existing `DeployHoodi` / `DeployMainnet` subclasses, which are NOT modified.
- Produces: `DeployBase.implementation` (`SMDiscovery`), `DeployBase.proxy` (`OssifiableProxy`), `DeployBase.discovery` (`SMDiscovery`, the proxy cast to the implementation ABI), and `error ProxyAdminNotSet()`. Task 5 mirrors this structure.

- [ ] **Step 1: Write the failing test**

`test/DeployScript.t.sol`:

```solidity
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {DeployHoodi} from "../script/DeployHoodi.s.sol";
import {DeployBase} from "../script/DeployBase.s.sol";
import {SMDiscovery} from "../src/SMDiscovery.sol";

contract DeployScriptTest is Test {
    uint256 internal constant HOODI_CHAIN_ID = 560048;
    uint256 internal constant HOODI_FORK_BLOCK = 3495000;
    uint256 internal constant CSM_MODULE_ID = 4;
    address internal constant PROXY_ADMIN = address(0xA11CE);

    function setUp() external {
        string memory rpcUrl = vm.envOr("RPC_URL", string(""));
        if (bytes(rpcUrl).length == 0) {
            vm.skip(true);
            return;
        }
        vm.createSelectFork(rpcUrl, HOODI_FORK_BLOCK);
        if (block.chainid != HOODI_CHAIN_ID) {
            vm.skip(true);
            return;
        }
    }

    function test_deploy_putsDiscoveryBehindProxyAndSeedsCache() external {
        vm.setEnv("PROXY_ADMIN", vm.toString(PROXY_ADMIN));

        DeployHoodi script = new DeployHoodi();
        script.run();

        assertEq(script.proxy().proxy__getAdmin(), PROXY_ADMIN);
        assertEq(
            script.proxy().proxy__getImplementation(),
            address(script.implementation())
        );
        assertEq(address(script.discovery()), address(script.proxy()));

        (address moduleAddress, ) = script.discovery().moduleCache(
            CSM_MODULE_ID
        );
        assertTrue(moduleAddress != address(0), "cache not seeded");
    }

    function test_deploy_revertsWhenProxyAdminUnset() external {
        vm.setEnv("PROXY_ADMIN", vm.toString(address(0)));

        DeployHoodi script = new DeployHoodi();
        vm.expectRevert(DeployBase.ProxyAdminNotSet.selector);
        script.run();
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `RPC_URL=<hoodi rpc> forge test --match-path test/DeployScript.t.sol -vv`

Expected: compilation failure — `DeployBase.ProxyAdminNotSet` and members `proxy`, `implementation`, `discovery` are not defined.

- [ ] **Step 3: Rewrite DeployBase**

Replace the whole body of `script/DeployBase.s.sol` with:

```solidity
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import "../src/SMDiscovery.sol";
import {OssifiableProxy} from "../src/lib/proxy/OssifiableProxy.sol";
import "../src/interfaces/IStakingRouter.sol";

struct DeployParams {
    address stakingRouterAddress;
    uint256[] moduleIds;
}

contract DeployBase is Script {
    DeployParams internal config;
    string internal chainName;
    uint256 internal chainId;

    SMDiscovery public implementation;
    OssifiableProxy public proxy;
    /// @notice The proxy, typed with the implementation ABI
    SMDiscovery public discovery;

    error ChainIdMismatch(uint256 actual, uint256 expected);
    error ProxyAdminNotSet();

    constructor(string memory _chainName, uint256 _chainId) {
        chainName = _chainName;
        chainId = _chainId;
    }

    function run() external virtual {
        if (chainId != block.chainid) {
            revert ChainIdMismatch({actual: block.chainid, expected: chainId});
        }

        address proxyAdmin = vm.envOr("PROXY_ADMIN", address(0));
        if (proxyAdmin == address(0)) revert ProxyAdminNotSet();

        vm.startBroadcast();

        implementation = new SMDiscovery(config.stakingRouterAddress);
        proxy = new OssifiableProxy(address(implementation), proxyAdmin, "");
        discovery = SMDiscovery(address(proxy));

        for (uint256 i = 0; i < config.moduleIds.length; i++) {
            uint256 moduleId = config.moduleIds[i];
            try discovery.updateModuleCache(moduleId) {
                console.log("Initialized cache for moduleId=%d", moduleId);
            } catch {
                console.log(
                    "Warning: Could not initialize cache for moduleId=%d (not registered yet)",
                    moduleId
                );
            }
        }
        vm.stopBroadcast();

        console.log("========================================");
        console.log("SMDiscovery proxy deployed at:", address(proxy));
        console.log("SMDiscovery implementation:", address(implementation));
        console.log("Proxy admin:", proxyAdmin);
        console.log("StakingRouter:", config.stakingRouterAddress);
        console.log("Chain:", chainName);
        console.log("ChainId:", chainId);
        console.log("========================================");
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `RPC_URL=<hoodi rpc> forge test --match-path test/DeployScript.t.sol -vv`

Expected: 2 tests PASS.

If `vm.startBroadcast` inside `forge test` causes an error on the installed Foundry version, report it rather than working around it — the fallback is to validate the script with `CHAIN=hoodi just deploy-live-dry` instead, and that decision is the user's.

- [ ] **Step 5: Dry-run the real script**

Run: `CHAIN=hoodi PROXY_ADMIN=0x000000000000000000000000000000000000dEaD just deploy-live-dry`

Expected: simulation succeeds and logs both the proxy and implementation addresses.

- [ ] **Step 6: Commit**

```bash
git add script/DeployBase.s.sol test/DeployScript.t.sol
git commit --no-gpg-sign -m "feat: deploy SMDiscovery behind OssifiableProxy"
```

---

### Task 5: Add the upgrade path

**Files:**
- Create: `script/UpgradeBase.s.sol`
- Create: `script/UpgradeHoodi.s.sol`
- Create: `script/UpgradeMainnet.s.sol`
- Modify: `justfile`
- Test: `test/UpgradeScript.t.sol` (create)

**Interfaces:**
- Consumes: `OssifiableProxy` (Task 1), `SMDiscovery`.
- Produces: `UpgradeBase.implementation` (`SMDiscovery`), `error ProxyAddressNotSet()`, and the `upgrade-live` / `upgrade-live-dry` / `upgrade-live-no-confirm` Just recipes.

The proxy address is read from `PROXY_ADDRESS` rather than hardcoded, matching the environment-variable approach chosen for `PROXY_ADMIN`. This also means the scripts are complete before the first deployment exists.

- [ ] **Step 1: Write the failing test**

`test/UpgradeScript.t.sol`:

```solidity
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {UpgradeHoodi} from "../script/UpgradeHoodi.s.sol";
import {UpgradeBase} from "../script/UpgradeBase.s.sol";
import {SMDiscovery} from "../src/SMDiscovery.sol";
import {OssifiableProxy} from "../src/lib/proxy/OssifiableProxy.sol";
import {StakingRouterMock} from "./mocks/StakingRouterMock.sol";

contract UpgradeScriptTest is Test {
    uint256 internal constant HOODI_CHAIN_ID = 560048;
    address internal constant STAKING_ROUTER =
        0xCc820558B39ee15C7C45B59390B503b83fb499A8;

    OssifiableProxy internal proxy;
    address internal firstImplementation;

    function setUp() external {
        vm.chainId(HOODI_CHAIN_ID);
        vm.etch(STAKING_ROUTER, address(new StakingRouterMock()).code);

        firstImplementation = address(new SMDiscovery(STAKING_ROUTER));
        proxy = new OssifiableProxy(
            firstImplementation,
            address(this),
            ""
        );
    }

    /// @dev All three cases share one test function on purpose: `vm.setEnv` mutates
    ///      process-global state and forge runs tests in parallel, so exactly one test
    ///      function may own `PROXY_ADDRESS`. Splitting these reintroduces a real race.
    function test_upgrade_adminUpgradesNonAdminDefersUnsetReverts() external {
        vm.setEnv("PROXY_ADDRESS", vm.toString(address(proxy)));

        // 1. The test contract is both the proxy admin and run()'s caller, so
        //    UpgradeBase's `broadcaster == admin` branch runs and the upgrade lands.
        UpgradeHoodi adminRun = new UpgradeHoodi();
        adminRun.run();

        address upgraded = address(adminRun.implementation());
        assertEq(proxy.proxy__getImplementation(), upgraded);
        assertTrue(upgraded != firstImplementation, "implementation unchanged");

        // 2. Under a different admin the script still deploys an implementation,
        //    but must leave the proxy pointing where it was.
        proxy.proxy__changeAdmin(address(0xBEEF));

        UpgradeHoodi nonAdminRun = new UpgradeHoodi();
        nonAdminRun.run();

        assertEq(proxy.proxy__getImplementation(), upgraded);
        assertTrue(
            address(nonAdminRun.implementation()) != upgraded,
            "expected a freshly deployed implementation"
        );

        // 3. An unset PROXY_ADDRESS must revert before anything is broadcast.
        vm.setEnv("PROXY_ADDRESS", vm.toString(address(0)));

        UpgradeHoodi unsetRun = new UpgradeHoodi();
        vm.expectRevert(UpgradeBase.ProxyAddressNotSet.selector);
        unsetRun.run();
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `forge test --match-path test/UpgradeScript.t.sol -vv`

Expected: compilation failure — `script/UpgradeHoodi.s.sol` not found.

- [ ] **Step 3: Write the upgrade scripts**

`script/UpgradeBase.s.sol`:

```solidity
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import "../src/SMDiscovery.sol";
import {OssifiableProxy} from "../src/lib/proxy/OssifiableProxy.sol";

contract UpgradeBase is Script {
    string internal chainName;
    uint256 internal chainId;
    address internal stakingRouterAddress;

    SMDiscovery public implementation;

    error ChainIdMismatch(uint256 actual, uint256 expected);
    error ProxyAddressNotSet();

    constructor(
        string memory _chainName,
        uint256 _chainId,
        address _stakingRouterAddress
    ) {
        chainName = _chainName;
        chainId = _chainId;
        stakingRouterAddress = _stakingRouterAddress;
    }

    function run() external virtual {
        if (chainId != block.chainid) {
            revert ChainIdMismatch({actual: block.chainid, expected: chainId});
        }

        address proxyAddress = vm.envOr("PROXY_ADDRESS", address(0));
        if (proxyAddress == address(0)) revert ProxyAddressNotSet();

        OssifiableProxy proxy = OssifiableProxy(payable(proxyAddress));
        address admin = proxy.proxy__getAdmin();

        // Broadcast explicitly as run()'s caller, so the identity compared against
        // `admin` is the same identity that ends up signing proxy__upgradeTo. A bare
        // vm.startBroadcast() uses the default sender, which diverges from msg.sender
        // under `forge test` and would make the admin branch untestable.
        address broadcaster = msg.sender;

        vm.startBroadcast(broadcaster);
        implementation = new SMDiscovery(stakingRouterAddress);

        if (broadcaster == admin) {
            proxy.proxy__upgradeTo(address(implementation));
            console.log("Upgraded proxy:", proxyAddress);
            console.log("New implementation:", address(implementation));
        } else {
            console.log("Broadcaster is not the proxy admin, not upgrading.");
            console.log("Proxy admin:", admin);
            console.log("Broadcaster:", broadcaster);
            console.log("New implementation:", address(implementation));
            console.log("Submit this transaction from the admin:");
            console.log("  to:", proxyAddress);
            console.log("  data:");
            console.logBytes(
                abi.encodeCall(
                    OssifiableProxy.proxy__upgradeTo,
                    (address(implementation))
                )
            );
        }
        vm.stopBroadcast();

        console.log("Chain:", chainName);
    }
}
```

`script/UpgradeHoodi.s.sol`:

```solidity
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import {UpgradeBase} from "./UpgradeBase.s.sol";

contract UpgradeHoodi is UpgradeBase {
    constructor()
        UpgradeBase(
            "hoodi",
            560048,
            0xCc820558B39ee15C7C45B59390B503b83fb499A8
        )
    {}
}
```

`script/UpgradeMainnet.s.sol`:

```solidity
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import {UpgradeBase} from "./UpgradeBase.s.sol";

contract UpgradeMainnet is UpgradeBase {
    constructor()
        UpgradeBase("mainnet", 1, 0xFdDf38947aFB03C621C71b06C9C70bce73f12999)
    {}
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `forge test --match-path test/UpgradeScript.t.sol -vv`

Expected: 1 test PASS.

Then run a bare `forge test` (no `--threads` flag) at least 5 consecutive times and confirm the same pass count every time. The suite writes process-global env vars, so repetition is the acceptance criterion, not a single green run.

- [ ] **Step 5: Add the Just recipes**

In `justfile`, after the `deploy_script_path` definition, add:

```just
upgrade_script_name := if chain == "mainnet" {
    "UpgradeMainnet"
} else if chain == "hoodi" {
    "UpgradeHoodi"
} else {
    error("Unsupported chain " + chain)
}

upgrade_script_path := "script" / upgrade_script_name + ".s.sol:" + upgrade_script_name
```

Then, after the `verify-live` recipe, add:

```just
upgrade-live *args:
    just _warn "The current `tput bold`chain={{chain}}`tput sgr0` with the following rpc url: $RPC_URL"
    ARTIFACTS_DIR=./artifacts/latest/ just _upgrade-live {{args}}

    mkdir -p ./artifacts/latest/
    cp ./broadcast/{{upgrade_script_name}}.s.sol/`cast chain-id --rpc-url=$RPC_URL`/run-latest.json \
        ./artifacts/latest/transactions.json

upgrade-live-no-confirm *args:
    just _warn "The current `tput bold`chain={{chain}}`tput sgr0` with the following rpc url: $RPC_URL"
    ARTIFACTS_DIR=./artifacts/latest/ just _upgrade-live-no-confirm --broadcast {{args}}

    mkdir -p ./artifacts/latest/
    cp ./broadcast/{{upgrade_script_name}}.s.sol/`cast chain-id --rpc-url=$RPC_URL`/run-latest.json \
        ./artifacts/latest/transactions.json

[confirm("You are about to broadcast upgrade transactions to the network. Are you sure?")]
_upgrade-live *args:
    just _upgrade-live-no-confirm --broadcast --verify {{args}}

upgrade-live-dry *args:
    just _upgrade-live-no-confirm {{args}}

_upgrade-live-no-confirm *args:
    forge script {{upgrade_script_path}} --force --rpc-url ${RPC_URL} {{args}}
```

- [ ] **Step 6: Verify the recipes resolve**

Run: `just --list`

Expected: `upgrade-live`, `upgrade-live-dry` and `upgrade-live-no-confirm` are listed. Then run `CHAIN=hoodi just --evaluate upgrade_script_path` and confirm it prints `script/UpgradeHoodi.s.sol:UpgradeHoodi`.

- [ ] **Step 7: Run the whole suite**

Run: `forge test -vv`

Expected: all tests pass or skip; no failures.

- [ ] **Step 8: Commit**

```bash
git add script/UpgradeBase.s.sol script/UpgradeHoodi.s.sol script/UpgradeMainnet.s.sol justfile test/UpgradeScript.t.sol
git commit --no-gpg-sign -m "feat: add proxy upgrade scripts and just recipes"
```

---

### Task 6: Update documentation and the cache script

**Files:**
- Modify: `script/update-module-cache.sh`
- Modify: `CLAUDE.md`
- Modify: `README.md`
- Modify: `docs/proxy-design.md`

**Interfaces:**
- Consumes: everything above. Produces nothing consumed by later tasks.

Note `CLAUDE.md` and `README.md` already have uncommitted modifications in the working tree from unrelated in-flight work. Stage only the lines this task changes; do not stage unrelated hunks.

- [ ] **Step 1: Let update-module-cache.sh target the proxy**

In `script/update-module-cache.sh`, replace the chain-id case block:

```bash
CHAIN_ID=$(cast chain-id --rpc-url "$RPC_URL")
case "$CHAIN_ID" in
  1)      DISCOVERY=0x6a9c16626D64dFe7A185eb6378F8eB901f96281C ;;
  560048) DISCOVERY=0xb3dFdcE02a83454F38Fd127E6261F7AdcDA86B47 ;;
  *) echo "unknown chain id $CHAIN_ID" >&2; exit 1 ;;
esac
```

with:

```bash
CHAIN_ID=$(cast chain-id --rpc-url "$RPC_URL")
# DISCOVERY may be set in the environment to override the defaults below.
# The per-chain values are the SMDiscovery *proxy* addresses; they change only
# on migration to the proxy, never on a routine release.
if [ -z "${DISCOVERY:-}" ]; then
  case "$CHAIN_ID" in
    1)      DISCOVERY=0x6a9c16626D64dFe7A185eb6378F8eB901f96281C ;;
    560048) DISCOVERY=0xb3dFdcE02a83454F38Fd127E6261F7AdcDA86B47 ;;
    *) echo "unknown chain id $CHAIN_ID (set DISCOVERY to override)" >&2; exit 1 ;;
  esac
fi
```

The addresses stay at their current values here. They are updated to the proxy addresses during the deployment step, which is outside this plan.

- [ ] **Step 2: Verify the script still runs**

Run: `RPC_URL=<hoodi rpc> script/update-module-cache.sh 4`

Expected: prints `chain=560048 discovery=0x... router=0x...` and then either `already cached, nothing to do` or attempts the `cast send`. Also confirm the override path: `DISCOVERY=0x000000000000000000000000000000000000dEaD RPC_URL=<hoodi rpc> script/update-module-cache.sh 4` prints the overridden address.

- [ ] **Step 3: Update the CLAUDE.md deployed-contracts table**

Replace the "Deployed Contracts" table with:

```markdown
| Chain          | StakingRouter                                | SMDiscovery (proxy)                          | Implementation |
|----------------|----------------------------------------------|----------------------------------------------|----------------|
| Mainnet (1)    | `0xFdDf38947aFB03C621C71b06C9C70bce73f12999` | pending proxy migration                      | pending        |
| Hoodi (560048) | `0xCc820558B39ee15C7C45B59390B503b83fb499A8` | pending proxy migration                      | pending        |

Pre-proxy deployments, deprecated once the proxies are live and kept only for reference:
mainnet `0x6a9c16626D64dFe7A185eb6378F8eB901f96281C`,
hoodi `0xb3dFdcE02a83454F38Fd127E6261F7AdcDA86B47`.
```

- [ ] **Step 4: Document the proxy in CLAUDE.md**

Under "Key Technical Details", add this subsection after "Cache Management Pattern":

```markdown
### Proxy Pattern

`SMDiscovery` sits behind Lido's `OssifiableProxy` (`src/lib/proxy/OssifiableProxy.sol`,
vendored from CSM with the pragma relaxed to 0.8.24). The address is stable across releases.

- `SMDiscovery` has no initializer: `STAKING_ROUTER` is `immutable` and lives in the
  implementation bytecode; `moduleCache` is filled by the permissionless `updateModuleCache()`.
- `moduleCache` occupies storage slot 0. New state variables may only be appended.
- Releasing a new implementation: `CHAIN=<chain> PROXY_ADDRESS=<proxy> just upgrade-live`.
  If the broadcaster is the proxy admin the upgrade is sent directly; otherwise the script
  logs the `proxy__upgradeTo` calldata for the admin multisig to submit.
- `proxy__ossify()` freezes the implementation permanently once the ABI settles.

Environment variables: `PROXY_ADMIN` (required by deploy scripts), `PROXY_ADDRESS`
(required by upgrade scripts).
```

- [ ] **Step 5: Update the Testing section of CLAUDE.md**

Replace `**Current Status**: No custom tests implemented` with:

```markdown
**Current Status**: Proxy mechanics covered by local-mock tests; queue detection covered by
a Hoodi fork test that skips when `RPC_URL` is unset.

| File | Covers |
|------|--------|
| `test/Proxy.t.sol` | immutables through delegatecall, cache preservation across upgrade, admin control, ossification |
| `test/SelectorCollision.t.sol` | no proxy selector shadows an implementation method |
| `test/QueueDetection.t.sol` | CSM queue detection, direct and proxied (fork) |
| `test/DeployScript.t.sol` | deploy script wires proxy and seeds cache (fork) |
| `test/UpgradeScript.t.sol` | upgrade script admin/non-admin branches |
```

- [ ] **Step 6: Update README.md**

Under `## Contract Addresses`, replace the table with:

```markdown
| Chain          | StakingRouter                                | SMDiscovery (proxy)     | Implementation |
|----------------|----------------------------------------------|-------------------------|----------------|
| Mainnet (1)    | `0xFdDf38947aFB03C621C71b06C9C70bce73f12999` | pending proxy migration | pending        |
| Hoodi (560048) | `0xCc820558B39ee15C7C45B59390B503b83fb499A8` | pending proxy migration | pending        |

Pre-proxy deployments, deprecated once the proxies are live and kept only for reference:
mainnet `0x6a9c16626D64dFe7A185eb6378F8eB901f96281C`,
hoodi `0xb3dFdcE02a83454F38Fd127E6261F7AdcDA86B47`.
```

Under `### Environment Variables`, append two bullets to the existing list:

```markdown
- `PROXY_ADMIN`: Admin address for the OssifiableProxy - required by `just deploy-live`
- `PROXY_ADDRESS`: Existing proxy to upgrade - required by `just upgrade-live`
```

After the `### Live Network` block and before `### Environment Variables`, insert
(outer fence shown as `~~~` only to keep this plan readable; use ``` in the README):

~~~markdown
### Upgrading

`SMDiscovery` sits behind an `OssifiableProxy`, so a new release replaces the
implementation and leaves the address alone.

```bash
# Dry run (recommended first)
CHAIN=mainnet PROXY_ADDRESS=<proxy> just upgrade-live-dry

# Deploy the new implementation and upgrade
CHAIN=mainnet RPC_URL=<your-rpc> PROXY_ADDRESS=<proxy> just upgrade-live
```

If the broadcaster is the proxy admin, the upgrade is sent directly. Otherwise the
script deploys the implementation and logs the `proxy__upgradeTo` calldata for the
admin multisig to submit.
~~~

In `## Why SMDiscovery?`, change the `**Stateless & Simple**` bullet to read
`**Simple**: No ownership, view-only functions, explicit cache management` — the
contract is no longer stateless-by-redeploy now that the cache persists across upgrades.

Leave `## Testing` and `## License` alone; Task 6 does not touch them.

- [ ] **Step 7: Correct the design doc**

In `docs/proxy-design.md`, under "Components", replace:

```
src/lib/proxy/OssifiableProxy.sol  vendored verbatim from lidofinance/community-staking-module
```

with:

```
src/lib/proxy/OssifiableProxy.sol  vendored from lidofinance/community-staking-module;
                                   sole modification is the pragma, 0.8.33 -> 0.8.24
```

And append this to the same section:

```markdown
The upstream file is GPL-3.0. This repository is already GPL-3.0 (`LICENSE`, and
`src/interfaces/IStakingRouter.sol` carries the same header), so vendoring raises no
licensing question. OpenZeppelin is pinned at `v5.4.0`, whose strictest pragma is `^0.8.22`.
```

Also update the "Deploy and upgrade scripts" section: the proxy address is read from
`PROXY_ADDRESS` rather than hardcoded per chain.

- [ ] **Step 8: Run the full suite one more time**

Run: `forge build && forge test -vv`

Expected: all tests pass or skip; no failures.

- [ ] **Step 9: Commit**

```bash
git add script/update-module-cache.sh docs/proxy-design.md
git add -p CLAUDE.md README.md   # stage only this task's hunks
git commit --no-gpg-sign -m "docs: document the proxy pattern and upgrade flow"
```

---

## After the plan

The remaining work is operational and deliberately outside this plan:

1. Deploy to hoodi with `PROXY_ADMIN` set, using the repo's `deploy` skill.
2. Verify implementation and proxy on both Etherscan V2 and Blockscout.
3. Repeat on mainnet with the multisig as `PROXY_ADMIN`.
4. Fill the real addresses into `CLAUDE.md`, `README.md`, `script/update-module-cache.sh` and `artifacts/{chain}/`.
5. Point the frontend/SDK config at the proxy addresses.
