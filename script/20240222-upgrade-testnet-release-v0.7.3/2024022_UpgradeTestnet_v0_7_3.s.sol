// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { IBaseStaking } from "@ronin/contracts/interfaces/staking/IBaseStaking.sol";
import {
  TransparentUpgradeableProxy,
  TransparentUpgradeableProxyV2
} from "@ronin/contracts/extensions/TransparentUpgradeableProxyV2.sol";
import { StdStyle } from "forge-std/StdStyle.sol";
import { console2 as console } from "forge-std/console2.sol";
import { TContract } from "foundry-deployment-kit/types/Types.sol";
import { LibProxy } from "foundry-deployment-kit/libraries/LibProxy.sol";
import { DefaultNetwork } from "foundry-deployment-kit/utils/DefaultNetwork.sol";
import { RoninTrustedOrganization, Proposal, RoninMigration, RoninGovernanceAdmin } from "script/RoninMigration.s.sol";
import { Contract } from "script/utils/Contract.sol";

contract Migration__20240222_UpgradeReleaseV0_7_3_Testnet is RoninMigration {
  using LibProxy for *;
  using StdStyle for *;

  uint256 private constant WAITING_SECS_TO_REVOKE = 1 days;

  address[] private contractsToUpgrade;
  TContract[] private contractTypesToUpgrade;

  function run() public onlyOn(DefaultNetwork.RoninTestnet.key()) {
    RoninGovernanceAdmin governanceAdmin =
      RoninGovernanceAdmin(config.getAddressFromCurrentNetwork(Contract.RoninGovernanceAdmin.key()));
    RoninTrustedOrganization trustedOrg =
      RoninTrustedOrganization(config.getAddressFromCurrentNetwork(Contract.RoninTrustedOrganization.key()));
    address payable[] memory allContracts = config.getAllAddresses(network());

    for (uint256 i; i < allContracts.length; ++i) {
      address proxyAdmin = allContracts[i].getProxyAdmin(false);
      if (proxyAdmin != address(governanceAdmin)) {
        console.log(
          unicode"⚠ WARNING:".yellow(),
          string.concat(
            vm.getLabel(allContracts[i]),
            " has different ProxyAdmin. Expected: ",
            vm.getLabel(address(governanceAdmin)),
            " Got: ",
            vm.toString(proxyAdmin)
          )
        );
      } else {
        address implementation = allContracts[i].getProxyImplementation();
        TContract contractType = config.getContractTypeFromCurrentNetwok(allContracts[i]);

        if (implementation.codehash != keccak256(vm.getDeployedCode(config.getContractAbsolutePath(contractType)))) {
          console.log(
            "Different Code Hash Detected. Contract To Upgrade:".cyan(),
            vm.getLabel(allContracts[i]),
            string.concat(" Query code Hash From: ", vm.getLabel(implementation))
          );
          contractTypesToUpgrade.push(contractType);
          contractsToUpgrade.push(allContracts[i]);
        } else {
          console.log("Contract not to Upgrade:", vm.getLabel(allContracts[i]));
        }
      }
    }

    uint256 innerCallCount = contractTypesToUpgrade.length + 1;
    console.log("Number contract to upgrade:", innerCallCount);

    bytes[] memory callDatas = new bytes[](innerCallCount);
    address[] memory targets = new address[](innerCallCount);
    uint256[] memory values = new uint256[](innerCallCount);
    address[] memory logics = new address[](innerCallCount);

    callDatas[innerCallCount - 1] = abi.encodeCall(
      TransparentUpgradeableProxyV2.functionDelegateCall,
      (abi.encodeCall(IBaseStaking.setWaitingSecsToRevoke, (WAITING_SECS_TO_REVOKE)))
    );
    targets[innerCallCount - 1] = loadContract(Contract.Staking.key());

    for (uint256 i; i < innerCallCount - 1; ++i) {
      targets[i] = contractsToUpgrade[i];
      logics[i] = _deployLogic(contractTypesToUpgrade[i]);
      callDatas[i] = abi.encodeCall(TransparentUpgradeableProxy.upgradeTo, (logics[i]));

      console.log("Code hash for:", vm.getLabel(logics[i]), vm.toString(logics[i].codehash));
      console.log(
        "Computed code hash:",
        vm.toString(keccak256(vm.getDeployedCode(config.getContractAbsolutePath(contractTypesToUpgrade[i]))))
      );
    }

    Proposal.ProposalDetail memory proposal =
      _buildProposal(governanceAdmin, block.timestamp + 14 days, targets, values, callDatas);
    _executeProposal(governanceAdmin, trustedOrg, proposal);
  }
}
