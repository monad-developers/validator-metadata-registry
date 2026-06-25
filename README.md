# MRC-13 Reference Implementation

A reference implementation of [MRC-13: Validator Metadata Registry](https://github.com/monad-crypto/MIPs/blob/main/MRCs/MRC-13.md) — a permissionless on-chain registry where Monad validators publish their own human-readable metadata (name, logo, website, socials, etc.) keyed to their `validatorId`. Authority to write is anchored to the validator's authority address as reported by the staking precompile.

This is **a** reference implementation, not *the* canonical deployment. MRC-13 deliberately doesn't anoint a canonical implementation or address; integrators and validators choose which conformant deployment(s) to use. Discussion lives in the [Monad forum thread](https://forum.monad.xyz/t/validator-metadata-registry/497).

## Repository layout

```
src/
  ValidatorMetadata.sol           — the registry contract
  interfaces/
    IValidatorMetadata.sol        — the MRC-13 interface
    IMonadStaking.sol             — minimal interface to the staking precompile
test/
  ValidatorMetadata.t.sol         — 31 tests covering every MRC-13 test case
script/
  ValidatorMetadata.s.sol         — deployment script (CREATE2, deterministic)
```

## Implementation choices

This contract does the minimum the standard requires and nothing more.

- **Authority + delegated writers.** The validator's authority address (resolved live from the staking precompile) can always write metadata. The authority can also call `setApproval(validatorId, delegate, approved)` to grant or revoke metadata-write access for that specific validator — useful for hot/cold key separation or ops-team operators. Approvals are keyed by `(validatorId, authority, delegate)`: scoped to one validator (approving a delegate for v1 doesn't grant access to v2), and a staking-precompile authority rotation automatically retires the prior authority's delegates because the write-check's key (which includes the *current* authority) no longer matches. `setApproval` itself rejects calls from any address that isn't the validator's current authority — no dead-letter writes — which also makes sub-delegation structurally impossible. These functions (`setApproval`, `isApproved`, `MetadataApprovalSet`) are *not* part of `IValidatorMetadata` — they're this implementation's choice under the MRC's "implementations MAY accept additional callers" clause.
- **Live authority resolution.** Every write calls `IMonadStaking(STAKING_PRECOMPILE).getValidator(id).authority` — no caching — so an authority rotation in the staking precompile takes effect immediately, with no registry-side action.
- **Custom errors.** `Unauthorized()`, `ValidatorNameEmpty()`, `ValidatorMetadataEmpty()` instead of revert strings.
- **No JSON validation on-chain.** `socials` and `additionalInfo` are stored verbatim; the JSON-by-convention rule from MRC-13 is enforced socially by writers and readers, not by the contract.
- **No upgrade path.** No proxy, no admin, no migration. A schema change is a new deployment at a new address.

`pragma solidity 0.8.28`, `evm_version = "prague"`, optimizer on (`runs = 200`), `bytecode_hash = "none"` — see `foundry.toml`.

## Toolchain

The project targets [monad-foundry](https://github.com/category-labs/foundry/tree/monad), a fork of Foundry with Monad-native execution and staking-precompile support:

```sh
curl -L https://foundry.category.xyz | bash
foundryup -n monad
```

Vanilla Foundry works too for build and test — the test suite stubs the staking precompile via `vm.mockCall`, so no Monad-specific runtime behaviour is needed to run it.

## Build & test

```sh
forge build
forge test
```

The 31-test suite covers every test case in MRC-13 §Test Cases, plus per-`Field` branch coverage on `updateMetadataField`, event-payload assertions on every successful write, authority rotation in both directions, and three fuzz tests at 1000 runs each (see `[fuzz] runs = 1000` in `foundry.toml`).

## Deploy

```sh
forge script script/ValidatorMetadata.s.sol \
  --rpc-url "$MONAD_RPC_URL" \
  --private-key "$PRIVATE_KEY" \
  --broadcast
```

The script uses CREATE2 via the standard deterministic-deployer factory at `0x4e59b44847b379578588920cA78FbF26c0B4956C`, with `SALT = keccak256("MRC-13:ValidatorMetadata:v1")`. As long as the factory is present on the target chain, the resulting address is identical on every Monad network and independent of which EOA broadcasts the transaction. To preview the address without sending a transaction, drop the `--broadcast` flag — the script logs both the predicted address and the salt. If a future bytecode change should land at a fresh address (e.g. a non-backward-compatible storage layout), bump the salt's version suffix.

If the deterministic-deployer factory isn't deployed on the target chain, the script will fail. It can be put in place by anyone via Nick's method — see [the deterministic-deployment-proxy repo](https://github.com/Arachnid/deterministic-deployment-proxy) for the presigned transaction.

## License

MIT — see the SPDX headers on the source files.
