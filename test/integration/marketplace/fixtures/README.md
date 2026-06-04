# Credit attestation test fixtures

`credit_attestation.json` is a signed EIP-712 `CreditAttestation` consumed by
`CreditAttestationIntegration.t.sol` to prove the off-chain → on-chain flow.

The committed file is a **bootstrap** fixture signed by a well-known test key so
CI is green without the off-chain service. To perform the true **API ↔
contract** validation, regenerate it from the local moonwell-ai Worker and
overwrite this file.

## Domain the signature commits to (must match the contract byte-for-byte)

- EIP-712 domain: `name="MoonwellCreditMarketplace"`, `version="1"`,
  `chainId=8453`, `verifyingContract=0x00000000000000000000000000000000C0FFEE01`
  (the deterministic address the test deploys `CreditTierRegistry` to via
  `deployCodeTo`; if you change `REGISTRY_ADDR` in the test, regenerate).
- Type:
  `CreditAttestation(address subject,uint16 tier,uint16 score,bytes32 reportHash,uint64 issuedAt,uint64 validUntil)`.
- Signer (attestor) = anvil account #0,
  `0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266` (key `0xac0974…ff80`). **TEST
  ONLY — never a real bureau key.**
- `subject` = anvil account #2, `0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC`
  (the test signs the borrower Request with its key).
- `reportHash = keccak256(abi.encode(address subject, uint16 score, uint16 tier, uint32 windowDays, uint64 generatedAt))`.
- Validity window is intentionally **wide** here (`issuedAt=1700000000`,
  `validUntil=2000000000`) so the fixture is valid at the Base fork's latest
  block without time-warping. Production attestations use a short TTL (minutes).

## Regenerate from the moonwell-ai API

Run the Worker locally with the dev bypass (`X402_DISABLED=true`), the anvil #0
signing key, `CREDIT_MARKETPLACE_ADDRESS=0x…C0FFEE01`,
`ATTESTATION_CHAIN_ID=8453`, then:

```
curl "http://localhost:8787/v1/credit/attestation/0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC?verifyingContract=0x00000000000000000000000000000000C0FFEE01&chainId=8453"
```

Write `data.attestation` + `data.signature` into this file's keys
(`subject, tier, score, reportHash, issuedAt, validUntil, signature`). If any
domain field, the struct field order, the signer, or the subject changes, the
on-chain digest changes and the signature stops verifying.
