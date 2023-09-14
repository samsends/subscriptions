// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import {Subscription} from "../src/Subscription.sol";

contract SubscriptionTest is Test {
    Subscription public subscription;

    function setUp() public {
        subscription = new Subscription();
    }
}
