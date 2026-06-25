// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IValidatorMetadata} from "src/interfaces/IValidatorMetadata.sol";
import {IMonadStaking} from "src/interfaces/IMonadStaking.sol";

/**
 * @title ValidatorMetadata
 * @notice Stores and manages additional metadata for Monad validators
 * @dev This contract augments the on-chain validator information from the staking precompile
 * with off-chain metadata like names, descriptions, and contact information
 */
contract ValidatorMetadata is IValidatorMetadata {
    /// @dev Caller is not the validator authority
    error Unauthorized();

    /// @dev Validator name cannot be empty
    error ValidatorNameEmpty();

    /// @dev Validator metadata has not been set yet
    error ValidatorMetadataEmpty();

    /// @dev Delegate address may not be the zero address
    error InvalidDelegate();

    /// @notice The Monad staking precompile address
    address public constant override STAKING_PRECOMPILE = address(0x0000000000000000000000000000000000001000);

    /// @notice Mapping from validatorId to metadata
    mapping(uint64 => Metadata) private _metadata;

    /// @notice Approval mapping. `_approvals[validatorId][authority][delegate] == true`
    ///         means `delegate` may write metadata for `validatorId` when `authority` is its
    ///         current authority. Keyed by validatorId + authority + delegate so that:
    ///         (a) approvals are scoped to a specific validator,
    ///         (b) a staking-precompile authority rotation implicitly invalidates the prior
    ///             authority's delegates for that validator (the lookup key changes).
    mapping(uint64 validatorId => mapping(address authority => mapping(address delegate => bool isApproved))) private
        _approvals;

    /// @notice Emitted when a delegate's approval state for a specific validator changes.
    /// @param validatorId The validator the approval is scoped to.
    /// @param authority The validator's current authority (verified by `setApproval`).
    /// @param delegate The address being approved or revoked.
    /// @param approved True if the delegate may now write metadata for `validatorId`, false if revoked.
    event MetadataApprovalSet(
        uint64 indexed validatorId, address indexed authority, address indexed delegate, bool approved
    );

    /// @notice Emitted when a validator's metadata record is deleted.
    /// @param validatorId The validator whose metadata was deleted.
    /// @param authority The caller that performed the deletion (validator's authority or an approved delegate).
    event MetadataDeleted(uint64 indexed validatorId, address indexed authority);

    /// Restricts to the validator's current authority, or an address the authority has approved
    /// for this specific validator.
    modifier onlyAuthorizedWriter(uint64 validatorId) {
        address authority = IMonadStaking(STAKING_PRECOMPILE).getValidator(validatorId).authority;
        require(msg.sender == authority || _approvals[validatorId][authority][msg.sender], Unauthorized());
        _;
    }

    function setMetadata(uint64 validatorId, Metadata calldata metadata)
        external
        override
        onlyAuthorizedWriter(validatorId)
    {
        require(bytes(metadata.name).length > 0, ValidatorNameEmpty());

        _metadata[validatorId] = metadata;
        emit MetadataUpdated(validatorId, msg.sender, metadata);
    }

    function updateMetadataField(uint64 validatorId, Field field, string calldata value)
        external
        override
        onlyAuthorizedWriter(validatorId)
    {
        Metadata storage metaRef = _metadata[validatorId];

        if (bytes(metaRef.name).length == 0) {
            revert ValidatorMetadataEmpty();
        }

        if (field == Field.NAME) {
            require(bytes(value).length > 0, ValidatorNameEmpty());
            metaRef.name = value;
        } else if (field == Field.WEBSITE) {
            metaRef.website = value;
        } else if (field == Field.DESCRIPTION) {
            metaRef.description = value;
        } else if (field == Field.LOGO) {
            metaRef.logo = value;
        } else if (field == Field.SOCIALS) {
            metaRef.socials = value;
        } else {
            metaRef.additionalInfo = value;
        }

        emit MetadataUpdated(validatorId, msg.sender, metaRef);
    }

    /// @notice Delete the stored metadata record for a validator.
    /// @dev Callable by the validator's authority address (resolved live against the staking
    ///      precompile) or by any address the authority has approved via `setApproval`.
    /// @dev Reverts if no metadata has been set for `validatorId`.
    /// @dev After successful deletion, `hasMetadata(validatorId)` returns `false` and
    ///      `getMetadata(validatorId)` returns the default `Metadata` struct.
    /// @dev Emits `MetadataDeleted` on success.
    /// @param validatorId The validator ID whose record is being deleted.
    function deleteMetadata(uint64 validatorId) external onlyAuthorizedWriter(validatorId) {
        if (bytes(_metadata[validatorId].name).length == 0) {
            revert ValidatorMetadataEmpty();
        }

        delete _metadata[validatorId];
        emit MetadataDeleted(validatorId, msg.sender);
    }

    function getMetadata(uint64 validatorId) external view override returns (Metadata memory metadata) {
        return _metadata[validatorId];
    }

    function hasMetadata(uint64 validatorId) external view override returns (bool) {
        return bytes(_metadata[validatorId].name).length > 0;
    }

    function getValidatorName(uint64 validatorId) external view override returns (string memory) {
        return _metadata[validatorId].name;
    }

    /// @notice Grant or revoke `delegate`'s right to write metadata for `validatorId`.
    /// @dev The caller MUST be the current authority of `validatorId` per the staking
    ///      precompile; otherwise reverts with `Unauthorized`. Approvals are stored under
    ///      `_approvals[validatorId][msg.sender][delegate]`, so a subsequent authority
    ///      rotation in the staking precompile implicitly invalidates them (the
    ///      write-check key changes). Sub-delegation is structurally impossible: a
    ///      delegate calling this would be rejected by the authority check.
    /// @param validatorId The validator the approval is scoped to.
    /// @param delegate The address being approved or revoked. MUST NOT be the zero address
    ///                 or the caller itself.
    /// @param approved True to grant, false to revoke.
    function setApproval(uint64 validatorId, address delegate, bool approved) external {
        require(delegate != address(0) && delegate != msg.sender, InvalidDelegate());
        address authority = IMonadStaking(STAKING_PRECOMPILE).getValidator(validatorId).authority;
        require(msg.sender == authority, Unauthorized());
        if (_approvals[validatorId][authority][delegate] == approved) return;
        _approvals[validatorId][authority][delegate] = approved;
        emit MetadataApprovalSet(validatorId, authority, delegate, approved);
    }

    /// @notice Whether `delegate` is approved to write metadata for `validatorId` when
    ///         `authority` is its current authority.
    /// @dev Pure storage lookup keyed by (validatorId, authority, delegate). To check by
    ///      validator id alone, callers resolve `getValidator(validatorId).authority`
    ///      against the staking precompile and pass that address here. This function does
    ///      not proxy to the precompile because Monad's staking precompile rejects
    ///      STATICCALL (a `view`-marked function would compile to STATICCALL).
    function isApproved(uint64 validatorId, address authority, address delegate) external view returns (bool) {
        return _approvals[validatorId][authority][delegate];
    }
}
