// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { console2 as console } from "forge-std/console2.sol";
import { stdStorage, StdStorage } from "forge-std/StdStorage.sol";
import { LibErrorHandler } from "contract-libs/LibErrorHandler.sol";
import { TContract } from "foundry-deployment-kit/types/Types.sol";
import { LibProxy } from "foundry-deployment-kit/libraries/LibProxy.sol";
import { Proposal, RoninMigration } from "script/RoninMigration.s.sol";
import { LibString, Contract } from "script/utils/Contract.sol";
import { RoninGovernanceAdmin, HardForkRoninGovernanceAdminDeploy } from "script/contracts/HardForkRoninGovernanceAdminDeploy.s.sol";
import { RoninTrustedOrganization, TemporalRoninTrustedOrganizationDeploy } from "script/contracts/TemporalRoninTrustedOrganizationDeploy.s.sol";
import "./20232811_ChangeGovernanceAdmin_Common.s.sol";

contract Migration__20232811_ChangeGovernanceAdmin_NotYetHardfork is Migration__20232811_ChangeGovernanceAdmin_Common {
  using LibString for *;
  using LibErrorHandler for bool;
  using stdStorage for StdStorage;
  using LibProxy for address payable;

  bytes32 constant $_IMPL_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

  function __node_hardfork_hook() internal override {
    // Get current broken Ronin Governance Admin
    __roninGovernanceAdmin = config.getAddressFromCurrentNetwork(Contract.RoninGovernanceAdmin.key());

    // Deploy new Ronin Governance Admin
    __hardForkGovernanceAdmin = new HardForkRoninGovernanceAdminDeploy().run();
    __trustedOrg = config.getAddressFromCurrentNetwork(Contract.RoninTrustedOrganization.key());

    // Deploy temporary Ronin Trusted Organization
    address tempTrustedOrgLogic = _deployLogic(Contract.TemporalRoninTrustedOrganization.key());
    vm.makePersistent(address(tempTrustedOrgLogic));

    // Cheat storage slot of impl in Trusted Org Proxy
    vm.store(address(__trustedOrg), bytes32($_IMPL_SLOT), bytes32(uint256(uint160(tempTrustedOrgLogic))));

    if (block.chainid == DefaultNetwork.RoninTestnet.chainId()) {
      // TODO: put the adding profile to Profile_Testnet
      // Cheat add Profile for community-validator: 0x9687e8C41fa369aD08FD278a43114C4207856a61

      // address profileContract = config.getAddressFromCurrentNetwork(Contract.Profile.key());
      // vm.store(
      //   profileContract,
      //   bytes32(0xe2b5ca0375b8eef7b8b64fc95e405858a03b6325b0d163d50bf963cf7c15b633),
      //   bytes32(uint256(uint160(0x9687e8C41fa369aD08FD278a43114C4207856a61)))
      // );
      // vm.store(
      //   profileContract,
      //   bytes32(0xe2b5ca0375b8eef7b8b64fc95e405858a03b6325b0d163d50bf963cf7c15b634),
      //   bytes32(uint256(uint160(0x9687e8C41fa369aD08FD278a43114C4207856a61)))
      // );
    }
  }
}
