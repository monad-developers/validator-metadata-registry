// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/**
 * @title IMonadStaking
 * @notice Interface for the Monad Staking Precompile at address 0x0000000000000000000000000000000000001000
 * @dev This precompile manages validator registration, delegation, and rewards
 */
interface IMonadStaking {
    /**
     * @notice Complete validator information from the precompile
     * @dev Matches Python SDK format: 12 fields returned from getValidator
     * @param authority Address that controls this validator
     * @param flags Validator flags/status
     * @param consensusStake Stake used for consensus
     * @param snapshotStake Snapshot stake value
     * @param stake Total stake delegated to this validator
     * @param accRewardPerToken Accumulator value for reward calculations
     * @param consensusCommission Commission rate for consensus
     * @param snapshotCommission Commission rate snapshot
     * @param commission Current commission rate
     * @param unclaimedRewards Rewards earned but not yet claimed
     * @param secpPubKey SECP256k1 public key for execution layer
     * @param blsPubKey BLS public key for consensus layer
     */
    struct ValidatorInfo {
        address authority;
        uint256 flags;
        uint256 consensusStake;
        uint256 snapshotStake;
        uint256 stake;
        uint256 accRewardPerToken;
        uint256 consensusCommission;
        uint256 snapshotCommission;
        uint256 commission;
        uint256 unclaimedRewards;
        bytes secpPubKey;
        bytes blsPubKey;
    }

    /**
     * @notice Delegator information for a specific validator
     * @param stake Amount of MON delegated
     * @param accumulator Accumulator value at time of last update
     * @param unclaimedRewards Rewards earned but not yet claimed
     */
    struct DelegatorInfo {
        uint256 stake;
        uint256 accumulator;
        uint256 unclaimedRewards;
    }

    /**
     * @notice Register a new validator with SECP and BLS public keys
     * @return success Whether the registration was successful
     */
    function addValidator() external returns (bool success);

    /**
     * @notice Delegate MON tokens to a validator
     * @param validatorId The ID of the validator to delegate to
     * @return success Whether the delegation was successful
     */
    function delegate(uint64 validatorId) external payable returns (bool success);

    /**
     * @notice Initiate undelegation of staked MON
     * @param validatorId The ID of the validator to undelegate from
     * @param amount Amount of MON to undelegate
     * @param withdrawalType Type of withdrawal (0 = standard, 1 = expedited)
     * @return success Whether the undelegation was initiated successfully
     */
    function undelegate(uint64 validatorId, uint256 amount, uint8 withdrawalType) external returns (bool success);

    /**
     * @notice Complete undelegation after withdrawal delay
     * @param validatorId The ID of the validator
     * @param withdrawalType Type of withdrawal that was initiated
     * @return success Whether the withdrawal was successful
     */
    function withdraw(uint64 validatorId, uint8 withdrawalType) external returns (bool success);

    /**
     * @notice Convert accumulated rewards into additional stake
     * @param validatorId The ID of the validator
     * @return success Whether compounding was successful
     */
    function compound(uint64 validatorId) external returns (bool success);

    /**
     * @notice Claim accumulated rewards
     * @param validatorId The ID of the validator
     * @return success Whether the claim was successful
     */
    function claimRewards(uint64 validatorId) external returns (bool success);

    /**
     * @notice Change validator commission rate
     * @param validatorId The ID of the validator
     * @param newCommission New commission rate in basis points
     * @return success Whether the commission change was successful
     */
    function changeCommission(uint64 validatorId, uint256 newCommission) external returns (bool success);

    /**
     * @notice Distribute external rewards (tips) to delegators
     * @param validatorId The ID of the validator
     * @return success Whether the reward distribution was successful
     */
    function externalReward(uint64 validatorId) external payable returns (bool success);

    /**
     * @notice Get complete validator information
     * @param validatorId The ID of the validator
     * @return info Complete validator information
     */
    function getValidator(uint64 validatorId) external returns (ValidatorInfo memory info);

    /**
     * @notice Get delegator information for a specific validator
     * @param validatorId The ID of the validator
     * @param delegator Address of the delegator
     * @return info Delegator stake and rewards information
     */
    function getDelegator(uint64 validatorId, address delegator) external returns (DelegatorInfo memory info);

    /**
     * @notice Get current epoch information
     * @return epoch Current epoch number
     */
    function getEpoch() external returns (uint256 epoch);
}
