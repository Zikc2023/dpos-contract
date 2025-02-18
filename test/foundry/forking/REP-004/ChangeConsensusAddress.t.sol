// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import { Test } from "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";
import { StdStyle } from "forge-std/StdStyle.sol";
import { TConsensus } from "@ronin/contracts/udvts/Types.sol";
import { Maintenance } from "@ronin/contracts/ronin/Maintenance.sol";
import { ContractType } from "@ronin/contracts/utils/ContractType.sol";
import { MockPrecompile } from "@ronin/contracts/mocks/MockPrecompile.sol";
import { IProfile, Profile } from "@ronin/contracts/ronin/profile/Profile.sol";
import { Profile_Mainnet } from "@ronin/contracts/ronin/profile/Profile_Mainnet.sol";
import { IBaseStaking, Staking } from "@ronin/contracts/ronin/staking/Staking.sol";
import { HasContracts } from "@ronin/contracts/extensions/collections/HasContracts.sol";
import { CandidateManager } from "@ronin/contracts/ronin/validator/CandidateManager.sol";
import { EmergencyExitBallot } from "@ronin/contracts/libraries/EmergencyExitBallot.sol";
import { SlashIndicator } from "@ronin/contracts/ronin/slash-indicator/SlashIndicator.sol";
import {
  ICandidateManagerCallback,
  ICandidateManager,
  RoninValidatorSet
} from "@ronin/contracts/ronin/validator/RoninValidatorSet.sol";
import {
  TransparentUpgradeableProxy,
  TransparentUpgradeableProxyV2
} from "@ronin/contracts/extensions/TransparentUpgradeableProxyV2.sol";
import { IRoninGovernanceAdmin, RoninGovernanceAdmin } from "@ronin/contracts/ronin/RoninGovernanceAdmin.sol";
import {
  IRoninTrustedOrganization,
  RoninTrustedOrganization
} from "@ronin/contracts/multi-chains/RoninTrustedOrganization.sol";
import { Proposal } from "@ronin/contracts/libraries/Proposal.sol";
import { Ballot } from "@ronin/contracts/libraries/Ballot.sol";

