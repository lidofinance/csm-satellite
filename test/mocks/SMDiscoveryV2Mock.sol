// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import {SMDiscovery} from "../../src/SMDiscovery.sol";

/// @dev Stand-in for a future SMDiscovery release, used to exercise upgrades.
contract SMDiscoveryV2Mock is SMDiscovery {
    uint256 public constant VERSION = 2;

    constructor(address stakingRouter) SMDiscovery(stakingRouter) {}
}
