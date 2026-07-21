// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {DeployBase} from "./DeployBase.s.sol";

contract DeployHoodi is DeployBase {
    constructor() DeployBase("hoodi", 560048) {
        config
            .stakingRouterAddress = 0xCc820558B39ee15C7C45B59390B503b83fb499A8;
        config.moduleIds.push(4); // CSM
        config.moduleIds.push(5); // CM
    }
}
