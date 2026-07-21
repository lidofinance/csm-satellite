// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {DeployBase} from "./DeployBase.s.sol";

contract DeployMainnet is DeployBase {
    constructor() DeployBase("mainnet", 1) {
        config.stakingRouterAddress = 0xFdDf38947aFB03C621C71b06C9C70bce73f12999;
        config.moduleIds.push(3); // CSM
        // config.moduleIds.push(4); // CM
    }
}
