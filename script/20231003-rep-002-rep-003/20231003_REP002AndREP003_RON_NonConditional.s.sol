// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./20231003_REP002AndREP003_Base.s.sol";

contract Simulation__20231003_UpgradeREP002AndREP003_RON_NonConditional is
  Simulation__20231003_UpgradeREP002AndREP003_Base
{
  function run() public virtual override {
    super.run();

    _upgradeDPoSContracts();

    // // test `RoninGatewayV3` functionality
    // _depositFor("before-upgrade-user");

    // trigger conditional migration
    _fastForwardToNextDay();
    _wrapUpEpoch();

    // // test `RoninValidatorSet` functionality
    // _fastForwardToNextDay();
    // _wrapUpEpoch();

    // // test `RoninGatewayV3` functionality
    // _depositFor("after-upgrade-user");
  }

  function _upgradeDPoSContracts() internal logFn("_upgradeDPoSContracts()") {
    {
      // upgrade `RoninValidatorSet`
      _upgradeProxy(Contract.RoninValidatorSet.key(), abi.encodeCall(RoninValidatorSet.initializeV2, ()));
      // bump `RoninValidatorSet` to V2, V3
      _validatorSet.initializeV3(loadContractOrDeploy(Contract.FastFinalityTracking.key()));
    }

    {
      // upgrade `Staking`
      // bump `Staking` to V2
      _upgradeProxy(Contract.Staking.key(), abi.encodeCall(Staking.initializeV2, ()));
    }

    {
      // upgrade `SlashIndicator`
      // bump `SlashIndicator` to V2, V3

      _upgradeProxy(
        Contract.SlashIndicator.key(), abi.encodeCall(SlashIndicator.initializeV2, (address(_roninGovernanceAdmin)))
      );
      _slashIndicator.initializeV3(loadContractOrDeploy(Contract.Profile.key()));
    }

    {
      // upgrade `RoninTrustedOrganization`
      _upgradeProxy(Contract.RoninTrustedOrganization.key(), EMPTY_ARGS);
    }

    {
      // upgrade `BridgeTracking`
      // bump `BridgeTracking` to V2
      _upgradeProxy(Contract.BridgeTracking.key(), abi.encodeCall(BridgeTracking.initializeV2, ()));
    }

    {
      // upgrade `StakingVesting`
      // bump `StakingVesting` to V2, V3
      _upgradeProxy(Contract.StakingVesting.key(), abi.encodeCall(StakingVesting.initializeV2, ()));
      _stakingVesting.initializeV3(50); // 5%
    }

    {
      // upgrade `Maintenance`
      // bump `Maintenance` to V2
      _upgradeProxy(Contract.Maintenance.key(), abi.encodeCall(Maintenance.initializeV2, ()));
    }
  }
}
