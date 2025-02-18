// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import { TConsensus } from "../udvts/Types.sol";

interface IFastFinalityTracking {
  /**
   * @dev Submit list of `voters` who vote for fast finality in the current block.
   *
   * Requirements:
   * - Only called once per block
   * - Only coinbase can call this method
   */
  function recordFinality(TConsensus[] calldata voters) external;

  /**
   * @dev Returns vote count of `addrs` in the `period`.
   */
  function getManyFinalityVoteCounts(
    uint256 period,
    TConsensus[] calldata addrs
  ) external view returns (uint256[] memory voteCounts);

  /**
   * @dev Returns vote count of `cids` in the `period`.
   */
  function getManyFinalityVoteCountsById(
    uint256 period,
    address[] calldata cids
  ) external view returns (uint256[] memory voteCounts);
}
