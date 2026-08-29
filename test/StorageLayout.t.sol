// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";

/// @dev Slot-0 stability is the invariant the whole proxy design rests on and has no
///      machine check otherwise — only the prose in docs/proxy-design.md. Reads the
///      build artifact's storageLayout (foundry.toml: extra_output = ["storageLayout"]).
contract StorageLayoutTest is Test {
    function test_moduleCacheIsTheOnlyStorageVariableAtSlotZero() external {
        string memory json = vm.readFile("out/SMDiscovery.sol/SMDiscovery.json");

        string[] memory topLevelKeys = vm.parseJsonKeys(json, "$");
        bool hasStorageLayout = false;
        for (uint256 i = 0; i < topLevelKeys.length; i++) {
            if (
                keccak256(bytes(topLevelKeys[i])) ==
                keccak256(bytes("storageLayout"))
            ) {
                hasStorageLayout = true;
                break;
            }
        }
        assertTrue(
            hasStorageLayout,
            "artifact missing storageLayout key; check extra_output in foundry.toml"
        );

        // A raw call lets us treat "index out of bounds" as a signal instead of a revert.
        (bool secondEntryExists, ) = address(vm).call(
            abi.encodeWithSelector(
                vm.parseJsonString.selector,
                json,
                ".storageLayout.storage[1].label"
            )
        );
        assertFalse(secondEntryExists, "expected exactly one storage variable");

        string memory label = vm.parseJsonString(
            json,
            ".storageLayout.storage[0].label"
        );
        assertEq(label, "moduleCache");

        uint256 slot = vm.parseJsonUint(json, ".storageLayout.storage[0].slot");
        assertEq(slot, 0);

        uint256 offset = vm.parseJsonUint(
            json,
            ".storageLayout.storage[0].offset"
        );
        assertEq(offset, 0);
    }
}
