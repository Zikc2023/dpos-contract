// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { TConsensus } from "@ronin/contracts/udvts/Types.sol";
import "./20231003_REP002AndREP003_RON_NonConditional.s.sol";

contract Simulation__20231003_UpgradeREP002AndREP003_RON_NonConditional_Wrapup2Periods is
  Simulation__20231003_UpgradeREP002AndREP003_RON_NonConditional
{
  function run() public virtual override {
    super.run();

    // submit block reward for one epoch
    vm.warp(block.timestamp + 3 seconds);
    vm.roll(block.number + 1);
    vm.prank(block.coinbase);
    _validatorSet.submitBlockReward{ value: 1_000_000 }();

    TConsensus[] memory finalityList = new TConsensus[](1);
    finalityList[0] = TConsensus.wrap(block.coinbase);
    vm.prank(block.coinbase);
    _fastFinalityTracking.recordFinality(finalityList);

    // wrap up period for second day after upgrade
    _fastForwardToNextDay();
    _wrapUpEpoch();

    // // test `RoninValidatorSet` functionality
    // _fastForwardToNextDay();
    // _wrapUpEpoch();

    // // test `RoninGatewayV3` functionality
    // _depositFor("after-upgrade-user");
  }
}
