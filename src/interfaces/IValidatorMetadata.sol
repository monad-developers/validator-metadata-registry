// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/**
 * @title IValidatorMetadata
 * @notice Interface for an on-chain registry of human-readable Monad validator metadata.
 * @dev Augments the staking precompile by storing per-validator name, description, logo,
 *      socials, and a forward-compatible `additionalInfo` payload. Writes are authorized
 *      against the validator's authority address as reported by the staking precompile;
 *      implementations MAY additionally grant write access to other callers under their
 *      own authorization rules.
 */
interface IValidatorMetadata {
    /**
     * @notice Emitted on every successful write to a validator's metadata.
     * @param validatorId The validator whose metadata changed.
     * @param authority The caller that performed the update.
     * @param metadata The full metadata record as observable immediately after the write.
     */
    event MetadataUpdated(uint64 indexed validatorId, address indexed authority, Metadata metadata);

    /**
     * @notice Address of the Monad staking precompile used for authority resolution.
     * @return The staking precompile address, `0x0000000000000000000000000000000000001000`.
     */
    function STAKING_PRECOMPILE() external view returns (address);

    /**
     * @notice Validator metadata record.
     * @param name Human-readable validator name/moniker. Required; non-empty whenever a record exists.
     * @param website Validator's website URL.
     * @param description Detailed description of the validator.
     * @param logo URL to the validator's logo/avatar image.
     * @param socials JSON object of social profiles, keyed by platform identifier (e.g. `{"x":"...","telegram":"..."}`).
     * @param additionalInfo JSON object reserved for forward-compatible metadata extensions; not interpreted by the registry.
     */
    struct Metadata {
        string name;
        string website;
        string description;
        string logo;
        string socials;
        string additionalInfo;
    }

    /// @notice Field selector for `updateMetadataField`.
    enum Field {
        NAME,
        WEBSITE,
        DESCRIPTION,
        LOGO,
        SOCIALS,
        ADDITIONAL_INFO
    }

    /**
     * @notice Set or replace the full metadata record for a validator.
     * @dev Callable by the validator's authority address, resolved live against the staking
     *      precompile; implementations MAY accept additional authorized callers under their
     *      own scheme. Reverts if the caller is not authorized.
     * @dev Reverts if `metadata.name` is empty.
     * @dev Emits `MetadataUpdated` on success.
     * @param validatorId The validator ID to set metadata for.
     * @param metadata The metadata record to store.
     */
    function setMetadata(uint64 validatorId, Metadata calldata metadata) external;

    /**
     * @notice Update a single field of a validator's metadata, leaving other fields untouched.
     * @dev Callable by the validator's authority address, resolved live against the staking
     *      precompile; implementations MAY accept additional authorized callers under their
     *      own scheme. Reverts if the caller is not authorized.
     * @dev Reverts if no metadata has been set for `validatorId` yet — use `setMetadata` to
     *      create the record first.
     * @dev Reverts when `field == NAME` and `value` is empty.
     * @dev Emits `MetadataUpdated` with the full post-update record on success.
     * @param validatorId The validator ID whose field is being updated.
     * @param field The field to update.
     * @param value The new value. For `field == SOCIALS` or `ADDITIONAL_INFO`, callers SHOULD
     *              pass a UTF-8 JSON object; the registry stores the string verbatim and
     *              does not validate JSON syntax.
     */
    function updateMetadataField(uint64 validatorId, Field field, string calldata value) external;

    /**
     * @notice Read the stored metadata record for a validator.
     * @dev Returns an all-default `Metadata` struct if no record exists; check `hasMetadata`
     *      first to distinguish an unset record from one whose every field happens to be empty.
     * @param validatorId The validator ID to read.
     * @return metadata The validator's metadata record.
     */
    function getMetadata(uint64 validatorId) external view returns (Metadata memory metadata);

    /**
     * @notice Whether metadata has been set for a validator.
     * @dev True iff the stored `name` is non-empty. Because `name` is required to be non-empty
     *      on every write, this is equivalent to "any metadata has ever been written for this
     *      validator".
     * @param validatorId The validator ID to check.
     * @return True if a metadata record exists for `validatorId`, false otherwise.
     */
    function hasMetadata(uint64 validatorId) external view returns (bool);

    /**
     * @notice Read just the validator's stored name.
     * @param validatorId The validator ID to read.
     * @return The validator's name, or the empty string if no metadata has been set.
     */
    function getValidatorName(uint64 validatorId) external view returns (string memory);
}
