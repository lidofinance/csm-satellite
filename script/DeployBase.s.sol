// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import "../src/SMDiscovery.sol";
import "../src/interfaces/IStakingRouter.sol";

struct DeployParams {
    address stakingRouterAddress;
    uint256[] moduleIds;
}

contract DeployBase is Script {
    DeployParams internal config;
    string internal chainName;
    uint256 internal chainId;

    error ChainIdMismatch(uint256 actual, uint256 expected);

    constructor(string memory _chainName, uint256 _chainId) {
        chainName = _chainName;
        chainId = _chainId;
    }

    function run() external virtual {
        if (chainId != block.chainid) {
            revert ChainIdMismatch({actual: block.chainid, expected: chainId});
        }

        vm.startBroadcast();

        // Deploy SMDiscovery (permissionless - no owner)
        SMDiscovery discovery = new SMDiscovery(config.stakingRouterAddress);

        // Initialize module cache for each configured module
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

        // Log deployment info
        console.log("========================================");
        console.log("SMDiscovery deployed at:", address(discovery));
        console.log("StakingRouter:", config.stakingRouterAddress);
        console.log("Chain:", chainName);
        console.log("ChainId:", chainId);
        console.log("========================================");
    }
}
