// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import "../src/SMDiscovery.sol";
import {OssifiableProxy} from "../src/lib/proxy/OssifiableProxy.sol";

contract UpgradeBase is Script {
    string internal chainName;
    uint256 internal chainId;

    SMDiscovery public implementation;

    error ChainIdMismatch(uint256 actual, uint256 expected);
    error ProxyAddressNotSet();
    error ProxyIsOssified();

    constructor(string memory _chainName, uint256 _chainId) {
        chainName = _chainName;
        chainId = _chainId;
    }

    function run() external virtual {
        if (chainId != block.chainid) {
            revert ChainIdMismatch({actual: block.chainid, expected: chainId});
        }

        address proxyAddress = vm.envOr("PROXY_ADDRESS", address(0));
        if (proxyAddress == address(0)) revert ProxyAddressNotSet();

        OssifiableProxy proxy = OssifiableProxy(payable(proxyAddress));
        if (proxy.proxy__getIsOssified()) revert ProxyIsOssified();

        address admin = proxy.proxy__getAdmin();
        address routerAddress = address(
            SMDiscovery(proxyAddress).STAKING_ROUTER()
        );

        // Broadcast explicitly as run()'s caller, so the identity compared against
        // `admin` is the same identity that ends up signing proxy__upgradeTo. A bare
        // vm.startBroadcast() uses the default sender, which diverges from msg.sender
        // under `forge test` and would make the admin branch untestable.
        address broadcaster = msg.sender;

        vm.startBroadcast(broadcaster);
        implementation = new SMDiscovery(routerAddress);

        if (broadcaster == admin) {
            proxy.proxy__upgradeTo(address(implementation));
            console.log("Upgraded proxy:", proxyAddress);
            console.log("New implementation:", address(implementation));
        } else {
            console.log("Broadcaster is not the proxy admin, not upgrading.");
            console.log("Proxy admin:", admin);
            console.log("Broadcaster:", broadcaster);
            console.log("New implementation:", address(implementation));
            console.log(
                "For a dry run that exercises the upgrade path, pass --sender <admin> explicitly."
            );
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
        console.log("StakingRouter:", routerAddress);
    }
}
