# MIP-M18: Multichain Governor Migration

## Overview

Moonwell is shifting to a multichain governance model. This proposal aims to
migrate the protocol to the new governor system contracts. This proposal will
deploy the new governor contracts to the Moonwell mainnet and base. After
deployment, the proposal will transfer ownership of the Moonwell contracts from
the current governor to the new governor.

## Specification

- Proposal MIP-M18a will deploy the new governor contract to Moonbeam mainnet.
- Proposal MIP-M18b will deploy the Vote Collection contract to Moonwell base.
- Proposal MIP-M18c will initialize the new MultichainGovernor contract on
  Moonbeam.
- Proposal MIP-M18d will transfer ownership of the Moonwell contracts to the new
  governor on both Moonbeam and Base.
- Proposal MIP-M18e will accept transferring ownership of the Moonwell contracts
  to the new governor on Moonbeam and Base.

### Motivation

In order to allow WELL token holders on all chains to participate in governance,
the xWELL token has been deployed to Base and Moonbeam. This means, that as an
xWELL holder on Base, you can vote on proposals on Moonbeam and vice versa.
However, the current governor contract is only deployed to Moonbeam and only
supports WELL, stkWELL and vesting WELL for participation in governance.

### Simulation

To simulate proposal executions, one must either create an Anvil fork of both
Moonbeam and Base or utilize a testnet environment. Note that Proposal MIP-M18e
may not function correctly in a locally forked setting since it depends on
broadcasting MIP-M18d transactions beforehand. Consequently, the only reliable
method to simulate the execution of MIP-M18e is through testnet deployment.

1. `anvil --fork-url "https://mainnet.base.org"`
2. `anvil --fork-url https://rpc.api.moonbeam.network --port 8555` in a separate
   terminal
3. Set the following environment variables:

```bash
BASE_RPC_URL=http://127.0.0.1:8545 MOONBEAM_RPC_URL=http://127.0.0.1:8555
```

```bash
DO_DEPLOY=true DO_VALIDATE=true DO_PRINT=true forge script
src/proposals/mips/mip-m18/mip-m18a.sol:mipm18a --broadcast --slow --fork-url
$MOONBEAM_RPC_URL -g 200
```

5. Copy new MULTICHAIN_GOVERNOR_PROXY and MULTICHAIN_GOVERNOR_IMPL from the
   output of the previous command and add them to Addresses.json.

6. Run

```bash
DO_DEPLOY=true DO_VALIDATE=true DO_PRINT=true forge script
src/proposals/mips/mip-m18/mip-m18b.sol:mipm18b --broadcast --slow --fork-url
$BASE_RPC_URL -g 200
```

7. Copy the new deployed addresses ECOSYSTEM_RESERVE_PROXY,
   ECOSYSTEM_RESERVE_IMPL, ECOSYSTEM_RESERVE_CONTROLLER, stkWELL_PROXY,
   stkWELL_IMPL, VOTE_COLLECTION_PROXY, VOTE_COLLECTION_IMPL and add them to
   Addresses.json.

8. Run

```bash
DO_VALIDATE=true DO_DEPLOY=true DO_AFTER_DEPLOY=true DO_PRINT=true
forge script src/proposals/mips/mip-m18/mip-m18c.sol:mipm18c --slow --broadcast
--fork-url $MOONBEAM_BASE_URL -g 200
```

9. Run

```bash
DO_VALIDATE=true DO_DEPLOY=true DO_AFTER_DEPLOY=true DO_PRINT=true
forge script src/proposals/mips/mip-m18/mip-m18d.sol:mipm18d
--fork-url $MOONBEAM_BASE_URL -g 200
```
