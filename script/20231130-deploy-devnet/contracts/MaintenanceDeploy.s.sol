// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Contract } from "script/utils/Contract.sol";
import { Maintenance } from "@ronin/contracts/ronin/Maintenance.sol";
import { DevnetMigration } from "../DevnetMigration.s.sol";

contract MaintenanceDeploy is DevnetMigration {
  function _defaultArguments() internal virtual override returns (bytes memory args) { }

  function run() public virtual returns (Maintenance instance) {
    instance = Maintenance(_deployProxy(Contract.Maintenance.key()));
  }
}