contract ChangeConsensusAddressForkTest is Test {
  using StdStyle for *;

  string constant RONIN_TEST_RPC = "https://saigon-archive.roninchain.com/rpc";
  string constant RONIN_MAIN_RPC = "https://api-archived.roninchain.com/rpc";
  bytes32 constant ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

  Profile internal _profile;
  Staking internal _staking;
  Maintenance internal _maintenance;
  RoninValidatorSet internal _validator;
  RoninGovernanceAdmin internal _roninGA;
  SlashIndicator internal _slashIndicator;
  RoninTrustedOrganization internal _roninTO;

  uint _profileCooldownConfig;

  modifier upgrade() {
    _upgradeContracts();
    _profileCooldownConfig = _profile.getCooldownConfig();
    _;
  }

  function _upgradeContracts() internal {
    _upgradeProfile();
    _upgradeStaking();
    _upgradeValidator();
    _upgradeMaintenance();
    _upgradeSlashIndicator();
    _upgradeRoninTO();
  }

  function setUp() external {
    MockPrecompile mockPrecompile = new MockPrecompile();
    vm.etch(address(0x68), address(mockPrecompile).code);
    vm.makePersistent(address(0x68));
    vm.etch(address(0x6a), address(mockPrecompile).code);
    vm.makePersistent(address(0x6a));

    vm.createSelectFork(RONIN_TEST_RPC, 21901973);
    // vm.createSelectFork(RONIN_MAIN_RPC, 29225255);

    if (block.chainid == 2021) {
      _profile = Profile(0x3b67c8D22a91572a6AB18acC9F70787Af04A4043);
      _maintenance = Maintenance(0x4016C80D97DDCbe4286140446759a3f0c1d20584);
      _staking = Staking(payable(0x9C245671791834daf3885533D24dce516B763B28));
      _roninGA = RoninGovernanceAdmin(0x53Ea388CB72081A3a397114a43741e7987815896);
      _slashIndicator = SlashIndicator(0xF7837778b6E180Df6696C8Fa986d62f8b6186752);
      _roninTO = RoninTrustedOrganization(0x7507dc433a98E1fE105d69f19f3B40E4315A4F32);
      _validator = RoninValidatorSet(payable(0x54B3AC74a90E64E8dDE60671b6fE8F8DDf18eC9d));
    }
    if (block.chainid == 2020) {
      // Mainnet
      _profile = Profile(0x840EBf1CA767CB690029E91856A357a43B85d035);
      _maintenance = Maintenance(0x6F45C1f8d84849D497C6C0Ac4c3842DC82f49894);
      _staking = Staking(payable(0x545edb750eB8769C868429BE9586F5857A768758));
      _roninGA = RoninGovernanceAdmin(0x946397deDFd2f79b75a72B322944a21C3240c9c3);
      _slashIndicator = SlashIndicator(0xEBFFF2b32fA0dF9C5C8C5d5AAa7e8b51d5207bA3);
      _roninTO = RoninTrustedOrganization(0x98D0230884448B3E2f09a177433D60fb1E19C090);
      _validator = RoninValidatorSet(payable(0x617c5d73662282EA7FfD231E020eCa6D2B0D552f));
    }

    vm.label(address(_profile), "Profile");
    vm.label(address(_staking), "Staking");
    vm.label(address(_validator), "Validator");
    vm.label(address(_maintenance), "Maintenance");
    vm.label(address(_roninGA), "GovernanceAdmin");
    vm.label(address(_roninTO), "TrustedOrganizations");
    vm.label(address(_slashIndicator), "SlashIndicator");
  }

  function _toSingletonArrayConsensuses(address consensus) private pure returns (TConsensus[] memory arr) {
    arr = new TConsensus[](1);
    arr[0] = TConsensus.wrap(consensus);
  }

  function testFork_ChangeCandidateAdmin_StakingRewardsFlow() external upgrade {
    // apply validator candidate
    _applyValidatorCandidate("a1", "c1");
    _bulkWrapUpEpoch(1);

    address c1 = makeAddr("c1");
    address a1 = makeAddr("a1");
    address a2 = makeAddr("a2");

    // change admin of c1 -> a2
    vm.startPrank(a1);
    _profile.changeAdminAddr(c1, a2);
    vm.stopPrank();

    address coinbase = block.coinbase;

    vm.coinbase(c1);
    _bulkSubmitBlockReward(1);
    _bulkWrapUpEpoch(1);

    vm.coinbase(c1);
    _bulkSubmitBlockReward(1);
    _bulkWrapUpEpoch(1);

    // reset coinbase
    vm.coinbase(coinbase);

    vm.deal(a1, 1000 ether);
    vm.deal(a2, 1000 ether);

    uint256 snapshotId = vm.snapshot();

    uint256 amount = a2.balance;
    console2.log("a2 can claim reward c1".yellow());
    vm.prank(a2);
    _staking.claimRewards(_toSingletonArrayConsensuses(c1));
    assertTrue(a2.balance > amount, "a2 can claim reward c1".red());

    vm.revertTo(snapshotId);
    console2.log("a1 cannot claim reward c1".yellow());
    amount = a1.balance;
    vm.prank(a1);
    _staking.claimRewards(_toSingletonArrayConsensuses(c1));
    assertTrue(a2.balance == amount, "a1 cannot claim reward c1".red());

    console2.log("a2 cannot delegate c1".yellow());
    vm.prank(a2);
    vm.expectRevert();
    _staking.delegate{ value: 100 ether }(TConsensus.wrap(c1));

    console2.log("a2 can stake c1".yellow());
    vm.prank(a2);
    _staking.stake{ value: 100 ether }(TConsensus.wrap(c1));

    console2.log("a1 cannot delegate c1".yellow());
    vm.prank(a1);
    vm.expectRevert();
    _staking.delegate{ value: 100 ether }(TConsensus.wrap(c1));

    console2.log("a1 cannot stake c1".yellow());
    vm.prank(a1);
    vm.expectRevert();
    _staking.stake{ value: 100 ether }(TConsensus.wrap(c1));

    uint256 a2BalanceBefore = a2.balance;

    vm.prank(a2);
    _staking.requestRenounce(TConsensus.wrap(c1));

    _bulkWrapUpEpoch(7);

    // a2 received balance after renounce
    uint256 a2BalanceAfter = a2.balance;
    assertTrue(a2BalanceAfter - a2BalanceBefore != 0);
    console2.log("Received:", a2BalanceAfter - a2BalanceBefore);
  }

  function testFork_AfterUpgraded_AddNewTrustedOrg_CanVoteProposal() external upgrade {
    _cheatSetRoninGACode();
    // add trusted org
    address consensus = makeAddr("consensus");
    address governor = makeAddr("governor");
    IRoninTrustedOrganization.TrustedOrganization memory newTrustedOrg =
      IRoninTrustedOrganization.TrustedOrganization(TConsensus.wrap(consensus), governor, address(0x0), 1000, 0);
    _addTrustedOrg(newTrustedOrg);

    address newLogic = address(new RoninValidatorSet());
    address[] memory targets = new address[](1);
    targets[0] = address(_validator);
    uint256[] memory values = new uint256[](1);
    bytes[] memory calldatas = new bytes[](1);
    calldatas[0] = abi.encodeCall(TransparentUpgradeableProxy.upgradeTo, newLogic);
    uint256[] memory gasAmounts = new uint256[](1);
    gasAmounts[0] = 1_000_000;
    Ballot.VoteType support = Ballot.VoteType.For;

    vm.startPrank(governor);
    _roninGA.proposeProposalForCurrentNetwork(
      block.timestamp + 5 minutes, targets, values, calldatas, gasAmounts, support
    );
    vm.stopPrank();
  }

  function testFork_RevertWhen_AfterUpgraded_ApplyValidatorCandidateC1_AddNewTrustedOrgC1_ChangeC1ToC2_RenounceC2()
    external
    upgrade
  {
    // apply validator candidate
    _applyValidatorCandidate("candidate-admin", "c1");

    // add trusted org
    address consensus = makeAddr("c1");
    address governor = makeAddr("governor");
    IRoninTrustedOrganization.TrustedOrganization memory newTrustedOrg =
      IRoninTrustedOrganization.TrustedOrganization(TConsensus.wrap(consensus), governor, address(0x0), 1000, 0);
    _addTrustedOrg(newTrustedOrg);

    address newConsensus = makeAddr("c2");
    address admin = makeAddr("candidate-admin");
    vm.startPrank(admin);
    _profile.changeConsensusAddr(consensus, TConsensus.wrap(newConsensus));
    vm.expectRevert(ICandidateManagerCallback.ErrTrustedOrgCannotRenounce.selector);
    _staking.requestRenounce(TConsensus.wrap(newConsensus));
    vm.stopPrank();
  }

  /**
   * R4-P-09
   */
  function testFork_AfterUpgraded_AsTrustedOrg_AfterRenouncedAndRemovedFromTO_ReAddAsTrustedOrg() external upgrade {
    // address[] memory validatorCids = _validator.getValidatorCandidates();
    // TConsensus standardConsensus;
    // address standardId;
    // for (uint i; i < validatorCids.length; i++) {
    //   if (_roninTO.getConsensusWeightById(validatorCids[i]) == 0) {
    //     standardId = validatorCids[i];
    //     standardConsensus = _profile.getId2Profile(standardId).consensus;
    //     break;
    //   }
    // }

    (, TConsensus standardConsensus) = _pickOneStandardCandidate();

    (address admin,,) = _staking.getPoolDetail(standardConsensus);
    vm.prank(admin);
    _staking.requestRenounce(standardConsensus);

    vm.warp(block.timestamp + 7 days);
    _bulkSubmitBlockReward(1);
    _bulkWrapUpEpoch(1);

    assertFalse(_validator.isValidatorCandidate(standardConsensus));

    IRoninTrustedOrganization.TrustedOrganization memory newTrustedOrg =
      IRoninTrustedOrganization.TrustedOrganization(standardConsensus, makeAddr("governor"), address(0x0), 1000, 0);
    _addTrustedOrg(newTrustedOrg);
  }

  function testFork_AfterUpgraded_AddNewTrustedOrgBefore_ApplyValidatorCandidateAfter() external upgrade {
    uint256 newWeight = 1000;

    // add trusted org
    address consensus = makeAddr("consensus");
    address governor = makeAddr("governor");
    IRoninTrustedOrganization.TrustedOrganization memory newTrustedOrg =
      IRoninTrustedOrganization.TrustedOrganization(TConsensus.wrap(consensus), governor, address(0x0), newWeight, 0);
    IRoninTrustedOrganization.TrustedOrganization[] memory trustedOrgs = _addTrustedOrg(newTrustedOrg);

    // apply validator candidate
    _applyValidatorCandidate("candidate-admin", "consensus");

    address admin = makeAddr("candidate-admin");
    address newAdmin = makeAddr("new-admin");
    address newTreasury = newAdmin;
    address newDummyTreasury = makeAddr("new-dummy-treasury");
    address newConsensus = makeAddr("new-consensus");

    vm.startPrank(admin);
    {
      vm.warp(block.timestamp + _profileCooldownConfig);
      _profile.changeConsensusAddr(consensus, TConsensus.wrap(newConsensus));

      vm.warp(block.timestamp + _profileCooldownConfig);
      _profile.changeAdminAddr(consensus, newAdmin);

      vm.warp(block.timestamp + _profileCooldownConfig);
      vm.expectRevert("Not supported");
      _profile.changeTreasuryAddr(consensus, payable(newDummyTreasury));
    }
    vm.stopPrank();

    // change new governor
    address newGovernor = makeAddr("new-governor");
    trustedOrgs[0].governor = newGovernor;
    trustedOrgs[0].consensusAddr = TConsensus.wrap(newConsensus);
    vm.prank(_getProxyAdmin(address(_roninTO)));
    TransparentUpgradeableProxyV2(payable(address(_roninTO))).functionDelegateCall(
      abi.encodeCall(RoninTrustedOrganization.updateTrustedOrganizations, trustedOrgs)
    );

    IProfile.CandidateProfile memory profile = _profile.getId2Profile(consensus);
    IRoninTrustedOrganization.TrustedOrganization memory trustedOrg =
      _roninTO.getTrustedOrganization(TConsensus.wrap(newConsensus));

    // assert eq to updated address
    // 1.
    assertEq(trustedOrg.governor, newGovernor);
    assertEq(TConsensus.unwrap(trustedOrg.consensusAddr), newConsensus);
    assertEq(profile.id, consensus);
    assertEq(profile.treasury, payable(newTreasury));
    assertEq(profile.__reservedGovernor, address(0x0));
    assertEq(TConsensus.unwrap(profile.consensus), newConsensus);

    // 2.
    __assertWeight(TConsensus.wrap(newConsensus), consensus, newWeight);
    __assertWeight(TConsensus.wrap(consensus), consensus, 0);
  }

  function testFork_AfterUpgraded_ApplyValidatorCandidateBefore_AddNewTrustedOrgAfter() external upgrade {
    uint256 newWeight = 1000;
    _profileCooldownConfig = _profile.getCooldownConfig();

    // apply validator candidate
    _applyValidatorCandidate("candidate-admin", "consensus");

    // add trusted org
    address consensus = makeAddr("consensus");
    address governor = makeAddr("governor");
    IRoninTrustedOrganization.TrustedOrganization memory newTrustedOrg =
      IRoninTrustedOrganization.TrustedOrganization(TConsensus.wrap(consensus), governor, address(0x0), newWeight, 0);
    IRoninTrustedOrganization.TrustedOrganization[] memory trustedOrgs = _addTrustedOrg(newTrustedOrg);

    address admin = makeAddr("candidate-admin");

    address newAdmin = makeAddr("new-admin");
    address newTreasury = newAdmin;
    address newDummyTreasury = makeAddr("new-dummy-treasury");
    address newConsensus = makeAddr("new-consensus");

    vm.startPrank(admin);
    {
      vm.warp(block.timestamp + _profileCooldownConfig);
      _profile.changeConsensusAddr(consensus, TConsensus.wrap(newConsensus));
      vm.warp(block.timestamp + _profileCooldownConfig);
      _profile.changeAdminAddr(consensus, newAdmin);

      vm.warp(block.timestamp + _profileCooldownConfig);
      vm.expectRevert("Not supported");
      _profile.changeTreasuryAddr(consensus, payable(newDummyTreasury));
    }
    vm.stopPrank();

    // change new governor
    address newGovernor = makeAddr("new-governor");
    trustedOrgs[0].governor = newGovernor;
    trustedOrgs[0].consensusAddr = TConsensus.wrap(newConsensus);
    vm.prank(_getProxyAdmin(address(_roninTO)));
    TransparentUpgradeableProxyV2(payable(address(_roninTO))).functionDelegateCall(
      abi.encodeCall(RoninTrustedOrganization.updateTrustedOrganizations, trustedOrgs)
    );

    IProfile.CandidateProfile memory profile = _profile.getId2Profile(consensus);
    IRoninTrustedOrganization.TrustedOrganization memory trustedOrg =
      _roninTO.getTrustedOrganization(TConsensus.wrap(newConsensus));

    // assert eq to updated address
    assertEq(trustedOrg.governor, newGovernor);
    assertEq(TConsensus.unwrap(trustedOrg.consensusAddr), newConsensus);
    assertEq(profile.id, consensus);
    assertEq(profile.treasury, payable(newTreasury));
    assertEq(profile.__reservedGovernor, address(0x0));
    assertEq(TConsensus.unwrap(profile.consensus), newConsensus);

    // 2.
    __assertWeight(TConsensus.wrap(newConsensus), consensus, newWeight);
    __assertWeight(TConsensus.wrap(consensus), consensus, 0);
  }

  function __assertWeight(TConsensus consensus, address id, uint256 weight) private {
    TConsensus[] memory consensuses = new TConsensus[](1);
    address[] memory ids = new address[](1);

    consensuses[0] = consensus;
    ids[0] = id;

    if (weight == 0) {
      assertEq(_roninTO.getConsensusWeight(consensuses[0]), weight);
      assertEq(_roninTO.getConsensusWeight(consensuses[0]), _roninTO.getConsensusWeight(consensuses[0]));
    } else {
      assertEq(_roninTO.getConsensusWeight(consensuses[0]), weight);
      assertEq(_roninTO.getConsensusWeight(consensuses[0]), _roninTO.getConsensusWeights(consensuses)[0]);
      assertEq(_roninTO.getConsensusWeights(consensuses)[0], _roninTO.getConsensusWeightById(ids[0]));
      assertEq(_roninTO.getConsensusWeightById(ids[0]), _roninTO.getConsensusWeightsById(ids)[0]);
      assertEq(_roninTO.getConsensusWeightsById(ids)[0], _roninTO.getConsensusWeight(consensuses[0]));
    }
  }

  /**
   * @dev After emergency exit success, the validator changes his addresses, but the refunded amount must be claimed by the old admin.
   */
  function testFork_AfterUpgraded_WithdrawableFund_execEmergencyExit() external upgrade {
    // TODO(bao): @TuDo1403 please enhance this test
    _cheatSetRoninGACode();
    IRoninTrustedOrganization.TrustedOrganization[] memory trustedOrgs = _roninTO.getAllTrustedOrganizations();
    TConsensus[] memory validatorCandidates = _validator.getValidatorCandidates();
    TConsensus validatorCandidate = validatorCandidates[2];
    ICandidateManager.ValidatorCandidate memory oldCandidate = _validator.getCandidateInfo(validatorCandidate);

    (address admin,,) = _staking.getPoolDetail(validatorCandidate);
    console2.log("admin", admin);

    address newAdmin = makeAddr("new-admin");
    TConsensus newConsensusAddr = TConsensus.wrap(makeAddr("new-consensus"));
    address payable newDummyTreasury = payable(makeAddr("new-dummy-treasury"));

    uint256 proposalRequestAt = block.timestamp;
    uint256 proposalExpiredAt = proposalRequestAt + _validator.emergencyExpiryDuration();
    bytes32 voteHash = EmergencyExitBallot.hash(
      TConsensus.unwrap(oldCandidate.__shadowedConsensus),
      oldCandidate.__shadowedTreasury,
      proposalRequestAt,
      proposalExpiredAt
    );

    vm.startPrank(admin);
    vm.expectEmit(address(_roninGA));
    emit IRoninGovernanceAdmin.EmergencyExitPollCreated(
      voteHash,
      TConsensus.unwrap(oldCandidate.__shadowedConsensus),
      oldCandidate.__shadowedTreasury,
      proposalRequestAt,
      proposalExpiredAt
    );
    _staking.requestEmergencyExit(validatorCandidate);
    vm.warp(block.timestamp + _profileCooldownConfig);
    _profile.changeConsensusAddr(TConsensus.unwrap(validatorCandidate), newConsensusAddr);
    vm.warp(block.timestamp + _profileCooldownConfig);
    _profile.changeAdminAddr(TConsensus.unwrap(validatorCandidate), newAdmin);

    vm.warp(block.timestamp + _profileCooldownConfig);
    vm.expectRevert("Not supported");
    _profile.changeTreasuryAddr(TConsensus.unwrap(validatorCandidate), newDummyTreasury);
    vm.stopPrank();

    // NOTE: locked fund refunded to the old treasury
    console2.log("recipient", oldCandidate.__shadowedTreasury);
    uint256 balanceBefore = oldCandidate.__shadowedTreasury.balance;
    console2.log("balanceBefore", balanceBefore);

    for (uint256 i; i < trustedOrgs.length; ++i) {
      if (trustedOrgs[i].governor != TConsensus.unwrap(validatorCandidate)) {
        vm.prank(trustedOrgs[i].governor);
        _roninGA.voteEmergencyExit(
          voteHash,
          TConsensus.unwrap(oldCandidate.__shadowedConsensus),
          oldCandidate.__shadowedTreasury,
          proposalRequestAt,
          proposalExpiredAt
        );
      }
    }

    uint256 balanceAfter = oldCandidate.__shadowedTreasury.balance;
    console2.log("balanceAfter", balanceAfter);
    uint256 fundReceived = balanceAfter - balanceBefore;
    console2.log("fundReceived", fundReceived);

    assertTrue(fundReceived != 0);
  }

  function testFork_AsTrustedOrg_AfterUpgraded_AfterChangeConsensus_requestRenounce() external upgrade {
    TConsensus trustedOrg = _roninTO.getAllTrustedOrganizations()[0].consensusAddr;
    console2.log("trustedOrgConsensus", TConsensus.unwrap(trustedOrg));
    address admin = _validator.getCandidateInfo(trustedOrg).__shadowedAdmin;

    TConsensus newConsensus = TConsensus.wrap(makeAddr("new-consensus"));
    vm.prank(admin);
    _profile.changeConsensusAddr(TConsensus.unwrap(trustedOrg), newConsensus);

    (address poolAdmin,,) = _staking.getPoolDetail(newConsensus);
    console2.log("poolAdmin", poolAdmin);

    vm.expectRevert();
    vm.prank(poolAdmin);
    _staking.requestRenounce(newConsensus);
  }

  function testFork_AsTrustedOrg_AfterUpgraded_AfterChangeConsensus_execEmergencyExit() external upgrade {
    TConsensus trustedOrg = _roninTO.getAllTrustedOrganizations()[0].consensusAddr;
    console2.log("trustedOrgConsensus", TConsensus.unwrap(trustedOrg));
    address admin = _validator.getCandidateInfo(trustedOrg).__shadowedAdmin;

    TConsensus newConsensus = TConsensus.wrap(makeAddr("new-consensus"));
    vm.prank(admin);
    _profile.changeConsensusAddr(TConsensus.unwrap(trustedOrg), newConsensus);

    (address poolAdmin,,) = _staking.getPoolDetail(newConsensus);
    console2.log("poolAdmin", poolAdmin);

    vm.prank(poolAdmin);
    _staking.requestEmergencyExit(newConsensus);
  }

  function testFork_NotReceiveReward_BeforeAndAfterUpgraded_execEmergencyExit() external {
    TConsensus[] memory validatorCandidates = _validator.getValidatorCandidates();
    TConsensus validatorCandidate = validatorCandidates[2];
    address recipient = _validator.getCandidateInfo(validatorCandidate).__shadowedTreasury;

    uint256 snapshotId = vm.snapshot();

    (address admin,,) = _staking.getPoolDetail(validatorCandidate);
    console2.log("before-upgrade-admin", admin);
    vm.prank(admin);
    _staking.requestEmergencyExit(validatorCandidate);

    uint256 adminBalanceBefore = admin.balance;
    console2.log("before-upgrade:adminBalanceBefore", adminBalanceBefore);

    vm.warp(block.timestamp + 7 days);
    _bulkWrapUpEpoch(1);

    uint256 adminBalanceAfter = admin.balance;
    console2.log("before-upgrade:adminBalanceAfter", adminBalanceAfter);

    assertFalse(_validator.isValidatorCandidate(validatorCandidate));
    console2.log("before-upgrade:recipient", recipient);
    uint256 balanceBefore = recipient.balance;
    console2.log("before-upgrade:balanceBefore", balanceBefore);

    _bulkSubmitBlockReward(1);
    _bulkWrapUpEpoch(1);

    uint256 balanceAfter = recipient.balance;
    console2.log("before-upgrade:balanceAfter", balanceAfter);
    uint256 rewardBeforeUpgrade = balanceAfter - balanceBefore;
    uint256 beforeUpgradeAdminStakingAmount = adminBalanceAfter - adminBalanceBefore;
    console2.log("before-upgrade:adminStakingAmount", beforeUpgradeAdminStakingAmount);
    console2.log("before-upgrade:reward", rewardBeforeUpgrade);

    assertEq(rewardBeforeUpgrade, 0);

    vm.revertTo(snapshotId);
    _upgradeContracts();

    (admin,,) = _staking.getPoolDetail(validatorCandidate);
    console2.log("after-upgrade-admin", admin);
    vm.prank(admin);
    _staking.requestEmergencyExit(validatorCandidate);

    adminBalanceBefore = admin.balance;
    console2.log("after-upgrade:adminBalanceBefore", adminBalanceBefore);

    vm.warp(block.timestamp + 7 days);
    _bulkWrapUpEpoch(1);

    adminBalanceAfter = admin.balance;
    console2.log("after-upgrade:adminBalanceAfter", adminBalanceAfter);

    uint256 afterUpgradeAdminStakingAmount = adminBalanceAfter - adminBalanceBefore;
    console2.log("after-upgrade:adminStakingAmount", afterUpgradeAdminStakingAmount);
    assertFalse(_validator.isValidatorCandidate(validatorCandidate));
    console2.log("after-upgrade:recipient", recipient);
    balanceBefore = recipient.balance;
    console2.log("after-upgrade:balanceBefore", balanceBefore);

    _bulkSubmitBlockReward(1);
    _bulkWrapUpEpoch(1);

    balanceAfter = recipient.balance;
    console2.log("after-upgrade:balanceAfter", balanceAfter);
    uint256 rewardAfterUpgrade = balanceAfter - balanceBefore;
    console2.log("after-upgrade:reward", rewardAfterUpgrade);

    assertEq(rewardAfterUpgrade, 0);
    assertEq(beforeUpgradeAdminStakingAmount, afterUpgradeAdminStakingAmount);
  }

  function testFork_AfterUpgraded_RevertWhen_ReapplySameAddress_Renounce() external upgrade {
    (, TConsensus standardConsensus) = _pickOneStandardCandidate();
    address recipient = _validator.getCandidateInfo(standardConsensus).__shadowedTreasury;

    (address admin,,) = _staking.getPoolDetail(standardConsensus);
    vm.prank(admin);
    _staking.requestRenounce(standardConsensus);

    vm.warp(block.timestamp + 7 days);
    _bulkSubmitBlockReward(1);
    _bulkWrapUpEpoch(1);

    assertFalse(_validator.isValidatorCandidate(standardConsensus));

    // re-apply same admin
    uint256 amount = _staking.minValidatorStakingAmount();
    vm.deal(admin, amount);
    vm.expectRevert();
    vm.prank(admin);
    _staking.applyValidatorCandidate{ value: amount }(
      admin, TConsensus.wrap(makeAddr("new-consensus")), payable(admin), 2500, "new-consensus", ""
    );
    // re-apply same consensus
    address newAdmin = makeAddr("new-admin");
    vm.deal(newAdmin, amount);
    vm.expectRevert();
    vm.prank(newAdmin);
    _staking.applyValidatorCandidate{ value: amount }(
      newAdmin, standardConsensus, payable(newAdmin), 2500, "new-admin", ""
    );

    console2.log("recipient", recipient);
    uint256 balanceBefore = recipient.balance;
    console2.log("balanceBefore", balanceBefore);

    _bulkSubmitBlockReward(1);
    _bulkWrapUpEpoch(1);

    uint256 balanceAfter = recipient.balance;
    console2.log("balanceAfter", balanceAfter);
    uint256 reward = balanceAfter - balanceBefore;
    console2.log("reward", reward);

    assertEq(reward, 0);
  }

  function testFork_AfterUpgraded_ChangeConsensusAddress() external upgrade {
    TConsensus[] memory validatorCandidates = _validator.getValidatorCandidates();
    TConsensus validatorCandidate = validatorCandidates[0];
    address cid = TConsensus.unwrap(validatorCandidate);
    address candidateAdmin = _validator.getCandidateInfo(validatorCandidate).__shadowedAdmin;
    TConsensus newConsensus = TConsensus.wrap(makeAddr("new-consensus-0"));

    vm.prank(candidateAdmin);
    _profile.changeConsensusAddr(cid, newConsensus);

    _bulkWrapUpEpoch(1);

    validatorCandidate = validatorCandidates[1];
    cid = TConsensus.unwrap(validatorCandidate);
    candidateAdmin = _validator.getCandidateInfo(validatorCandidate).__shadowedAdmin;
    newConsensus = TConsensus.wrap(makeAddr("new-consensus-1"));
    vm.prank(candidateAdmin);
    _profile.changeConsensusAddr(cid, newConsensus);

    _bulkWrapUpEpoch(1);
  }

  function testFork_AfterUpgraded_WrapUpEpochAndNonWrapUpEpoch_ChangeAdmin_ChangeConsensus_ChangeTreasury()
    external
    upgrade
  {
    TConsensus[] memory validatorCandidates = _validator.getValidatorCandidates();
    address cid = TConsensus.unwrap(validatorCandidates[0]);
    address candidateAdmin = _validator.getCandidateInfo(TConsensus.wrap(cid)).__shadowedAdmin;

    // change validator admin
    address newAdmin = makeAddr("new-admin");
    address newTreasury = newAdmin;
    address newConsensus = makeAddr("new-consensus");
    address payable newDummyTreasury = payable(makeAddr("new-dummy-treasury"));

    vm.startPrank(candidateAdmin);
    _profile.changeConsensusAddr(cid, TConsensus.wrap(newConsensus));
    _profile.changeAdminAddr(cid, newAdmin);

    vm.expectRevert("Not supported");
    _profile.changeTreasuryAddr(cid, newDummyTreasury);
    vm.stopPrank();

    // store snapshot state
    uint256 snapshotId = vm.snapshot();

    // wrap up epoch
    _bulkWrapUpEpoch(1);

    ICandidateManager.ValidatorCandidate memory wrapUpInfo = _validator.getCandidateInfo(TConsensus.wrap(newConsensus));
    ICandidateManager.ValidatorCandidate[] memory wrapUpInfos = _validator.getCandidateInfos();

    // revert to state before wrap up
    vm.revertTo(snapshotId);
    ICandidateManager.ValidatorCandidate memory nonWrapUpInfo =
      _validator.getCandidateInfo(TConsensus.wrap(newConsensus));
    ICandidateManager.ValidatorCandidate[] memory nonWrapUpInfos = _validator.getCandidateInfos();

    assertEq(wrapUpInfo.__shadowedAdmin, nonWrapUpInfo.__shadowedAdmin);
    assertEq(wrapUpInfo.__shadowedAdmin, newAdmin);
    assertEq(TConsensus.unwrap(wrapUpInfo.__shadowedConsensus), TConsensus.unwrap(nonWrapUpInfo.__shadowedConsensus));
    assertEq(TConsensus.unwrap(wrapUpInfo.__shadowedConsensus), newConsensus);
    assertEq(wrapUpInfo.__shadowedTreasury, nonWrapUpInfo.__shadowedTreasury);
    assertEq(wrapUpInfo.__shadowedTreasury, newTreasury);
    assertEq(wrapUpInfo.commissionRate, nonWrapUpInfo.commissionRate);
    assertEq(wrapUpInfo.revokingTimestamp, nonWrapUpInfo.revokingTimestamp);
    assertEq(wrapUpInfo.topupDeadline, nonWrapUpInfo.topupDeadline);

    IProfile.CandidateProfile memory mProfile = _profile.getId2Profile(cid);
    assertEq(mProfile.id, cid);
    assertEq(TConsensus.unwrap(mProfile.consensus), newConsensus);
    assertEq(mProfile.admin, newAdmin);
    assertEq(mProfile.treasury, newTreasury);

    assertEq(wrapUpInfos.length, nonWrapUpInfos.length);
    for (uint256 i; i < wrapUpInfos.length; ++i) {
      assertEq(keccak256(abi.encode(wrapUpInfos[i])), keccak256(abi.encode(nonWrapUpInfos[i])));
    }
  }

  function testFork_SlashIndicator_BeforeAndAfterUpgrade() external {
    TConsensus[] memory validatorCandidates = _validator.getValidatorCandidates();
    TConsensus validatorCandidate = validatorCandidates[0];
    address cid = TConsensus.unwrap(validatorCandidate);
    address candidateAdmin = _validator.getCandidateInfo(validatorCandidate).__shadowedAdmin;

    uint256 snapshotId = vm.snapshot();

    address recipient = _validator.getCandidateInfo(validatorCandidate).__shadowedTreasury;
    console2.log("before-upgrade:recipient", recipient);
    uint256 balanceBefore = recipient.balance;
    console2.log("before-upgrade:balanceBefore", balanceBefore);

    _bulkSubmitBlockReward(1);
    _bulkSlashIndicator(validatorCandidate, 150);

    _bulkWrapUpEpoch(1);

    uint256 balanceAfter = recipient.balance;
    console2.log("before-upgrade:balanceAfter", balanceAfter);
    uint256 beforeUpgradeReward = balanceAfter - balanceBefore;
    console2.log("before-upgrade:reward", beforeUpgradeReward);
    assertFalse(_validator.isBlockProducer(validatorCandidate));

    vm.revertTo(snapshotId);
    _upgradeContracts();
    TConsensus newConsensus = TConsensus.wrap(makeAddr("consensus"));
    vm.prank(candidateAdmin);
    _profile.changeConsensusAddr(cid, newConsensus);

    _bulkSubmitBlockReward(1);
    _bulkSlashIndicator(newConsensus, 150);

    console2.log("new-consensus", TConsensus.unwrap(newConsensus));

    recipient = _validator.getCandidateInfo(newConsensus).__shadowedTreasury;
    console2.log("after-upgrade:recipient", recipient);

    balanceBefore = recipient.balance;
    console2.log("after-upgrade:balanceBefore", balanceBefore);

    _bulkWrapUpEpoch(1);

    balanceAfter = recipient.balance;
    console2.log("after-upgrade:balanceAfter", balanceBefore);
    uint256 afterUpgradedReward = balanceAfter - balanceBefore;
    console2.log("after-upgrade:reward", afterUpgradedReward);

    assertFalse(_validator.isBlockProducer(newConsensus));
    assertEq(afterUpgradedReward, beforeUpgradeReward, "afterUpgradedReward != beforeUpgradeReward");
  }

  function testFork_Maintenance_BeforeAndAfterUpgrade() external {
    IRoninTrustedOrganization.TrustedOrganization memory trustedOrg = _roninTO.getTrustedOrganizationAt(0);
    TConsensus validatorCandidate = trustedOrg.consensusAddr;
    address cid = TConsensus.unwrap(validatorCandidate);
    address candidateAdmin = _validator.getCandidateInfo(validatorCandidate).__shadowedAdmin;

    // check balance before wrapup epoch
    address recipient = _validator.getCandidateInfo(validatorCandidate).__shadowedTreasury;
    console2.log("before-upgrade:recipient", recipient);
    uint256 balanceBefore = recipient.balance;
    console2.log("before-upgrade:balanceBefore", balanceBefore);
    uint256 minOffsetToStartSchedule = _maintenance.minOffsetToStartSchedule();

    // save snapshot state before wrapup
    uint256 snapshotId = vm.snapshot();

    _bulkSubmitBlockReward(1);
    uint256 latestEpoch = _validator.getLastUpdatedBlock() + 200;
    uint256 startMaintenanceBlock = latestEpoch + 1 + minOffsetToStartSchedule;
    uint256 endMaintenanceBlock = latestEpoch + minOffsetToStartSchedule + _maintenance.minMaintenanceDurationInBlock();
    this.schedule(candidateAdmin, validatorCandidate, startMaintenanceBlock, endMaintenanceBlock);
    vm.roll(latestEpoch + minOffsetToStartSchedule + 200);

    _bulkSlashIndicator(validatorCandidate, 150);
    _bulkWrapUpEpoch(1);

    // assertFalse(_maintenance.checkMaintained(validatorCandidate, block.number + 1));
    assertFalse(_validator.isBlockProducer(validatorCandidate));
    uint256 balanceAfter = recipient.balance;
    console2.log("before-upgrade:balanceAfter", balanceAfter);
    uint256 beforeUpgradeReward = balanceAfter - balanceBefore;
    console2.log("before-upgrade:reward", beforeUpgradeReward);

    // revert to previous state
    console2.log(
      StdStyle.blue("==============================================================================================")
    );
    vm.revertTo(snapshotId);
    _upgradeContracts();
    // change consensus address
    TConsensus newConsensus = TConsensus.wrap(makeAddr("consensus"));
    vm.prank(candidateAdmin);
    _profile.changeConsensusAddr(cid, newConsensus);

    recipient = _validator.getCandidateInfo(newConsensus).__shadowedTreasury;
    console2.log("after-upgrade:recipient", recipient);
    balanceBefore = recipient.balance;
    console2.log("after-upgrade:balanceBefore", balanceBefore);

    _bulkSubmitBlockReward(1);
    latestEpoch = _validator.getLastUpdatedBlock() + 200;
    startMaintenanceBlock = latestEpoch + 1 + minOffsetToStartSchedule;
    endMaintenanceBlock = latestEpoch + minOffsetToStartSchedule + _maintenance.minMaintenanceDurationInBlock();

    this.schedule(candidateAdmin, newConsensus, startMaintenanceBlock, endMaintenanceBlock);
    vm.roll(latestEpoch + minOffsetToStartSchedule + 200);

    _bulkSlashIndicator(newConsensus, 150);
    _bulkWrapUpEpoch(1);

    assertTrue(_maintenance.checkMaintained(newConsensus, block.number + 1));
    assertTrue(_maintenance.checkMaintainedById(TConsensus.unwrap(validatorCandidate), block.number + 1));
    assertFalse(_validator.isBlockProducer(newConsensus));

    vm.expectRevert(abi.encodeWithSignature("ErrLookUpIdFailed(address)", TConsensus.unwrap(validatorCandidate)));
    _maintenance.checkMaintained(validatorCandidate, block.number + 1);

    balanceAfter = recipient.balance;
    console2.log("after-upgrade:balanceAfter", balanceBefore);
    uint256 afterUpgradedReward = balanceAfter - balanceBefore;
    console2.log("after-upgrade:reward", afterUpgradedReward);
    assertEq(afterUpgradedReward, beforeUpgradeReward, "afterUpgradedReward != beforeUpgradeReward");
  }

  function testFork_ShareSameSameReward_BeforeAndAfterUpgrade() external {
    TConsensus[] memory validatorCandidates = _validator.getValidatorCandidates();
    TConsensus validatorCandidate = validatorCandidates[0];
    address cid = TConsensus.unwrap(validatorCandidate);
    address candidateAdmin = _validator.getCandidateInfo(validatorCandidate).__shadowedAdmin;
    //address recipient = candidateAdmin;
    address recipient = _validator.getCandidateInfo(validatorCandidate).__shadowedTreasury;
    console2.log("before-upgrade:recipient", recipient);
    uint256 balanceBefore = recipient.balance;
    console2.log("before-upgrade:balanceBefore", balanceBefore);
    uint256 snapshotId = vm.snapshot();

    _bulkSubmitBlockReward(1);
    _bulkWrapUpEpoch(1);

    uint256 balanceAfter = recipient.balance;
    console2.log("before-upgrade:balanceAfter", balanceAfter);
    uint256 beforeUpgradeReward = balanceAfter - balanceBefore;
    console2.log("before-upgrade:reward", beforeUpgradeReward);

    vm.revertTo(snapshotId);
    _upgradeContracts();
    TConsensus newConsensus = TConsensus.wrap(makeAddr("consensus"));
    vm.prank(candidateAdmin);
    _profile.changeConsensusAddr(cid, newConsensus);

    console2.log("new-consensus", TConsensus.unwrap(newConsensus));

    recipient = _validator.getCandidateInfo(newConsensus).__shadowedTreasury;
    console2.log("after-upgrade:recipient", recipient);

    balanceBefore = recipient.balance;
    console2.log("after-upgrade:balanceBefore", balanceBefore);

    _bulkSubmitBlockReward(1);
    _bulkWrapUpEpoch(1);

    balanceAfter = recipient.balance;
    console2.log("after-upgrade:balanceAfter", balanceBefore);
    uint256 afterUpgradedReward = balanceAfter - balanceBefore;
    console2.log("after-upgrade:reward", afterUpgradedReward);

    assertEq(afterUpgradedReward, beforeUpgradeReward, "afterUpgradedReward != beforeUpgradeReward");
  }

  function testFailFork_RevertWhen_AfterUpgraded_DifferentAdmins_ShareSameConsensusAddr() external upgrade {
    TConsensus[] memory validatorCandidates = _validator.getValidatorCandidates();
    TConsensus validatorCandidate = validatorCandidates[0];
    address cid = TConsensus.unwrap(validatorCandidate);
    address candidateAdmin = _validator.getCandidateInfo(validatorCandidate).__shadowedAdmin;
    TConsensus newConsensus = TConsensus.wrap(makeAddr("same-consensus"));
    vm.prank(candidateAdmin);
    _profile.changeConsensusAddr(cid, newConsensus);

    _bulkWrapUpEpoch(1);

    validatorCandidate = validatorCandidates[1];
    candidateAdmin = _validator.getCandidateInfo(validatorCandidate).__shadowedAdmin;
    newConsensus = TConsensus.wrap(makeAddr("same-consensus"));
    vm.prank(candidateAdmin);
    _profile.changeConsensusAddr(cid, newConsensus);

    _bulkWrapUpEpoch(1);
  }

  function testFork_AfterUpgraded_applyValidatorCandidate() external upgrade {
    _applyValidatorCandidate("candidate-admin-0", "consensus-0");
    _applyValidatorCandidate("candidate-admin-1", "consensus-1");
    _bulkWrapUpEpoch(1);
  }

  function testFork_AfterUpgraded_applyValidatorCandidateByPeriod() external upgrade {
    _applyValidatorCandidate("candidate-admin-0", "consensus-0");
    _bulkWrapUpEpoch(1);
    _applyValidatorCandidate("candidate-admin-1", "consensus-1");
  }

  function testFailFork_RevertWhen_AfterUpgraded_ReapplyValidatorCandidateByPeriod() external upgrade {
    _applyValidatorCandidate("candidate-admin", "consensus");
    _bulkWrapUpEpoch(1);
    _applyValidatorCandidate("candidate-admin", "consensus");
  }

  function testFailFork_RevertWhen_AfterUpgraded_ReapplyValidatorCandidate() external upgrade {
    _applyValidatorCandidate("candidate-admin", "consensus");
    _applyValidatorCandidate("candidate-admin", "consensus");
  }

  function schedule(address admin, TConsensus consensus, uint256 startAtBlock, uint256 endedAtBlock) external {
    vm.prank(admin);
    _maintenance.schedule(consensus, startAtBlock, endedAtBlock);
  }

  function _bulkWrapUpEpoch(uint256 times) internal {
    for (uint256 i; i < times; ++i) {
      _fastForwardToNextDay();
      _wrapUpEpoch();
    }
  }

  function _bulkSlashIndicator(TConsensus consensus, uint256 times) internal {
    vm.startPrank(block.coinbase);
    for (uint256 i; i < times; ++i) {
      _slashIndicator.slashUnavailability(consensus);
      vm.roll(block.number + 1);
    }
    vm.stopPrank();
  }

  function _bulkSubmitBlockReward(uint256 times) internal {
    for (uint256 i; i < times; ++i) {
      vm.roll(block.number + 1);
      vm.deal(block.coinbase, 1000 ether);
      vm.prank(block.coinbase);
      _validator.submitBlockReward{ value: 1000 ether }();
    }
  }

  function _upgradeProfile() internal {
    Profile logic;

    if (block.chainid == 2020) {
      logic = new Profile_Mainnet();
    }
    if (block.chainid == 2021) {
      // logic = new Profile_Testnet();
      logic = new Profile();
    }

    uint gl1 = gasleft();
    console2.log("gasleft 1", gl1);

    vm.prank(_getProxyAdmin(address(_profile)));
    TransparentUpgradeableProxyV2(payable(address(_profile))).upgradeToAndCall(
      address(logic), abi.encodeCall(Profile.initializeV2, (address(_staking), address(_roninTO)))
    );

    uint gl2 = gasleft();
    console2.log("gasleft 2", gl2);
    console2.log("consume", gl1 - gl2);
  }

  function _cheatSetRoninGACode() internal {
    RoninGovernanceAdmin logic =
      new RoninGovernanceAdmin(block.chainid, address(_roninTO), address(_validator), type(uint256).max);
    vm.etch(address(_roninGA), address(logic).code);

    vm.startPrank(address(_roninGA));
    _roninGA.setContract(ContractType.VALIDATOR, address(_validator));
    _roninGA.setContract(ContractType.RONIN_TRUSTED_ORGANIZATION, address(_roninTO));
    vm.stopPrank();
  }

  function _upgradeMaintenance() internal {
    Maintenance logic = new Maintenance();
    vm.prank(_getProxyAdmin(address(_maintenance)));
    TransparentUpgradeableProxyV2(payable(address(_maintenance))).upgradeToAndCall(
      address(logic), abi.encodeCall(Maintenance.initializeV3, (address(_profile)))
    );
  }

  function _upgradeRoninTO() internal {
    RoninTrustedOrganization logic = new RoninTrustedOrganization();
    vm.prank(_getProxyAdmin(address(_roninTO)));
    TransparentUpgradeableProxyV2(payable(address(_roninTO))).upgradeToAndCall(
      address(logic), abi.encodeCall(RoninTrustedOrganization.initializeV2, (address(_profile)))
    );
  }

  function _upgradeSlashIndicator() internal {
    SlashIndicator logic = new SlashIndicator();
    vm.prank(_getProxyAdmin(address(_slashIndicator)));
    TransparentUpgradeableProxyV2(payable(address(_slashIndicator))).upgradeTo(address(logic));
  }

  function _upgradeStaking() internal {
    Staking logic = new Staking();
    vm.prank(_getProxyAdmin(address(_staking)));
    TransparentUpgradeableProxyV2(payable(_staking)).upgradeToAndCall(
      address(logic), abi.encodeCall(Staking.initializeV3, (address(_profile)))
    );
  }

  function _upgradeValidator() internal {
    RoninValidatorSet logic = new RoninValidatorSet();
    vm.prank(_getProxyAdmin(address(_validator)));
    TransparentUpgradeableProxyV2(payable(_validator)).upgradeToAndCall(
      address(logic), abi.encodeCall(RoninValidatorSet.initializeV4, (address(_profile)))
    );
  }

  function _getProxyAdmin(address proxy) internal view returns (address payable proxyAdmin) {
    return payable(address(uint160(uint256(vm.load(address(proxy), ADMIN_SLOT)))));
  }

  function _wrapUpEpoch() internal {
    vm.prank(block.coinbase);
    _validator.wrapUpEpoch();
  }

  function _fastForwardToNextDay() internal {
    vm.warp(block.timestamp + 3 seconds);
    vm.roll(block.number + 1);

    uint256 numberOfBlocksInEpoch = _validator.numberOfBlocksInEpoch();

    uint256 epochEndingBlockNumber = block.number + (numberOfBlocksInEpoch - 1) - (block.number % numberOfBlocksInEpoch);
    uint256 nextDayTimestamp = block.timestamp + 1 days;

    // fast forward to next day
    vm.warp(nextDayTimestamp);
    vm.roll(epochEndingBlockNumber);
  }

  function _addTrustedOrg(IRoninTrustedOrganization.TrustedOrganization memory trustedOrg)
    internal
    returns (IRoninTrustedOrganization.TrustedOrganization[] memory trustedOrgs)
  {
    trustedOrgs = new IRoninTrustedOrganization.TrustedOrganization[](1);
    trustedOrgs[0] = trustedOrg;
    vm.prank(_getProxyAdmin(address(_roninTO)));
    TransparentUpgradeableProxyV2(payable(address(_roninTO))).functionDelegateCall(
      abi.encodeCall(RoninTrustedOrganization.addTrustedOrganizations, trustedOrgs)
    );
  }

  function _applyValidatorCandidate(string memory candidateAdminLabel, string memory consensusLabel) internal {
    address candidateAdmin = makeAddr(candidateAdminLabel);
    TConsensus consensusAddr = TConsensus.wrap(makeAddr(consensusLabel));
    bytes memory pubKey = bytes(candidateAdminLabel);

    uint256 amount = _staking.minValidatorStakingAmount();
    vm.deal(candidateAdmin, amount);
    vm.prank(candidateAdmin, candidateAdmin);
    _staking.applyValidatorCandidate{ value: amount }(
      candidateAdmin, consensusAddr, payable(candidateAdmin), 15_00, pubKey, ""
    );
  }

  function _pickOneStandardCandidate() internal view returns (address standardId, TConsensus standardConsensus) {
    address[] memory validatorCids = _validator.getValidatorCandidateIds();
    for (uint i; i < validatorCids.length; i++) {
      if (_roninTO.getConsensusWeightById(validatorCids[i]) == 0) {
        standardId = validatorCids[i];
        standardConsensus = _profile.getId2Profile(standardId).consensus;
        break;
      }
    }
  }
}
