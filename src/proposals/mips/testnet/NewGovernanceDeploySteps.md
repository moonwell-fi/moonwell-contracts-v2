# New Governance Deploy Steps

## Today: Clean up the house

### Proposal 1: Move moonbase lending system ownership to Artemis

### Proposal 2 - current multichain governor:

- Move temporal governor ownership back to artemis
- Move bridge adapter ownership back to artemis
- Move xwell ownership back to artemis
- Move distributor ownership back to artemis
- Remove old governor as a trusted sender on temporal governor

### Proposal 3 - old multichain governor:

- Create proposal to change voting period to 1 minute and cross chain period to
  21 minutes on old governor

### Proposal 19

Execute proposal 19 to deploy the unwrapper adapter

## Tuesday night

### Proposal 4

- Execute proposal to hand off proxy admin ownership from old governor to the
  current governor

### Proposal 5

- Create a governance proposal to transfer proxy admin ownership from the
  current governor to the timelock tomorrow

## Wednesday: Deploy proposal 18

- Deploy the new governor (MIP 18 A, B and C)
- Change proposal D to fix the addresses
- Change proposal E to fix the addresses, remove the old
- Proposal to update the wormhole bridge adapter to use to use the unwrapper
  adapter on Moonbase
- Change addresses on Address.json

## Thursday

- Execute the proposal 2 to change voting period to 1 minute and cross chain
  period to 21 minutes
