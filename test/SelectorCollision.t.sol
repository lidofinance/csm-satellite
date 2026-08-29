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
