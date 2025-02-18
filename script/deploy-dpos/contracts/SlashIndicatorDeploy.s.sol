// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { SlashIndicator } from "@ronin/contracts/ronin/slash-indicator/SlashIndicator.sol";
import { Contract } from "script/utils/Contract.sol";
import { DPoSMigration } from "../DPoSMigration.s.sol";

contract SlashIndicatorDeploy is DPoSMigration {
  function _defaultArguments() internal virtual override returns (bytes memory args) { }

  function run() public virtual returns (SlashIndicator instance) {
    instance = SlashIndicator(_deployProxy(Contract.SlashIndicator.key()));
  }
}
