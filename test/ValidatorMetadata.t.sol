// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {ValidatorMetadata} from "src/ValidatorMetadata.sol";
import {IValidatorMetadata} from "src/interfaces/IValidatorMetadata.sol";
import {IMonadStaking} from "src/interfaces/IMonadStaking.sol";

contract ValidatorMetadataTest is Test {
    ValidatorMetadata internal registry;

    address internal constant STAKING_PRECOMPILE = 0x0000000000000000000000000000000000001000;

    address internal constant AUTHORITY_A = address(0xA1);
    address internal constant AUTHORITY_B = address(0xB2);
    address internal constant ATTACKER = address(0xDEAD);
    uint64 internal constant VALIDATOR_ID = 42;

    /// Mirror of IValidatorMetadata.MetadataUpdated so vm.expectEmit can resolve topics.
    event MetadataUpdated(uint64 indexed validatorId, address indexed authority, IValidatorMetadata.Metadata metadata);

    function setUp() public {
        registry = new ValidatorMetadata();
    }

    // ─── Helpers ─────────────────────────────────────────────────────────

    /// Make the staking precompile return `authority` from `getValidator(validatorId).authority`.
    function _mockAuthority(uint64 validatorId, address authority) internal {
        IMonadStaking.ValidatorInfo memory info;
        info.authority = authority;
        vm.mockCall(
            STAKING_PRECOMPILE,
            abi.encodeWithSelector(IMonadStaking.getValidator.selector, validatorId),
            abi.encode(info)
        );
    }

    function _sampleMetadata() internal pure returns (IValidatorMetadata.Metadata memory) {
        return IValidatorMetadata.Metadata({
            name: "TestValidator",
            website: "https://example.com",
            description: "A test validator",
            logo: "https://example.com/logo.png",
            socials: "{\"x\":\"https://x.com/test\"}",
            additionalInfo: "{\"region\":\"eu-west-1\"}"
        });
    }

    function _seedRecord(uint64 validatorId, address authority) internal {
        _mockAuthority(validatorId, authority);
        vm.prank(authority);
        registry.setMetadata(validatorId, _sampleMetadata());
    }

    function _assertMetadataEq(IValidatorMetadata.Metadata memory a, IValidatorMetadata.Metadata memory b)
        internal
        pure
    {
        assertEq(a.name, b.name, "name");
        assertEq(a.website, b.website, "website");
        assertEq(a.description, b.description, "description");
        assertEq(a.logo, b.logo, "logo");
        assertEq(a.socials, b.socials, "socials");
        assertEq(a.additionalInfo, b.additionalInfo, "additionalInfo");
    }

    // ─── Constants and getters (MRC test case 10) ────────────────────────

    function test_StakingPrecompileAddressIsCanonical() public view {
        assertEq(registry.STAKING_PRECOMPILE(), STAKING_PRECOMPILE);
    }

    // ─── setMetadata: happy path (MRC case 1) ────────────────────────────

    function test_SetMetadata_AsAuthority_PersistsAndEmits() public {
        _mockAuthority(VALIDATOR_ID, AUTHORITY_A);
        IValidatorMetadata.Metadata memory m = _sampleMetadata();

        vm.expectEmit(true, true, false, true);
        emit MetadataUpdated(VALIDATOR_ID, AUTHORITY_A, m);

        vm.prank(AUTHORITY_A);
        registry.setMetadata(VALIDATOR_ID, m);

        _assertMetadataEq(registry.getMetadata(VALIDATOR_ID), m);
    }

    // ─── setMetadata: unauthorized (MRC case 2) ──────────────────────────

    function test_SetMetadata_AsNonAuthority_Reverts() public {
        _mockAuthority(VALIDATOR_ID, AUTHORITY_A);

        vm.expectRevert(ValidatorMetadata.Unauthorized.selector);
        vm.prank(ATTACKER);
        registry.setMetadata(VALIDATOR_ID, _sampleMetadata());
    }

    // ─── setMetadata: nonexistent validator (zero authority) ─────────────

    function test_SetMetadata_RevertsWhenAuthorityIsZero() public {
        // The staking precompile returns address(0) for a nonexistent validator;
        // no real caller can be address(0), so the existing authority check rejects.
        _mockAuthority(VALIDATOR_ID, address(0));

        vm.expectRevert(ValidatorMetadata.Unauthorized.selector);
        vm.prank(AUTHORITY_A);
        registry.setMetadata(VALIDATOR_ID, _sampleMetadata());
    }

    // ─── setMetadata: empty name (MRC case 3) ────────────────────────────

    function test_SetMetadata_EmptyName_Reverts() public {
        _mockAuthority(VALIDATOR_ID, AUTHORITY_A);
        IValidatorMetadata.Metadata memory m = _sampleMetadata();
        m.name = "";

        vm.expectRevert(ValidatorMetadata.ValidatorNameEmpty.selector);
        vm.prank(AUTHORITY_A);
        registry.setMetadata(VALIDATOR_ID, m);
    }

    function test_SetMetadata_NameOnly_AllOtherFieldsEmpty_Succeeds() public {
        _mockAuthority(VALIDATOR_ID, AUTHORITY_A);
        IValidatorMetadata.Metadata memory m = IValidatorMetadata.Metadata({
            name: "MinimalValidator", website: "", description: "", logo: "", socials: "", additionalInfo: ""
        });

        vm.prank(AUTHORITY_A);
        registry.setMetadata(VALIDATOR_ID, m);

        _assertMetadataEq(registry.getMetadata(VALIDATOR_ID), m);
        assertTrue(registry.hasMetadata(VALIDATOR_ID));
    }

    // ─── setMetadata: overwrite existing record (additional) ─────────────

    function test_SetMetadata_OverwritesExistingRecord() public {
        _seedRecord(VALIDATOR_ID, AUTHORITY_A);

        IValidatorMetadata.Metadata memory replacement = IValidatorMetadata.Metadata({
            name: "Replaced", website: "", description: "", logo: "", socials: "", additionalInfo: ""
        });
        vm.prank(AUTHORITY_A);
        registry.setMetadata(VALIDATOR_ID, replacement);

        _assertMetadataEq(registry.getMetadata(VALIDATOR_ID), replacement);
    }

    // ─── updateMetadataField: no prior record (MRC case 4) ───────────────

    function test_UpdateMetadataField_NoPriorRecord_RevertsForEveryField() public {
        _mockAuthority(VALIDATOR_ID, AUTHORITY_A);

        vm.startPrank(AUTHORITY_A);
        vm.expectRevert(ValidatorMetadata.ValidatorMetadataEmpty.selector);
        registry.updateMetadataField(VALIDATOR_ID, IValidatorMetadata.Field.NAME, "x");
        vm.expectRevert(ValidatorMetadata.ValidatorMetadataEmpty.selector);
        registry.updateMetadataField(VALIDATOR_ID, IValidatorMetadata.Field.WEBSITE, "x");
        vm.expectRevert(ValidatorMetadata.ValidatorMetadataEmpty.selector);
        registry.updateMetadataField(VALIDATOR_ID, IValidatorMetadata.Field.DESCRIPTION, "x");
        vm.expectRevert(ValidatorMetadata.ValidatorMetadataEmpty.selector);
        registry.updateMetadataField(VALIDATOR_ID, IValidatorMetadata.Field.LOGO, "x");
        vm.expectRevert(ValidatorMetadata.ValidatorMetadataEmpty.selector);
        registry.updateMetadataField(VALIDATOR_ID, IValidatorMetadata.Field.SOCIALS, "x");
        vm.expectRevert(ValidatorMetadata.ValidatorMetadataEmpty.selector);
        registry.updateMetadataField(VALIDATOR_ID, IValidatorMetadata.Field.ADDITIONAL_INFO, "x");
        vm.stopPrank();
    }

    // ─── updateMetadataField: unauthorized ───────────────────────────────

    function test_UpdateMetadataField_AsNonAuthority_Reverts() public {
        _seedRecord(VALIDATOR_ID, AUTHORITY_A);

        vm.expectRevert(ValidatorMetadata.Unauthorized.selector);
        vm.prank(ATTACKER);
        registry.updateMetadataField(VALIDATOR_ID, IValidatorMetadata.Field.WEBSITE, "https://attacker.com");
    }

    // ─── updateMetadataField: per-field updates (MRC case 5, all six branches) ─

    function test_UpdateMetadataField_Name_UpdatesAndEmitsFullRecord() public {
        _seedRecord(VALIDATOR_ID, AUTHORITY_A);

        IValidatorMetadata.Metadata memory expected = _sampleMetadata();
        expected.name = "NewName";

        vm.expectEmit(true, true, false, true);
        emit MetadataUpdated(VALIDATOR_ID, AUTHORITY_A, expected);

        vm.prank(AUTHORITY_A);
        registry.updateMetadataField(VALIDATOR_ID, IValidatorMetadata.Field.NAME, "NewName");
        _assertMetadataEq(registry.getMetadata(VALIDATOR_ID), expected);
    }

    function test_UpdateMetadataField_Website_UpdatesAndEmitsFullRecord() public {
        _seedRecord(VALIDATOR_ID, AUTHORITY_A);

        IValidatorMetadata.Metadata memory expected = _sampleMetadata();
        expected.website = "https://newsite.example";

        vm.expectEmit(true, true, false, true);
        emit MetadataUpdated(VALIDATOR_ID, AUTHORITY_A, expected);

        vm.prank(AUTHORITY_A);
        registry.updateMetadataField(VALIDATOR_ID, IValidatorMetadata.Field.WEBSITE, "https://newsite.example");
        _assertMetadataEq(registry.getMetadata(VALIDATOR_ID), expected);
    }

    function test_UpdateMetadataField_Description_UpdatesAndEmitsFullRecord() public {
        _seedRecord(VALIDATOR_ID, AUTHORITY_A);

        IValidatorMetadata.Metadata memory expected = _sampleMetadata();
        expected.description = "Updated description text";

        vm.expectEmit(true, true, false, true);
        emit MetadataUpdated(VALIDATOR_ID, AUTHORITY_A, expected);

        vm.prank(AUTHORITY_A);
        registry.updateMetadataField(VALIDATOR_ID, IValidatorMetadata.Field.DESCRIPTION, "Updated description text");
        _assertMetadataEq(registry.getMetadata(VALIDATOR_ID), expected);
    }

    function test_UpdateMetadataField_Logo_UpdatesAndEmitsFullRecord() public {
        _seedRecord(VALIDATOR_ID, AUTHORITY_A);

        IValidatorMetadata.Metadata memory expected = _sampleMetadata();
        expected.logo = "ipfs://newlogo";

        vm.expectEmit(true, true, false, true);
        emit MetadataUpdated(VALIDATOR_ID, AUTHORITY_A, expected);

        vm.prank(AUTHORITY_A);
        registry.updateMetadataField(VALIDATOR_ID, IValidatorMetadata.Field.LOGO, "ipfs://newlogo");
        _assertMetadataEq(registry.getMetadata(VALIDATOR_ID), expected);
    }

    function test_UpdateMetadataField_Socials_UpdatesAndEmitsFullRecord() public {
        _seedRecord(VALIDATOR_ID, AUTHORITY_A);

        IValidatorMetadata.Metadata memory expected = _sampleMetadata();
        expected.socials = "{\"telegram\":\"@newhandle\"}";

        vm.expectEmit(true, true, false, true);
        emit MetadataUpdated(VALIDATOR_ID, AUTHORITY_A, expected);

        vm.prank(AUTHORITY_A);
        registry.updateMetadataField(VALIDATOR_ID, IValidatorMetadata.Field.SOCIALS, "{\"telegram\":\"@newhandle\"}");
        _assertMetadataEq(registry.getMetadata(VALIDATOR_ID), expected);
    }

    function test_UpdateMetadataField_AdditionalInfo_UpdatesAndEmitsFullRecord() public {
        _seedRecord(VALIDATOR_ID, AUTHORITY_A);

        IValidatorMetadata.Metadata memory expected = _sampleMetadata();
        expected.additionalInfo = "{\"version\":2}";

        vm.expectEmit(true, true, false, true);
        emit MetadataUpdated(VALIDATOR_ID, AUTHORITY_A, expected);

        vm.prank(AUTHORITY_A);
        registry.updateMetadataField(VALIDATOR_ID, IValidatorMetadata.Field.ADDITIONAL_INFO, "{\"version\":2}");
        _assertMetadataEq(registry.getMetadata(VALIDATOR_ID), expected);
    }

    // ─── updateMetadataField: empty NAME (MRC case 6 first half) ─────────

    function test_UpdateMetadataField_Name_Empty_Reverts() public {
        _seedRecord(VALIDATOR_ID, AUTHORITY_A);

        vm.expectRevert(ValidatorMetadata.ValidatorNameEmpty.selector);
        vm.prank(AUTHORITY_A);
        registry.updateMetadataField(VALIDATOR_ID, IValidatorMetadata.Field.NAME, "");
    }

    // ─── updateMetadataField: empty value clears optional fields (MRC case 6 second half) ─

    function test_UpdateMetadataField_EmptyValue_ClearsOptionalFields() public {
        _seedRecord(VALIDATOR_ID, AUTHORITY_A);

        vm.startPrank(AUTHORITY_A);
        registry.updateMetadataField(VALIDATOR_ID, IValidatorMetadata.Field.WEBSITE, "");
        registry.updateMetadataField(VALIDATOR_ID, IValidatorMetadata.Field.DESCRIPTION, "");
        registry.updateMetadataField(VALIDATOR_ID, IValidatorMetadata.Field.LOGO, "");
        registry.updateMetadataField(VALIDATOR_ID, IValidatorMetadata.Field.SOCIALS, "");
        registry.updateMetadataField(VALIDATOR_ID, IValidatorMetadata.Field.ADDITIONAL_INFO, "");
        vm.stopPrank();

        IValidatorMetadata.Metadata memory stored = registry.getMetadata(VALIDATOR_ID);
        assertEq(stored.name, _sampleMetadata().name, "name should be unchanged");
        assertEq(stored.website, "");
        assertEq(stored.description, "");
        assertEq(stored.logo, "");
        assertEq(stored.socials, "");
        assertEq(stored.additionalInfo, "");
    }

    // ─── updateMetadataField: ADDITIONAL_INFO accepts non-JSON verbatim (MRC case 7) ─

    function test_UpdateMetadataField_AdditionalInfo_NoJsonValidation() public {
        _seedRecord(VALIDATOR_ID, AUTHORITY_A);

        string memory garbage = "this is definitely not json {{{ ;; \x00";
        vm.prank(AUTHORITY_A);
        registry.updateMetadataField(VALIDATOR_ID, IValidatorMetadata.Field.ADDITIONAL_INFO, garbage);

        assertEq(registry.getMetadata(VALIDATOR_ID).additionalInfo, garbage);
    }

    function test_UpdateMetadataField_Socials_NoJsonValidation() public {
        _seedRecord(VALIDATOR_ID, AUTHORITY_A);

        string memory garbage = "not-json-at-all";
        vm.prank(AUTHORITY_A);
        registry.updateMetadataField(VALIDATOR_ID, IValidatorMetadata.Field.SOCIALS, garbage);

        assertEq(registry.getMetadata(VALIDATOR_ID).socials, garbage);
    }

    // ─── Authority rotation (MRC case 8) ─────────────────────────────────

    function test_AuthorityRotation_NewAuthorityCanWriteImmediately() public {
        _seedRecord(VALIDATOR_ID, AUTHORITY_A);

        // Precompile rotates to authority B (no registry-side action needed).
        _mockAuthority(VALIDATOR_ID, AUTHORITY_B);

        vm.prank(AUTHORITY_B);
        registry.updateMetadataField(VALIDATOR_ID, IValidatorMetadata.Field.WEBSITE, "https://from-b.example");
        assertEq(registry.getMetadata(VALIDATOR_ID).website, "https://from-b.example");
    }

    function test_AuthorityRotation_OldAuthorityCannotWriteAfterRotation() public {
        _seedRecord(VALIDATOR_ID, AUTHORITY_A);

        _mockAuthority(VALIDATOR_ID, AUTHORITY_B);

        vm.expectRevert(ValidatorMetadata.Unauthorized.selector);
        vm.prank(AUTHORITY_A);
        registry.updateMetadataField(VALIDATOR_ID, IValidatorMetadata.Field.WEBSITE, "https://from-a.example");
    }

    function test_AuthorityRotation_NewAuthorityCanOverwriteFullRecord() public {
        _seedRecord(VALIDATOR_ID, AUTHORITY_A);

        _mockAuthority(VALIDATOR_ID, AUTHORITY_B);

        IValidatorMetadata.Metadata memory bsRecord = IValidatorMetadata.Metadata({
            name: "OperatorB", website: "https://b.example", description: "", logo: "", socials: "", additionalInfo: ""
        });
        vm.prank(AUTHORITY_B);
        registry.setMetadata(VALIDATOR_ID, bsRecord);
        _assertMetadataEq(registry.getMetadata(VALIDATOR_ID), bsRecord);
    }

    // ─── hasMetadata / getMetadata / getValidatorName (MRC case 9 + extras) ─

    function test_HasMetadata_FalseWhenUnset() public view {
        assertFalse(registry.hasMetadata(VALIDATOR_ID));
    }

    function test_HasMetadata_TrueAfterSet() public {
        _seedRecord(VALIDATOR_ID, AUTHORITY_A);
        assertTrue(registry.hasMetadata(VALIDATOR_ID));
    }

    function test_HasMetadata_FalseForDifferentValidatorId() public {
        _seedRecord(VALIDATOR_ID, AUTHORITY_A);
        assertFalse(registry.hasMetadata(VALIDATOR_ID + 1));
    }

    function test_GetMetadata_ReturnsZeroStructWhenUnset() public view {
        IValidatorMetadata.Metadata memory stored = registry.getMetadata(VALIDATOR_ID);
        assertEq(stored.name, "");
        assertEq(stored.website, "");
        assertEq(stored.description, "");
        assertEq(stored.logo, "");
        assertEq(stored.socials, "");
        assertEq(stored.additionalInfo, "");
    }

    function test_GetValidatorName_EmptyWhenUnset() public view {
        assertEq(registry.getValidatorName(VALIDATOR_ID), "");
    }

    function test_GetValidatorName_ReturnsStoredName() public {
        _seedRecord(VALIDATOR_ID, AUTHORITY_A);
        assertEq(registry.getValidatorName(VALIDATOR_ID), _sampleMetadata().name);
    }

    // ─── Delegation / approval flow ──────────────────────────────────────

    address internal constant DELEGATE = address(0xD1);
    address internal constant OTHER_DELEGATE = address(0xD2);

    /// Mirror of ValidatorMetadata.MetadataApprovalSet so vm.expectEmit can resolve topics.
    event MetadataApprovalSet(
        uint64 indexed validatorId, address indexed authority, address indexed delegate, bool approved
    );

    function test_IsApproved_DefaultFalse() public view {
        assertFalse(registry.isApproved(VALIDATOR_ID, AUTHORITY_A, DELEGATE));
    }

    function test_SetApproval_GrantsAndEmits() public {
        _mockAuthority(VALIDATOR_ID, AUTHORITY_A);

        vm.expectEmit(true, true, true, true);
        emit MetadataApprovalSet(VALIDATOR_ID, AUTHORITY_A, DELEGATE, true);

        vm.prank(AUTHORITY_A);
        registry.setApproval(VALIDATOR_ID, DELEGATE, true);

        assertTrue(registry.isApproved(VALIDATOR_ID, AUTHORITY_A, DELEGATE));
    }

    function test_SetApproval_Revokes() public {
        _mockAuthority(VALIDATOR_ID, AUTHORITY_A);

        vm.startPrank(AUTHORITY_A);
        registry.setApproval(VALIDATOR_ID, DELEGATE, true);
        registry.setApproval(VALIDATOR_ID, DELEGATE, false);
        vm.stopPrank();

        assertFalse(registry.isApproved(VALIDATOR_ID, AUTHORITY_A, DELEGATE));
    }

    function test_SetApproval_AsNonAuthority_Reverts() public {
        // Under the (validatorId, authority, delegate)-keyed scheme, setApproval
        // verifies the caller is the validator's current authority. A non-authority
        // caller now reverts with Unauthorized — no more dead-letter writes.
        _mockAuthority(VALIDATOR_ID, AUTHORITY_A);

        vm.expectRevert(ValidatorMetadata.Unauthorized.selector);
        vm.prank(ATTACKER);
        registry.setApproval(VALIDATOR_ID, DELEGATE, true);
    }

    function test_SetApproval_DelegateCannotSubDelegate() public {
        // AUTHORITY_A approves DELEGATE for VALIDATOR_ID.
        _mockAuthority(VALIDATOR_ID, AUTHORITY_A);
        vm.prank(AUTHORITY_A);
        registry.setApproval(VALIDATOR_ID, DELEGATE, true);

        // DELEGATE is not the validator's authority, so their setApproval call
        // is rejected outright by the new authority check.
        vm.expectRevert(ValidatorMetadata.Unauthorized.selector);
        vm.prank(DELEGATE);
        registry.setApproval(VALIDATOR_ID, OTHER_DELEGATE, true);
    }

    function test_SetApproval_NoOpDoesNotEmit() public {
        // All three no-op shapes hit the equality short-circuit and must skip
        // both the SSTORE and the emit:
        //   1. re-granting an already-active approval
        //   2. revoking-never-approved (default-zero storage slot)
        //   3. revoking-already-revoked (slot written true then false)
        // setApproval now requires the caller to be the validator's current
        // authority, so each case uses the authority's prank.

        _mockAuthority(VALIDATOR_ID, AUTHORITY_A);

        // (1) re-granting an already-active approval
        vm.prank(AUTHORITY_A);
        registry.setApproval(VALIDATOR_ID, DELEGATE, true);
        vm.recordLogs();
        vm.prank(AUTHORITY_A);
        registry.setApproval(VALIDATOR_ID, DELEGATE, true);
        assertEq(vm.getRecordedLogs().length, 0, "duplicate grant emitted an event");
        assertTrue(registry.isApproved(VALIDATOR_ID, AUTHORITY_A, DELEGATE));

        // (2) revoking-never-approved — the storage slot is the default false,
        //     so setApproval(_, false) is a no-op without any prior interaction.
        vm.recordLogs();
        vm.prank(AUTHORITY_A);
        registry.setApproval(VALIDATOR_ID, OTHER_DELEGATE, false);
        assertEq(vm.getRecordedLogs().length, 0, "revoking-never-approved emitted an event");
        assertFalse(registry.isApproved(VALIDATOR_ID, AUTHORITY_A, OTHER_DELEGATE));

        // (3) revoking-already-revoked — distinct from (2): the slot was
        //     explicitly written true and then false. The third call (revoking
        //     a slot that already holds false from a prior revoke) must also
        //     be a no-op. Uses a third delegate so its slot is independent of (1).
        address thirdDelegate = address(0xD3);
        vm.startPrank(AUTHORITY_A);
        registry.setApproval(VALIDATOR_ID, thirdDelegate, true);
        registry.setApproval(VALIDATOR_ID, thirdDelegate, false);
        vm.recordLogs();
        registry.setApproval(VALIDATOR_ID, thirdDelegate, false);
        vm.stopPrank();
        assertEq(vm.getRecordedLogs().length, 0, "revoking-already-revoked emitted an event");
        assertFalse(registry.isApproved(VALIDATOR_ID, AUTHORITY_A, thirdDelegate));
    }

    function test_SetApproval_ZeroDelegate_Reverts() public {
        _mockAuthority(VALIDATOR_ID, AUTHORITY_A);

        vm.startPrank(AUTHORITY_A);
        vm.expectRevert(ValidatorMetadata.InvalidDelegate.selector);
        registry.setApproval(VALIDATOR_ID, address(0), true);
        vm.expectRevert(ValidatorMetadata.InvalidDelegate.selector);
        registry.setApproval(VALIDATOR_ID, address(0), false);
        vm.stopPrank();
    }

    function test_SetApproval_SelfDelegate_Reverts() public {
        // An authority approving themselves is meaningless — the write-side modifier
        // already lets them through unconditionally. Reject the call so it can't
        // pollute the approval set or emit a misleading event.
        _mockAuthority(VALIDATOR_ID, AUTHORITY_A);

        vm.startPrank(AUTHORITY_A);
        vm.expectRevert(ValidatorMetadata.InvalidDelegate.selector);
        registry.setApproval(VALIDATOR_ID, AUTHORITY_A, true);
        vm.expectRevert(ValidatorMetadata.InvalidDelegate.selector);
        registry.setApproval(VALIDATOR_ID, AUTHORITY_A, false);
        vm.stopPrank();
    }

    function test_ApprovedDelegate_CanSetMetadata() public {
        _mockAuthority(VALIDATOR_ID, AUTHORITY_A);
        vm.prank(AUTHORITY_A);
        registry.setApproval(VALIDATOR_ID, DELEGATE, true);

        IValidatorMetadata.Metadata memory m = _sampleMetadata();

        vm.expectEmit(true, true, false, true);
        emit MetadataUpdated(VALIDATOR_ID, DELEGATE, m);

        vm.prank(DELEGATE);
        registry.setMetadata(VALIDATOR_ID, m);

        _assertMetadataEq(registry.getMetadata(VALIDATOR_ID), m);
    }

    function test_ApprovedDelegate_CanUpdateMetadataField() public {
        _seedRecord(VALIDATOR_ID, AUTHORITY_A);
        vm.prank(AUTHORITY_A);
        registry.setApproval(VALIDATOR_ID, DELEGATE, true);

        vm.prank(DELEGATE);
        registry.updateMetadataField(VALIDATOR_ID, IValidatorMetadata.Field.WEBSITE, "https://delegate.example");

        assertEq(registry.getMetadata(VALIDATOR_ID).website, "https://delegate.example");
    }

    function test_RevokedDelegate_CannotWrite() public {
        _seedRecord(VALIDATOR_ID, AUTHORITY_A);

        vm.startPrank(AUTHORITY_A);
        registry.setApproval(VALIDATOR_ID, DELEGATE, true);
        registry.setApproval(VALIDATOR_ID, DELEGATE, false);
        vm.stopPrank();

        vm.expectRevert(ValidatorMetadata.Unauthorized.selector);
        vm.prank(DELEGATE);
        registry.updateMetadataField(VALIDATOR_ID, IValidatorMetadata.Field.WEBSITE, "https://nope.example");
    }

    function test_ApprovalsResetOnAuthorityRotation() public {
        // A approves D for V; V's authority then rotates to B. D loses access
        // immediately because the write-check now queries
        // `_approvals[V][B][D]`, which is false.
        _seedRecord(VALIDATOR_ID, AUTHORITY_A);
        vm.prank(AUTHORITY_A);
        registry.setApproval(VALIDATOR_ID, DELEGATE, true);

        _mockAuthority(VALIDATOR_ID, AUTHORITY_B);

        vm.expectRevert(ValidatorMetadata.Unauthorized.selector);
        vm.prank(DELEGATE);
        registry.updateMetadataField(VALIDATOR_ID, IValidatorMetadata.Field.WEBSITE, "https://blocked.example");
    }

    function test_PriorAuthorityApprovalState_DoesNotAffectSuccessor() public {
        // While A is val1's authority, A grants then revokes approval to B (treating
        // B as a delegate). Both writes live at `_approvals[V][A][B]`, which the
        // post-rotation write-check never reads (it queries `_approvals[V][B][...]`).
        // After rotation to B:
        //   - B writes as the new authority — independent of any stored approval
        //     from A's regime.
        //   - A cannot write — A is no longer authority, and `_approvals[V][B][A]`
        //     was never set.

        _mockAuthority(VALIDATOR_ID, AUTHORITY_A);
        vm.startPrank(AUTHORITY_A);
        registry.setApproval(VALIDATOR_ID, AUTHORITY_B, true);
        registry.setApproval(VALIDATOR_ID, AUTHORITY_B, false);
        vm.stopPrank();

        _mockAuthority(VALIDATOR_ID, AUTHORITY_B);

        IValidatorMetadata.Metadata memory m = _sampleMetadata();
        vm.prank(AUTHORITY_B);
        registry.setMetadata(VALIDATOR_ID, m);
        _assertMetadataEq(registry.getMetadata(VALIDATOR_ID), m);

        vm.expectRevert(ValidatorMetadata.Unauthorized.selector);
        vm.prank(AUTHORITY_A);
        registry.updateMetadataField(VALIDATOR_ID, IValidatorMetadata.Field.WEBSITE, "https://nope.example");
    }

    function test_ApprovalIsScopedToSpecificValidator() public {
        // AUTHORITY_A controls v1 and v2. Approving D for v1 must NOT give D
        // access to v2 — the storage key includes validatorId.
        uint64 v1 = 100;
        uint64 v2 = 200;
        _mockAuthority(v1, AUTHORITY_A);
        _mockAuthority(v2, AUTHORITY_A);

        vm.prank(AUTHORITY_A);
        registry.setApproval(v1, DELEGATE, true);

        // D can write for v1.
        IValidatorMetadata.Metadata memory m = _sampleMetadata();
        vm.prank(DELEGATE);
        registry.setMetadata(v1, m);
        assertTrue(registry.hasMetadata(v1));

        // D cannot write for v2 — approval is keyed by validatorId.
        vm.expectRevert(ValidatorMetadata.Unauthorized.selector);
        vm.prank(DELEGATE);
        registry.setMetadata(v2, m);

        // isApproved confirms the scoping.
        assertTrue(registry.isApproved(v1, AUTHORITY_A, DELEGATE));
        assertFalse(registry.isApproved(v2, AUTHORITY_A, DELEGATE));
    }

    function test_SetMetadata_PerValidatorIsolation() public {
        // Same-authority writes to different validatorIds must not bleed into
        // each other's storage slot. Confirms the metadata mapping is keyed by
        // validatorId and not, say, by authority.
        uint64 v1 = 100;
        uint64 v2 = 200;
        _mockAuthority(v1, AUTHORITY_A);
        _mockAuthority(v2, AUTHORITY_A);

        IValidatorMetadata.Metadata memory mV1 = _sampleMetadata();
        mV1.name = "ValidatorOne";
        mV1.website = "https://v1.example";

        IValidatorMetadata.Metadata memory mV2 = _sampleMetadata();
        mV2.name = "ValidatorTwo";
        mV2.website = "https://v2.example";

        vm.startPrank(AUTHORITY_A);
        registry.setMetadata(v1, mV1);
        registry.setMetadata(v2, mV2);
        vm.stopPrank();

        _assertMetadataEq(registry.getMetadata(v1), mV1);
        _assertMetadataEq(registry.getMetadata(v2), mV2);

        // Overwriting v1's full record must not touch v2.
        IValidatorMetadata.Metadata memory mV1Replaced = _sampleMetadata();
        mV1Replaced.name = "ValidatorOneReplaced";
        vm.prank(AUTHORITY_A);
        registry.setMetadata(v1, mV1Replaced);

        _assertMetadataEq(registry.getMetadata(v1), mV1Replaced);
        _assertMetadataEq(registry.getMetadata(v2), mV2);
    }

    function test_TwoDelegatesUnderSameAuthority_CanBothWrite() public {
        // AUTHORITY_A approves both DELEGATE and OTHER_DELEGATE. DELEGATE
        // creates the record; OTHER_DELEGATE updates a field on the same
        // record. Confirms multiple delegates can coexist under one authority
        // and that approvals form a set, not a single-slot pointer.
        _mockAuthority(VALIDATOR_ID, AUTHORITY_A);

        vm.startPrank(AUTHORITY_A);
        registry.setApproval(VALIDATOR_ID, DELEGATE, true);
        registry.setApproval(VALIDATOR_ID, OTHER_DELEGATE, true);
        vm.stopPrank();

        IValidatorMetadata.Metadata memory m = _sampleMetadata();

        vm.prank(DELEGATE);
        registry.setMetadata(VALIDATOR_ID, m);

        vm.prank(OTHER_DELEGATE);
        registry.updateMetadataField(VALIDATOR_ID, IValidatorMetadata.Field.WEBSITE, "https://updated-by-d2.example");

        IValidatorMetadata.Metadata memory stored = registry.getMetadata(VALIDATOR_ID);
        assertEq(stored.website, "https://updated-by-d2.example", "D2's field update did not land");
        assertEq(stored.name, m.name, "D1's other fields should be preserved");
        assertEq(stored.description, m.description);
        assertEq(stored.logo, m.logo);
        assertEq(stored.socials, m.socials);
        assertEq(stored.additionalInfo, m.additionalInfo);
    }

    // ─── deleteMetadata ──────────────────────────────────────────────────

    /// Mirror of ValidatorMetadata.MetadataDeleted so vm.expectEmit can resolve topics.
    event MetadataDeleted(uint64 indexed validatorId, address indexed authority);

    function test_DeleteMetadata_AsAuthority_RemovesRecordAndEmits() public {
        _seedRecord(VALIDATOR_ID, AUTHORITY_A);

        vm.expectEmit(true, true, false, true);
        emit MetadataDeleted(VALIDATOR_ID, AUTHORITY_A);

        vm.prank(AUTHORITY_A);
        registry.deleteMetadata(VALIDATOR_ID);

        assertFalse(registry.hasMetadata(VALIDATOR_ID));
        IValidatorMetadata.Metadata memory stored = registry.getMetadata(VALIDATOR_ID);
        assertEq(stored.name, "");
        assertEq(stored.website, "");
        assertEq(stored.description, "");
        assertEq(stored.logo, "");
        assertEq(stored.socials, "");
        assertEq(stored.additionalInfo, "");
    }

    function test_DeleteMetadata_AsApprovedDelegate_Succeeds() public {
        _seedRecord(VALIDATOR_ID, AUTHORITY_A);
        vm.prank(AUTHORITY_A);
        registry.setApproval(VALIDATOR_ID, DELEGATE, true);

        vm.expectEmit(true, true, false, true);
        emit MetadataDeleted(VALIDATOR_ID, DELEGATE);

        vm.prank(DELEGATE);
        registry.deleteMetadata(VALIDATOR_ID);

        assertFalse(registry.hasMetadata(VALIDATOR_ID));
    }

    function test_DeleteMetadata_AsNonAuthority_Reverts() public {
        _seedRecord(VALIDATOR_ID, AUTHORITY_A);

        vm.expectRevert(ValidatorMetadata.Unauthorized.selector);
        vm.prank(ATTACKER);
        registry.deleteMetadata(VALIDATOR_ID);

        // Record is still there.
        assertTrue(registry.hasMetadata(VALIDATOR_ID));
    }

    function test_DeleteMetadata_NoPriorRecord_Reverts() public {
        _mockAuthority(VALIDATOR_ID, AUTHORITY_A);

        vm.expectRevert(ValidatorMetadata.ValidatorMetadataEmpty.selector);
        vm.prank(AUTHORITY_A);
        registry.deleteMetadata(VALIDATOR_ID);
    }

    function test_DeleteMetadata_ThenSetMetadata_RecreatesRecord() public {
        _seedRecord(VALIDATOR_ID, AUTHORITY_A);

        vm.startPrank(AUTHORITY_A);
        registry.deleteMetadata(VALIDATOR_ID);
        // After deletion, setMetadata works (creates a fresh record); a follow-up
        // updateMetadataField would require this fresh setMetadata.
        IValidatorMetadata.Metadata memory m = _sampleMetadata();
        m.name = "Reborn";
        registry.setMetadata(VALIDATOR_ID, m);
        vm.stopPrank();

        assertTrue(registry.hasMetadata(VALIDATOR_ID));
        assertEq(registry.getMetadata(VALIDATOR_ID).name, "Reborn");
    }

    function test_DeleteMetadata_AfterAuthorityRotation_OldAuthorityCannotDelete() public {
        _seedRecord(VALIDATOR_ID, AUTHORITY_A);

        _mockAuthority(VALIDATOR_ID, AUTHORITY_B);

        vm.expectRevert(ValidatorMetadata.Unauthorized.selector);
        vm.prank(AUTHORITY_A);
        registry.deleteMetadata(VALIDATOR_ID);

        // New authority can delete.
        vm.prank(AUTHORITY_B);
        registry.deleteMetadata(VALIDATOR_ID);
        assertFalse(registry.hasMetadata(VALIDATOR_ID));
    }

    // ─── Fuzz ────────────────────────────────────────────────────────────

    function testFuzz_SetMetadata_AsAuthority_Persists(
        uint64 validatorId,
        address authority,
        string memory name,
        string memory website,
        string memory socials
    ) public {
        vm.assume(authority != address(0));
        vm.assume(bytes(name).length > 0);

        _mockAuthority(validatorId, authority);

        IValidatorMetadata.Metadata memory m = IValidatorMetadata.Metadata({
            name: name, website: website, description: "", logo: "", socials: socials, additionalInfo: ""
        });

        vm.prank(authority);
        registry.setMetadata(validatorId, m);

        _assertMetadataEq(registry.getMetadata(validatorId), m);
        assertTrue(registry.hasMetadata(validatorId));
        assertEq(registry.getValidatorName(validatorId), name);
    }

    function testFuzz_UpdateMetadataField_AdditionalInfo_StoredVerbatim(string memory value) public {
        _seedRecord(VALIDATOR_ID, AUTHORITY_A);

        vm.prank(AUTHORITY_A);
        registry.updateMetadataField(VALIDATOR_ID, IValidatorMetadata.Field.ADDITIONAL_INFO, value);

        assertEq(registry.getMetadata(VALIDATOR_ID).additionalInfo, value);
    }

    function testFuzz_UnauthorizedCaller_CannotSetMetadata(uint64 validatorId, address authority, address caller)
        public
    {
        vm.assume(authority != address(0));
        vm.assume(caller != address(0));
        vm.assume(caller != authority);
        // After the delegation PR, an "unauthorized" caller is one that is neither the
        // current authority nor an approved delegate. Filter out any approved-delegate
        // case so a future setUp that seeds approvals can't silently weaken this test.
        vm.assume(!registry.isApproved(validatorId, authority, caller));

        _mockAuthority(validatorId, authority);

        vm.expectRevert(ValidatorMetadata.Unauthorized.selector);
        vm.prank(caller);
        registry.setMetadata(validatorId, _sampleMetadata());
    }
}
