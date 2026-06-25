- **Topic:** Reference implementation: ValidatorMetadata (companion to the existing testnet deployment)
- **Status:** Source published, deployment pending

---

## **What this is**

A reference implementation of MRC-13 in Solidity, with tests and a deterministic deployment script. Intended as a **companion** to the implementation already live at `0x3f084CAF88F8894f6c83cf40b9cA7e792D9F221B` on testnet — MRC-13 deliberately doesn't anoint any single deployment as canonical, and more independent implementations help the standard get exercised across different design assumptions.

Source is published; no on-chain deployment yet. The deploy script targets the standard deterministic-deployer factory at `0x4e59b44847b379578588920cA78FbF26c0B4956C`, so once broadcast it will land at the same address on every chain where the factory is present. With the current bytecode and `SALT = keccak256("MRC-13:ValidatorMetadata:v1")`, the predicted address is `0x610AAca1B07DCAe88602Cc836bB58a437A5791F3`.

Repo: *[link to repo]*

## **Notable design choices**

Documenting the bits where the spec leaves room and this implementation made a specific call.

**Delegation keyed by `(validatorId, authority, delegate)`.** The MRC's "implementations MAY accept additional callers" clause is implemented as per-(validator, authority) approvals. Three properties flow from that key shape:

- Approvals are scoped to one validator — approving a delegate for v1 doesn't grant access to v2.
- A staking-precompile authority rotation implicitly retires the prior authority's delegates; the write-check's lookup key changes.
- `setApproval` itself rejects calls from any address that isn't the validator's current authority, so sub-delegation is structurally impossible.

This is a more restrictive shape than the alternatives I considered (per-authority only, or per-(authority,delegate) without validatorId). The trade-off is operational ergonomics — an authority running N validators needs N `setApproval` calls to grant the same delegate access across all of them — in exchange for tighter blast-radius semantics around rotation and per-validator policy.

**Custom errors over revert strings.** `Unauthorized()`, `ValidatorNameEmpty()`, `ValidatorMetadataEmpty()`, `InvalidDelegate()`. Smaller calldata on revert and clearer indexer-side decoding.

**Live authority resolution on every write.** No caching anywhere — the staking-precompile call happens on the write transaction, so a rotation takes effect immediately with no registry-side action.

**`deleteMetadata` is included.** Symmetric with `setMetadata`: same authorization, opposite direction. Useful for validators who want to retire their record without touching the staking precompile.

**Deterministic deployment via the standard CREATE2 factory.** Salt versioning policy: bump `v1` → `v2` in the salt string when bytecode changes in a way that should land at a fresh address (e.g. a non-backward-compatible storage layout).

**No upgrade path.** No proxy, no admin, no migration. A schema change is a new deployment at a new address — integrators track which address they consider current.

## **Test coverage**

53 tests, ~80 ms runtime, including:

- Every test case from MRC-13 § Test Cases.
- Per-`Field` branch coverage on `updateMetadataField`.
- Event-payload assertions on every successful write.
- Authority rotation in both directions.
- Three fuzz tests at 1000 runs each (set-metadata persistence with arbitrary inputs, `additionalInfo` verbatim storage, non-authority rejection).
- The delegation surface: zero/self-delegate rejection, no-op short-circuit in three distinct shapes (re-granting, revoking-never-approved, revoking-already-revoked), per-validator scoping, rotation invalidation, post-rotation old-authority-cannot-write.

## **What's next**

- Plan to deploy this on Monad testnet shortly. Will post the on-chain address back here once it lands; given the deterministic salt the actual transaction is purely a confirmation of the predicted address.
- Open to feedback on the delegation model — the per-validator scoping is a deliberate choice but not the only defensible one, and reactions are welcome.
- Tracking @ColinkaMalinka's "observed validator status" direction with interest — that's a consumer-side, off-chain layer on top of the registry, which feels like the right separation.

## **Repository**

*[link to repo]*
