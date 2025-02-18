// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "../../interfaces/slash-indicator/ISlashIndicator.sol";
import "../../interfaces/validator/IRoninValidatorSet.sol";
import "../../interfaces/IMaintenance.sol";
import "../../interfaces/IProfile.sol";
import "./DeprecatedSlashBridgeOperator.sol";
import "./DeprecatedSlashBridgeVoting.sol";
import "./SlashDoubleSign.sol";
import "./SlashFastFinality.sol";
import "./SlashUnavailability.sol";
import "./CreditScore.sol";

contract SlashIndicator is
  ISlashIndicator,
  SlashDoubleSign,
  SlashFastFinality,
  DeprecatedSlashBridgeVoting,
  DeprecatedSlashBridgeOperator,
  SlashUnavailability,
  CreditScore,
  Initializable
{
  constructor() {
    _disableInitializers();
  }

  /**
   * @dev Initializes the contract storage.
   */
  function initialize(
    address __validatorContract,
    address __maintenanceContract,
    address __roninTrustedOrganizationContract,
    address __roninGovernanceAdminContract,
    uint256[4] calldata, /* _bridgeOperatorSlashingConfigs */
    uint256[2] calldata, /* _bridgeVotingSlashingConfigs */
    // _doubleSignSlashingConfigs[0]: _slashDoubleSignAmount
    // _doubleSignSlashingConfigs[1]: _doubleSigningJailUntilBlock
    // _doubleSignSlashingConfigs[2]: _doubleSigningOffsetLimitBlock
    uint256[3] calldata _doubleSignSlashingConfigs,
    // _unavailabilitySlashingConfigs[0]: _unavailabilityTier1Threshold
    // _unavailabilitySlashingConfigs[1]: _unavailabilityTier2Threshold
    // _unavailabilitySlashingConfigs[2]: _slashAmountForUnavailabilityTier2Threshold
    // _unavailabilitySlashingConfigs[3]: _jailDurationForUnavailabilityTier2Threshold
    uint256[4] calldata _unavailabilitySlashingConfigs,
    // _creditScoreConfigs[0]: _gainCreditScore
    // _creditScoreConfigs[1]: _maxCreditScore
    // _creditScoreConfigs[2]: _bailOutCostMultiplier
    // _creditScoreConfigs[3]: _cutOffPercentageAfterBailout
    uint256[4] calldata _creditScoreConfigs
  ) external initializer {
    _setContract(ContractType.VALIDATOR, __validatorContract);
    _setContract(ContractType.MAINTENANCE, __maintenanceContract);
    _setContract(ContractType.GOVERNANCE_ADMIN, __roninGovernanceAdminContract);
    _setContract(ContractType.RONIN_TRUSTED_ORGANIZATION, __roninTrustedOrganizationContract);

    _setDoubleSignSlashingConfigs(
      _doubleSignSlashingConfigs[0], _doubleSignSlashingConfigs[1], _doubleSignSlashingConfigs[2]
    );
    _setUnavailabilitySlashingConfigs(
      _unavailabilitySlashingConfigs[0],
      _unavailabilitySlashingConfigs[1],
      _unavailabilitySlashingConfigs[2],
      _unavailabilitySlashingConfigs[3]
    );
    _setCreditScoreConfigs(
      _creditScoreConfigs[0], _creditScoreConfigs[1], _creditScoreConfigs[2], _creditScoreConfigs[3]
    );
  }

  function initializeV2(address roninGovernanceAdminContract) external reinitializer(2) {
    _setContract(ContractType.VALIDATOR, ______deprecatedValidator);
    _setContract(ContractType.MAINTENANCE, ______deprecatedMaintenance);
    _setContract(ContractType.GOVERNANCE_ADMIN, roninGovernanceAdminContract);
    _setContract(ContractType.RONIN_TRUSTED_ORGANIZATION, ______deprecatedTrustedOrg);

    delete ______deprecatedValidator;
    delete ______deprecatedMaintenance;
    delete ______deprecatedTrustedOrg;
    delete ______deprecatedGovernanceAdmin;
  }

  function initializeV3(address profileContract) external reinitializer(3) {
    _setContract(ContractType.PROFILE, profileContract);
    _setFastFinalitySlashingConfigs(_slashDoubleSignAmount, _doubleSigningJailUntilBlock);
  }

  /**
   * @dev Helper for CreditScore contract to reset the indicator of the validator after bailing out.
   */
  function _setUnavailabilityIndicator(
    address validator,
    uint256 period,
    uint256 indicator
  ) internal override(CreditScore, SlashUnavailability) {
    SlashUnavailability._setUnavailabilityIndicator(validator, period, indicator);
  }

  /**
   * @dev Helper for CreditScore contract to query indicator of the validator.
   */
  function _getUnavailabilityIndicatorById(
    address validatorId,
    uint256 period
  ) internal view override(CreditScore, SlashUnavailability) returns (uint256) {
    return SlashUnavailability._getUnavailabilityIndicatorById(validatorId, period);
  }

  function _checkBailedOutAtPeriodById(
    address cid,
    uint256 period
  ) internal view override(CreditScore, SlashUnavailability) returns (bool) {
    return CreditScore._checkBailedOutAtPeriodById(cid, period);
  }

  /**
   * @dev Sanity check the address to be slashed
   */
  function _shouldSlash(
    TConsensus consensus,
    address validatorId
  ) internal view override(SlashDoubleSign, SlashUnavailability) returns (bool) {
    return
    // The slasher must not be identical with the slashee
    (msg.sender != TConsensus.unwrap(consensus)) && (msg.sender != validatorId)
    // The slashee must still be block producer at the time of being slashed
    && IRoninValidatorSet(getContract(ContractType.VALIDATOR)).isBlockProducerById(validatorId)
    // The slashee must not on maintenance
    && !IMaintenance(getContract(ContractType.MAINTENANCE)).checkMaintainedById(validatorId, block.number);
  }

  function __css2cid(TConsensus consensusAddr)
    internal
    view
    override(CreditScore, SlashUnavailability, SlashFastFinality)
    returns (address)
  {
    return IProfile(getContract(ContractType.PROFILE)).getConsensus2Id(consensusAddr);
  }

  function __tryCss2cid(TConsensus consensusAddr) internal view override(SlashDoubleSign) returns (bool, address) {
    return IProfile(getContract(ContractType.PROFILE)).tryGetConsensus2Id(consensusAddr);
  }

  function __css2cidBatch(TConsensus[] memory consensusAddrs) internal view override returns (address[] memory) {
    return IProfile(getContract(ContractType.PROFILE)).getManyConsensus2Id(consensusAddrs);
  }
}
