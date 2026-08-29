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
