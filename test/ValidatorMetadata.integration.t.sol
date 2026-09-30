// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {MonadTest} from "monad-std/MonadTest.sol";
import {ValidatorMetadata} from "src/ValidatorMetadata.sol";
import {IValidatorMetadata} from "src/interfaces/IValidatorMetadata.sol";
import {IMonadStaking} from "src/interfaces/IMonadStaking.sol";
import {AddValidatorFixture as F} from "test/fixtures/AddValidatorFixture.sol";

/// Integration tests against the real staking precompile. Requires a Monad-aware forge
/// (>= 1.8.0) run with `--network monad`; skipped otherwise.
///
/// Unlike the unit tests, nothing here is mocked: a validator is registered via `addValidator`
/// with real secp/BLS signatures, so these tests catch any drift between the precompile's
/// `getValidator` return layout and what `ValidatorMetadata` decodes.
contract ValidatorMetadataIntegrationTest is Test, MonadTest {
    ValidatorMetadata internal registry;
    uint64 internal validatorId;

    address internal constant REGISTRAR = address(0x5E9);
    address internal constant ATTACKER = address(0xDEAD);
    address internal constant DELEGATE = address(0xD1);

    function setUp() public {
        // Skip when the staking precompile is absent (plain `forge test` without `--network monad`).
        // A call to a codeless address succeeds with empty return data, so check the length too.
        // CI sets REQUIRE_MONAD_PRECOMPILE so a misconfigured runner fails loudly instead of skipping.
        (bool ok, bytes memory ret) = STAKING_ADDRESS.call(abi.encodeCall(IMonadStaking.getEpoch, ()));
        bool precompileMissing = !ok || ret.length == 0;
        if (precompileMissing && vm.envOr("REQUIRE_MONAD_PRECOMPILE", false)) {
            revert("staking precompile missing: run with --network monad");
        }
        vm.skip(precompileMissing);

        registry = new ValidatorMetadata();

        vm.deal(REGISTRAR, F.AMOUNT);
        vm.prank(REGISTRAR);
        validatorId = staking.addValidator{value: F.AMOUNT}(F.PAYLOAD, F.SECP_SIG, F.BLS_SIG);
    }

    // ─── Helpers ─────────────────────────────────────────────────────────

    /// Destructuring the 12-value return requires `via_ir = true` (set in foundry.toml).
    function _validatorHead(uint64 id) internal returns (address authAddress, uint64 flags, uint256 stake) {
        (authAddress, flags, stake,,,,,,,,,) = IMonadStaking(STAKING_ADDRESS).getValidator(id);
    }

    function _sampleMetadata() internal pure returns (IValidatorMetadata.Metadata memory) {
        return IValidatorMetadata.Metadata({
            name: "IntegrationValidator",
            website: "https://example.com",
            description: "Registered via the real staking precompile",
            logo: "",
            socials: "",
            additionalInfo: ""
        });
    }

    // ─── Precompile sanity ───────────────────────────────────────────────

    function test_AddValidator_RegistersWithFixtureAuthority() public {
        (address authAddress,, uint256 stake) = _validatorHead(validatorId);
        assertEq(authAddress, F.AUTH_ADDRESS, "authAddress");
        assertEq(stake, F.AMOUNT, "stake");
    }

    function test_AddValidator_UnknownIdHasZeroAuthority() public {
        (address authAddress,,) = _validatorHead(validatorId + 1_000);
        assertEq(authAddress, address(0));
    }

    // ─── setMetadata against the real authority ──────────────────────────

    function test_SetMetadata_AsRealAuthority_Succeeds() public {
        vm.prank(F.AUTH_ADDRESS);
        registry.setMetadata(validatorId, _sampleMetadata());

        assertEq(registry.getValidatorName(validatorId), "IntegrationValidator");
    }

    function test_SetMetadata_AsNonAuthority_Reverts() public {
        vm.expectRevert(ValidatorMetadata.Unauthorized.selector);
        vm.prank(ATTACKER);
        registry.setMetadata(validatorId, _sampleMetadata());
    }

    function test_SetMetadata_UnknownValidator_Reverts() public {
        // Precompile returns address(0) for an unregistered id; no caller can match it.
        vm.expectRevert(ValidatorMetadata.Unauthorized.selector);
        vm.prank(F.AUTH_ADDRESS);
        registry.setMetadata(validatorId + 1_000, _sampleMetadata());
    }

    // ─── setApproval / delegate writes ───────────────────────────────────

    function test_SetApproval_ThenDelegateCanWrite() public {
        vm.prank(F.AUTH_ADDRESS);
        registry.setApproval(validatorId, DELEGATE, true);

        vm.prank(DELEGATE);
        registry.setMetadata(validatorId, _sampleMetadata());

        assertEq(registry.getValidatorName(validatorId), "IntegrationValidator");
    }

    function test_SetApproval_AsNonAuthority_Reverts() public {
        vm.expectRevert(ValidatorMetadata.Unauthorized.selector);
        vm.prank(ATTACKER);
        registry.setApproval(validatorId, DELEGATE, true);
    }
}
