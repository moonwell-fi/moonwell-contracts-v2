# MultiRewardDistributor

The MultiRewardDistributor contract is responsible for distributing rewards to users for interacting with the protocol. The logic for this contract was inspired by the flywheel logic in the Comptroller. The MultiRewardDistributor allows for distributions of multiple token types per MToken. This means that a user could mint as an example mUSDbC, and then receive rewards in WELL, USDC and WETH.


## Upgradability

The MultiRewardDistributor is an upgradeable contract. This means it cannot have constant values or use a constructor to set values. Instead, it utilizes a constructor which disables the initialize function. The initialize function can be called by a proxy contract that uses MultiRewardDistributor as its logic contract. In the initialize function, important state variables Comptroller, Pause Guardian and Emission Cap are set 

## Comptroller Admin Actions

The Admin of the Comptroller has the ability to call several state changing functions on MultiRewardDistributor.

The function `_setEmissionCap` sets the cap on emissions for all reward configurations. This does not apply retroactively to configurations that were created before the cap was set.

The function `_setPauseGuardian` sets the pause guardian for the MultiRewardDistributor.

Function `_rescueFunds` allows sending funds in the contract to the Comptroller's Admin.

Function `_addEmissionConfig` allows adding an additional reward stream to an MToken. Rewards can be provided for borrowing, lending, or both, as long as the reward speeds are less than the emission cap.

## Reward Streams

Each reward stream has an owner. This owner is allowed to update the supply and borrow reward speeds, the reward end time, and the owner.

## Pausing

The contract can be paused by both the Comptroller Admin and the Pause Guardian. Pausing the contract does not stop users from interacting with the contract, it just stops tokens from being transferred out of the contract. Rewards accrue normally while the contract is paused. Only the Comptroller's Admin can unpause the contract.

## Reward Claiming

Rewards can only be claimed by calls from the Comptroller or the Comptroller's Admin. In order to claim rewards, users must call the `claimReward` function on the Comptroller.
