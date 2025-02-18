// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "../../udvts/Types.sol";
import "../../utils/RoleAccess.sol";
import { ProfileStorage } from "./ProfileStorage.sol";
import { PCUVerifyBLSPublicKey } from "../../precompile-usages/PCUVerifyBLSPublicKey.sol";

abstract contract ProfileHandler is PCUVerifyBLSPublicKey, ProfileStorage {
  /**
   * @dev Checks each element in the new profile and reverts if there is duplication with any existing profile.
   */
  function _requireNonDuplicatedInRegistry(CandidateProfile memory profile) internal view {
    _requireNonZeroAndNonDuplicated(RoleAccess.CONSENSUS, TConsensus.unwrap(profile.consensus));
    _requireNonZeroAndNonDuplicated(RoleAccess.CANDIDATE_ADMIN, profile.admin);
    _requireNonZeroAndNonDuplicated(RoleAccess.TREASURY, profile.treasury);

    // Currently skip check of governor because the address is address(0x00).
    // _requireNonDuplicated(RoleAccess.GOVERNOR, profile.__reservedGovernor);

    _requireNonDuplicatedPubkey(profile.pubkey);
  }

  function _requireNonZeroAndNonDuplicated(RoleAccess addressType, address addr) internal view {
    if (addr == address(0)) revert ErrZeroAddress(addressType);
    _requireNonDuplicated(addressType, addr);
  }

  function _requireNonDuplicated(RoleAccess addressType, address addr) internal view {
    if (_isRegisteredAddr(addr)) {
      revert ErrDuplicatedInfo(addressType, uint256(uint160(addr)));
    }
  }

  function _isRegisteredAddr(address addr) internal view returns (bool) {
    return _registry[uint256(uint160(addr))];
  }

  function _requireNonDuplicatedPubkey(bytes memory pubkey) internal view {
    if (_isRegisteredPubkey(pubkey)) {
      revert ErrDuplicatedPubkey(pubkey);
    }
  }

  function _isRegisteredPubkey(bytes memory pubkey) internal view returns (bool) {
    return _registry[_hashPubkey(pubkey)];
  }

  function _verifyPubkey(bytes calldata publicKey, bytes calldata proofOfPossession) internal {
    if (!_pcVerifyBLSPublicKey(publicKey, proofOfPossession)) {
      revert ErrInvalidProofOfPossession(publicKey, proofOfPossession);
    } else {
      emit PubkeyVerified(publicKey, proofOfPossession);
    }
  }

  function _requireCooldownPassed(CandidateProfile storage _profile) internal view {
    if (block.timestamp < _profile.profileLastChange + _profileChangeCooldown) {
      revert ErrProfileChangeCooldownNotEnded();
    }
  }

  function _requireCooldownPassedAndStartCooldown(CandidateProfile storage _profile) internal {
    _requireCooldownPassed(_profile);
    _startCooldown(_profile);
  }
}
