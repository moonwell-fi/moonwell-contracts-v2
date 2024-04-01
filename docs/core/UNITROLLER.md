# Unitroller

## Overview

The `Unitroller` contract forms the core part of the Comptroller system. It
provides a flexible storage contract that delegates business logic to an
externally set Comptroller Implementation. This is part of an upgrade pattern
known as "Universal Upgradeable Proxy".

This contract interacts with the following other contracts:

- **ErrorReporter**: A contract used for tracking error codes and failure
  information.
- **ComptrollerStorage**: A storage contract that stores the admin addresses and
  comptroller implementations.

## Contract Architecture

### State Variables

- `admin`: The address of the admin. This address has administrative privileges
  over the contract.
- `pendingAdmin`: The address set to become the new admin.
- `comptrollerImplementation`: The address of the current comptroller
  implementation.
- `pendingComptrollerImplementation`: The address set to become the new
  comptroller implementation.

### Events

- **NewPendingImplementation**: Emitted when `pendingComptrollerImplementation`
  is updated.
- **NewImplementation**: Emitted when `comptrollerImplementation` is updated.
- **NewPendingAdmin**: Emitted when `pendingAdmin` is updated.
- **NewAdmin**: Emitted when `admin` is updated.

### Constructor

- The constructor is called when the contract is deployed and sets the `admin`
  to the address that deployed the contract.

### Functions

#### \_setPendingImplementation()

- Only callable by the admin.
- Sets a new pending comptroller implementation address.
- Emits a `NewPendingImplementation` event.

#### \_acceptImplementation()

- Only callable by the `pendingComptrollerImplementation` address.
- Accepts the role as the new comptroller implementation.
- Emits a `NewImplementation` and a `NewPendingImplementation` event.

#### \_setPendingAdmin()

- Only callable by the admin.
- Sets a new pending admin address.
- Emits a `NewPendingAdmin` event.

#### \_acceptAdmin()

- Only callable by the `pendingAdmin` address.
- Accepts the role as the new admin.
- Emits a `NewAdmin` and a `NewPendingAdmin` event.

#### Fallback function

- The fallback function delegates any calls it cannot handle to the
  `comptrollerImplementation`. This allows for flexible upgrades of the
  comptroller functionality.

## Edge Cases & Considerations

- The fallback function delegates execution to an implementation contract. If
  the delegate call fails, it will revert and bubble up the error.
- There are no checks if the addresses set as pending are contracts that can
  execute the required functions. Misconfiguration could lead to failed
  transactions or locked funds.
- The `admin` has full control over changing the `pendingAdmin` and
  `pendingComptrollerImplementation`. Misuse or loss of the `admin` account
  could pose a risk to the contract.
- When accepting to be the new `admin` or `comptrollerImplementation`, there are
  no checks whether these contracts have the expected interface or not. A
  contract with a wrong interface could cause the system to be stuck in an
  unrecoverable state.
