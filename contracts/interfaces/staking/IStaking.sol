// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "./IBaseStaking.sol";
import "./IStakingCallback.sol";
import "./ICandidateStaking.sol";
import "./IDelegatorStaking.sol";

interface IStaking is IRewardPool, IBaseStaking, ICandidateStaking, IDelegatorStaking, IStakingCallback {
  /// @dev Event emitted when the `wasAdmin` is finished to migrate.
  event MigrateWasAdminFinished();
  /// @dev Event emitted when the `migrateWasAdmin` method is disabled.
  event MigrateWasAdminDisabled();

  /// @dev Error indicating that the REP-4 migration is already done.
  error ErrMigrateWasAdminAlreadyDone();

  /**
   * @dev Records the amount of rewards `_rewards` for the pools `_consensusAddrs`.
   *
   * Requirements:
   * - The method caller must be validator contract.
   *
   * Emits the event `PoolsUpdated` once the contract recorded the rewards successfully.
   * Emits the event `PoolsUpdateFailed` once the input array lengths are not equal.
   * Emits the event `PoolsUpdateConflicted` when there are some pools which already updated in the period.
   *
   * Note: This method should be called once at the period ending.
   *
   */
  function execRecordRewards(address[] calldata poolIds, uint256[] calldata rewards, uint256 period) external payable;

  /**
   * @dev Deducts from staking amount of the validator `_consensusAddr` for `_amount`.
   *
   * Requirements:
   * - The method caller must be validator contract.
   *
   * Emits the event `Unstaked`.
   *
   */
  function execDeductStakingAmount(address poolId, uint256 amount) external returns (uint256 actualDeductingAmount);
}
