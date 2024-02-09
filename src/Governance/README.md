# Slither

## MultichainGovernor/MultichainVoteCollection.sol

### Command

```
slither src/Governance/MultichainGovernor/MultichainVoteCollection.sol --solc-remaps "@protocol=./src @openzeppelin-contracts-upgradeable=./lib/openzeppelin-contracts-upgradeable @openzeppelin-contracts=./lib/openzeppelin-contracts @zelt=./lib/zelt @zelt-src=./lib/zelt/src"
```

### Output

```
Compilation warnings/errors on src/Governance/MultichainGovernor/MultichainVoteCollection.sol:
Warning: SPDX license identifier not provided in source file. Before publishing, consider adding a comment containing "SPDX-License-Identifier: <SPDX-License>" to each source file. Use "SPDX-License-Identifier: UNLICENSED" for non-open-source code. Please see https://spdx.org for more information.
--> src/Governance/MultichainGovernor/MultichainVoteCollection.sol

Warning: SPDX license identifier not provided in source file. Before publishing, consider adding a comment containing "SPDX-License-Identifier: <SPDX-License>" to each source file. Use "SPDX-License-Identifier: UNLICENSED" for non-open-source code. Please see https://spdx.org for more information.
--> ./src/Governance/MultichainGovernor/Constants.sol

Warning: SPDX license identifier not provided in source file. Before publishing, consider adding a comment containing "SPDX-License-Identifier: <SPDX-License>" to each source file. Use "SPDX-License-Identifier: UNLICENSED" for non-open-source code. Please see https://spdx.org for more information.
--> ./src/Governance/MultichainGovernor/IMultichainVoteCollection.sol

Warning: SPDX license identifier not provided in source file. Before publishing, consider adding a comment containing "SPDX-License-Identifier: <SPDX-License>" to each source file. Use "SPDX-License-Identifier: UNLICENSED" for non-open-source code. Please see https://spdx.org for more information.
--> ./src/Governance/MultichainGovernor/SnapshotInterface.sol

Warning: SPDX license identifier not provided in source file. Before publishing, consider adding a comment containing "SPDX-License-Identifier: <SPDX-License>" to each source file. Use "SPDX-License-Identifier: UNLICENSED" for non-open-source code. Please see https://spdx.org for more information.
--> ./src/wormhole/WormholeBridgeBase.sol

Warning: SPDX license identifier not provided in source file. Before publishing, consider adding a comment containing "SPDX-License-Identifier: <SPDX-License>" to each source file. Use "SPDX-License-Identifier: UNLICENSED" for non-open-source code. Please see https://spdx.org for more information.
--> ./src/xWELL/xWELL.sol

Warning: SPDX license identifier not provided in source file. Before publishing, consider adding a comment containing "SPDX-License-Identifier: <SPDX-License>" to each source file. Use "SPDX-License-Identifier: UNLICENSED" for non-open-source code. Please see https://spdx.org for more information.
--> ./src/xWELL/ConfigurablePause.sol

Warning: SPDX license identifier not provided in source file. Before publishing, consider adding a comment containing "SPDX-License-Identifier: <SPDX-License>" to each source file. Use "SPDX-License-Identifier: UNLICENSED" for non-open-source code. Please see https://spdx.org for more information.
--> ./src/xWELL/ConfigurablePauseGuardian.sol

Warning: SPDX license identifier not provided in source file. Before publishing, consider adding a comment containing "SPDX-License-Identifier: <SPDX-License>" to each source file. Use "SPDX-License-Identifier: UNLICENSED" for non-open-source code. Please see https://spdx.org for more information.
--> ./src/xWELL/MintLimits.sol

Warning: SPDX license identifier not provided in source file. Before publishing, consider adding a comment containing "SPDX-License-Identifier: <SPDX-License>" to each source file. Use "SPDX-License-Identifier: UNLICENSED" for non-open-source code. Please see https://spdx.org for more information.
--> ./src/xWELL/interfaces/IXERC20.sol

Warning: SPDX license identifier not provided in source file. Before publishing, consider adding a comment containing "SPDX-License-Identifier: <SPDX-License>" to each source file. Use "SPDX-License-Identifier: UNLICENSED" for non-open-source code. Please see https://spdx.org for more information.
--> ./src/xWELL/xERC20.sol

Warning: SPDX license identifier not provided in source file. Before publishing, consider adding a comment containing "SPDX-License-Identifier: <SPDX-License>" to each source file. Use "SPDX-License-Identifier: UNLICENSED" for non-open-source code. Please see https://spdx.org for more information.
--> ./lib/zelt/src/lib/RateLimitMidpointCommonLibrary.sol

Warning: SPDX license identifier not provided in source file. Before publishing, consider adding a comment containing "SPDX-License-Identifier: <SPDX-License>" to each source file. Use "SPDX-License-Identifier: UNLICENSED" for non-open-source code. Please see https://spdx.org for more information.
--> ./lib/zelt/src/lib/RateLimitedMidpointLibrary.sol

Warning: SPDX license identifier not provided in source file. Before publishing, consider adding a comment containing "SPDX-License-Identifier: <SPDX-License>" to each source file. Use "SPDX-License-Identifier: UNLICENSED" for non-open-source code. Please see https://spdx.org for more information.
--> ./lib/zelt/src/util/Math.sol

Warning: Contract code size is 36043 bytes and exceeds 24576 bytes (a limit introduced in Spurious Dragon). This contract may not be deployable on Mainnet. Consider enabling the optimizer (with a low "runs" value!), turning off revert strings, or using libraries.
  --> ./src/xWELL/xWELL.sol:15:1:
   |
15 | contract xWELL is
   | ^ (Relevant source part starts here and spans across multiple lines).

INFO:Detectors:
WormholeBridgeBase._bridgeOutAll(bytes) (src/wormhole/WormholeBridgeBase.sol#279-324) sends eth to arbitrary user
	Dangerous calls:
	- (success) = msg.sender.call{value: totalRefundAmount}() (src/wormhole/WormholeBridgeBase.sol#321)
Reference: https://github.com/crytic/slither/wiki/Detector-Documentation#functions-that-send-ether-to-arbitrary-destinations
INFO:Detectors:
xWELL.CLOCK_MODE() (src/xWELL/xWELL.sol#90-95) uses a dangerous strict equality:
	- require(bool,string)(clock() == uint48(block.timestamp),Incorrect clock) (src/xWELL/xWELL.sol#92)
ConfigurablePause.paused() (src/xWELL/ConfigurablePause.sol#41-46) uses a dangerous strict equality:
	- pauseStartTime == 0 (src/xWELL/ConfigurablePause.sol#42-45)
Reference: https://github.com/crytic/slither/wiki/Detector-Documentation#dangerous-strict-equalities

INFO:Detectors:
WormholeBridgeBase.bridgeCost(uint16) (src/wormhole/WormholeBridgeBase.sol#214-234) ignores return value by (cost) = wormholeRelayer.quoteEVMDeliveryPrice(dstWormholeChainId,0,gasLimit) (src/wormhole/WormholeBridgeBase.sol#217-233)
WormholeBridgeBase._bridgeOutAll(bytes) (src/wormhole/WormholeBridgeBase.sol#279-324) ignores return value by wormholeRelayer.sendPayloadToEvm{value: cost}(targetChain,targetAddress[targetChain],payload,0,gasLimit) (src/wormhole/WormholeBridgeBase.sol#293-312)
Reference: https://github.com/crytic/slither/wiki/Detector-Documentation#unused-return

INFO:Detectors:
WormholeBridgeBase.bridgeCost(uint16) (src/wormhole/WormholeBridgeBase.sol#214-234) has external calls inside a loop: (cost) = wormholeRelayer.quoteEVMDeliveryPrice(dstWormholeChainId,0,gasLimit) (src/wormhole/WormholeBridgeBase.sol#217-233)
Reference: https://github.com/crytic/slither/wiki/Detector-Documentation/#calls-inside-a-loop

INFO:Detectors:
Reentrancy in WormholeBridgeBase._bridgeOutAll(bytes) (src/wormhole/WormholeBridgeBase.sol#279-324):
	External calls:
	- wormholeRelayer.sendPayloadToEvm{value: cost}(targetChain,targetAddress[targetChain],payload,0,gasLimit) (src/wormhole/WormholeBridgeBase.sol#293-312)
	Event emitted after the call(s):
	- BridgeOutFailed(targetChain,payload,cost) (src/wormhole/WormholeBridgeBase.sol#311)
	- BridgeOutSuccess(targetChain,cost,targetAddress[targetChain],payload) (src/wormhole/WormholeBridgeBase.sol#303-308)
Reentrancy in MultichainVoteCollection.emitVotes(uint256) (src/Governance/MultichainGovernor/MultichainVoteCollection.sol#243-285):
	External calls:
	- _bridgeOutAll(abi.encode(proposalId,votes.forVotes,votes.againstVotes,votes.abstainVotes)) (src/Governance/MultichainGovernor/MultichainVoteCollection.sol#270-277)
		- wormholeRelayer.sendPayloadToEvm{value: cost}(targetChain,targetAddress[targetChain],payload,0,gasLimit) (src/wormhole/WormholeBridgeBase.sol#293-312)
		- (success) = msg.sender.call{value: totalRefundAmount}() (src/wormhole/WormholeBridgeBase.sol#321)
	Event emitted after the call(s):
	- VotesEmitted(proposalId,votes.forVotes,votes.againstVotes,votes.abstainVotes) (src/Governance/MultichainGovernor/MultichainVoteCollection.sol#279-284)
Reference: https://github.com/crytic/slither/wiki/Detector-Documentation#reentrancy-vulnerabilities-3

INFO:Detectors:
ConfigurablePause.paused() (src/xWELL/ConfigurablePause.sol#41-46) uses timestamp for comparisons
	Dangerous comparisons:
	- block.timestamp <= pauseStartTime + pauseDuration (src/xWELL/ConfigurablePause.sol#42-45)
ConfigurablePauseGuardian.pauseUsed() (src/xWELL/ConfigurablePauseGuardian.sol#26-28) uses timestamp for comparisons
	Dangerous comparisons:
	- pauseStartTime != 0 (src/xWELL/ConfigurablePauseGuardian.sol#27)
MintLimits._setRateLimitPerSecond(address,uint128) (src/xWELL/MintLimits.sol#89-109) uses timestamp for comparisons
	Dangerous comparisons:
	- require(bool,string)(rateLimits[from].bufferCap != 0,MintLimits: non-existent rate limit) (src/xWELL/MintLimits.sol#97-100)
MintLimits._setBufferCap(address,uint112) (src/xWELL/MintLimits.sol#116-134) uses timestamp for comparisons
	Dangerous comparisons:
	- require(bool,string)(rateLimits[from].bufferCap != 0,MintLimits: non-existent rate limit) (src/xWELL/MintLimits.sol#118-121)
MintLimits._addLimit(MintLimits.RateLimitMidPointInfo) (src/xWELL/MintLimits.sol#149-180) uses timestamp for comparisons
	Dangerous comparisons:
	- require(bool,string)(rateLimits[rateLimit.bridge].bufferCap == 0,MintLimits: rate limit already exists) (src/xWELL/MintLimits.sol#158-161)
MintLimits._removeLimit(address) (src/xWELL/MintLimits.sol#194-203) uses timestamp for comparisons
	Dangerous comparisons:
	- require(bool,string)(rateLimits[bridge].bufferCap != 0,MintLimits: cannot remove non-existent rate limit) (src/xWELL/MintLimits.sol#195-198)
xWELL.CLOCK_MODE() (src/xWELL/xWELL.sol#90-95) uses timestamp for comparisons
	Dangerous comparisons:
	- require(bool,string)(clock() == uint48(block.timestamp),Incorrect clock) (src/xWELL/xWELL.sol#92)
MultichainVoteCollection.castVote(uint256,uint8) (src/Governance/MultichainGovernor/MultichainVoteCollection.sol#166-226) uses timestamp for comparisons
	Dangerous comparisons:
	- require(bool,string)(proposal.votingStartTime <= block.timestamp,MultichainVoteCollection: Voting has not started yet) (src/Governance/MultichainGovernor/MultichainVoteCollection.sol#173-176)
	- require(bool,string)(proposal.votingEndTime >= block.timestamp,MultichainVoteCollection: Voting has ended) (src/Governance/MultichainGovernor/MultichainVoteCollection.sol#179-182)
MultichainVoteCollection.emitVotes(uint256) (src/Governance/MultichainGovernor/MultichainVoteCollection.sol#243-285) uses timestamp for comparisons
	Dangerous comparisons:
	- require(bool,string)(proposal.votingEndTime < block.timestamp,MultichainVoteCollection: Voting has not ended) (src/Governance/MultichainGovernor/MultichainVoteCollection.sol#257-260)
	- require(bool,string)(proposal.crossChainVoteCollectionEndTimestamp >= block.timestamp,MultichainVoteCollection: Voting collection phase has ended) (src/Governance/MultichainGovernor/MultichainVoteCollection.sol#263-266)
MultichainVoteCollection._bridgeIn(uint16,bytes) (src/Governance/MultichainGovernor/MultichainVoteCollection.sol#289-350) uses timestamp for comparisons
	Dangerous comparisons:
	- require(bool,string)(votingEndTime > block.timestamp,MultichainVoteCollection: end time must be in the future) (src/Governance/MultichainGovernor/MultichainVoteCollection.sol#312-315)
Reference: https://github.com/crytic/slither/wiki/Detector-Documentation#block-timestamp

INFO:Detectors:
MultichainVoteCollection.castVote(uint256,uint8) (src/Governance/MultichainGovernor/MultichainVoteCollection.sol#166-226) compares to a boolean constant:
	-require(bool,string)(receipt.hasVoted == false,MultichainVoteCollection: voter already voted) (src/Governance/MultichainGovernor/MultichainVoteCollection.sol#192-195)
Reference: https://github.com/crytic/slither/wiki/Detector-Documentation#boolean-equality

INFO:Detectors:
WormholeBridgeBase._addTargetAddresses(WormholeTrustedSender.TrustedSender[]) (src/wormhole/WormholeBridgeBase.sol#117-127) is never used and should be removed
WormholeBridgeBase._removeTargetAddresses(WormholeTrustedSender.TrustedSender[]) (src/wormhole/WormholeBridgeBase.sol#154-171) is never used and should be removed
WormholeTrustedSender._addTrustedSender(address,uint16) (src/Governance/WormholeTrustedSender.sol#53-64) is never used and should be removed
WormholeTrustedSender._addTrustedSenders(WormholeTrustedSender.TrustedSender[]) (src/Governance/WormholeTrustedSender.sol#37-48) is never used and should be removed
WormholeTrustedSender._removeTrustedSender(address,uint16) (src/Governance/WormholeTrustedSender.sol#69-83) is never used and should be removed
WormholeTrustedSender._removeTrustedSenders(WormholeTrustedSender.TrustedSender[]) (src/Governance/WormholeTrustedSender.sol#87-98) is never used and should be removed
Reference: https://github.com/crytic/slither/wiki/Detector-Documentation#dead-code

INFO:Detectors:
Pragma version0.8.19 (src/Governance/IWormholeTrustedSender.sol#2) necessitates a version too recent to be trusted. Consider deploying with 0.8.18.
Pragma version0.8.19 (src/Governance/MultichainGovernor/Constants.sol#1) necessitates a version too recent to be trusted. Consider deploying with 0.8.18.
Pragma version0.8.19 (src/Governance/MultichainGovernor/IMultichainVoteCollection.sol#1) necessitates a version too recent to be trusted. Consider deploying with 0.8.18.
Pragma version0.8.19 (src/Governance/MultichainGovernor/SnapshotInterface.sol#1) necessitates a version too recent to be trusted. Consider deploying with 0.8.18.
Pragma version0.8.19 (src/Governance/WormholeTrustedSender.sol#2) necessitates a version too recent to be trusted. Consider deploying with 0.8.18.
Pragma version0.8.19 (src/wormhole/IWormhole.sol#3) necessitates a version too recent to be trusted. Consider deploying with 0.8.18.
Pragma version^0.8.0 (src/wormhole/IWormholeReceiver.sol#3) allows old versions
Pragma version^0.8.0 (src/wormhole/IWormholeRelayer.sol#3) allows old versions
Pragma version0.8.19 (src/wormhole/WormholeBridgeBase.sol#1) necessitates a version too recent to be trusted. Consider deploying with 0.8.18.
Pragma version0.8.19 (src/xWELL/ConfigurablePause.sol#1) necessitates a version too recent to be trusted. Consider deploying with 0.8.18.
Pragma version0.8.19 (src/xWELL/ConfigurablePauseGuardian.sol#1) necessitates a version too recent to be trusted. Consider deploying with 0.8.18.
Pragma version0.8.19 (src/xWELL/MintLimits.sol#1) necessitates a version too recent to be trusted. Consider deploying with 0.8.18.
Pragma version0.8.19 (src/xWELL/interfaces/IXERC20.sol#1) necessitates a version too recent to be trusted. Consider deploying with 0.8.18.
Pragma version0.8.19 (src/xWELL/xERC20.sol#1) necessitates a version too recent to be trusted. Consider deploying with 0.8.18.
Pragma version0.8.19 (src/xWELL/xWELL.sol#1) necessitates a version too recent to be trusted. Consider deploying with 0.8.18.
Pragma version0.8.19 (src/Governance/MultichainGovernor/MultichainVoteCollection.sol#1) necessitates a version too recent to be trusted. Consider deploying with 0.8.18.
solc-0.8.19 is not recommended for deployment
Reference: https://github.com/crytic/slither/wiki/Detector-Documentation#incorrect-versions-of-solidity

INFO:Detectors:
Low level call in WormholeBridgeBase._bridgeOutAll(bytes) (src/wormhole/WormholeBridgeBase.sol#279-324):
	- (success) = msg.sender.call{value: totalRefundAmount}() (src/wormhole/WormholeBridgeBase.sol#321)
Reference: https://github.com/crytic/slither/wiki/Detector-Documentation#low-level-calls

INFO:Detectors:
Variable WormholeBridgeBase._targetChains (src/wormhole/WormholeBridgeBase.sol#54) is not in mixedCase
Contract xERC20 (src/xWELL/xERC20.sol#13-123) is not in CapWords
Contract xWELL (src/xWELL/xWELL.sol#15-299) is not in CapWords
Function xWELL.CLOCK_MODE() (src/xWELL/xWELL.sol#90-95) is not in mixedCase
Parameter MultichainVoteCollection.initialize(address,address,address,address,uint16,address)._xWell (src/Governance/MultichainGovernor/MultichainVoteCollection.sol#65) is not in mixedCase
Parameter MultichainVoteCollection.initialize(address,address,address,address,uint16,address)._stkWell (src/Governance/MultichainGovernor/MultichainVoteCollection.sol#66) is not in mixedCase
Parameter MultichainVoteCollection.initialize(address,address,address,address,uint16,address)._moonbeamGovernor (src/Governance/MultichainGovernor/MultichainVoteCollection.sol#67) is not in mixedCase
Parameter MultichainVoteCollection.initialize(address,address,address,address,uint16,address)._wormholeRelayer (src/Governance/MultichainGovernor/MultichainVoteCollection.sol#68) is not in mixedCase
Parameter MultichainVoteCollection.initialize(address,address,address,address,uint16,address)._moonbeamWormholeChainId (src/Governance/MultichainGovernor/MultichainVoteCollection.sol#69) is not in mixedCase
Parameter MultichainVoteCollection.initialize(address,address,address,address,uint16,address)._owner (src/Governance/MultichainGovernor/MultichainVoteCollection.sol#70) is not in mixedCase
Reference: https://github.com/crytic/slither/wiki/Detector-Documentation#conformance-to-solidity-naming-conventions

INFO:Detectors:
Variable Constants.MAX_CROSS_CHAIN_VOTE_COLLECTION_PERIOD (src/Governance/MultichainGovernor/Constants.sol#27) is too similar to Constants.MIN_CROSS_CHAIN_VOTE_COLLECTION_PERIOD (src/Governance/MultichainGovernor/Constants.sol#24)
Variable Constants.MAX_PROPOSAL_THRESHOLD (src/Governance/MultichainGovernor/Constants.sol#33) is too similar to Constants.MIN_PROPOSAL_THRESHOLD (src/Governance/MultichainGovernor/Constants.sol#30)
Reference: https://github.com/crytic/slither/wiki/Detector-Documentation#variable-names-too-similar

INFO:Slither:src/Governance/MultichainGovernor/MultichainVoteCollection.sol analyzed (47 contracts with 88 detectors), 55 result(s) found
```
<br/><br/>

## MultichainGovernor/MultichainGovernor.sol

### Command

```
slither src/Governance/MultichainGovernor/MultichainGovernor.sol --solc-remaps "@protocol=./src @openzeppelin-contracts-upgradeable=./lib/openzeppelin-contracts-upgradeable @openzeppelin-contracts=./lib/openzeppelin-contracts @zelt=./lib/zelt @zelt-src=./lib/zelt/src"
```

### Output

```
Compilation warnings/errors on src/Governance/MultichainGovernor/MultichainGovernor.sol:
Warning: SPDX license identifier not provided in source file. Before publishing, consider adding a comment containing "SPDX-License-Identifier: <SPDX-License>" to each source file. Use "SPDX-License-Identifier: UNLICENSED" for non-open-source code. Please see https://spdx.org for more information.
--> src/Governance/MultichainGovernor/MultichainGovernor.sol

Warning: SPDX license identifier not provided in source file. Before publishing, consider adding a comment containing "SPDX-License-Identifier: <SPDX-License>" to each source file. Use "SPDX-License-Identifier: UNLICENSED" for non-open-source code. Please see https://spdx.org for more information.
--> ./src/Governance/MultichainGovernor/Constants.sol

Warning: SPDX license identifier not provided in source file. Before publishing, consider adding a comment containing "SPDX-License-Identifier: <SPDX-License>" to each source file. Use "SPDX-License-Identifier: UNLICENSED" for non-open-source code. Please see https://spdx.org for more information.
--> ./src/Governance/MultichainGovernor/IMultichainGovernor.sol

Warning: SPDX license identifier not provided in source file. Before publishing, consider adding a comment containing "SPDX-License-Identifier: <SPDX-License>" to each source file. Use "SPDX-License-Identifier: UNLICENSED" for non-open-source code. Please see https://spdx.org for more information.
--> ./src/Governance/MultichainGovernor/SnapshotInterface.sol

Warning: SPDX license identifier not provided in source file. Before publishing, consider adding a comment containing "SPDX-License-Identifier: <SPDX-License>" to each source file. Use "SPDX-License-Identifier: UNLICENSED" for non-open-source code. Please see https://spdx.org for more information.
--> ./src/wormhole/WormholeBridgeBase.sol

Warning: SPDX license identifier not provided in source file. Before publishing, consider adding a comment containing "SPDX-License-Identifier: <SPDX-License>" to each source file. Use "SPDX-License-Identifier: UNLICENSED" for non-open-source code. Please see https://spdx.org for more information.
--> ./src/xWELL/ConfigurablePauseGuardian.sol

Warning: SPDX license identifier not provided in source file. Before publishing, consider adding a comment containing "SPDX-License-Identifier: <SPDX-License>" to each source file. Use "SPDX-License-Identifier: UNLICENSED" for non-open-source code. Please see https://spdx.org for more information.
--> ./src/xWELL/xWELL.sol

Warning: SPDX license identifier not provided in source file. Before publishing, consider adding a comment containing "SPDX-License-Identifier: <SPDX-License>" to each source file. Use "SPDX-License-Identifier: UNLICENSED" for non-open-source code. Please see https://spdx.org for more information.
--> ./src/xWELL/ConfigurablePause.sol

Warning: SPDX license identifier not provided in source file. Before publishing, consider adding a comment containing "SPDX-License-Identifier: <SPDX-License>" to each source file. Use "SPDX-License-Identifier: UNLICENSED" for non-open-source code. Please see https://spdx.org for more information.
--> ./src/xWELL/MintLimits.sol

Warning: SPDX license identifier not provided in source file. Before publishing, consider adding a comment containing "SPDX-License-Identifier: <SPDX-License>" to each source file. Use "SPDX-License-Identifier: UNLICENSED" for non-open-source code. Please see https://spdx.org for more information.
--> ./src/xWELL/interfaces/IXERC20.sol

Warning: SPDX license identifier not provided in source file. Before publishing, consider adding a comment containing "SPDX-License-Identifier: <SPDX-License>" to each source file. Use "SPDX-License-Identifier: UNLICENSED" for non-open-source code. Please see https://spdx.org for more information.
--> ./src/xWELL/xERC20.sol

Warning: SPDX license identifier not provided in source file. Before publishing, consider adding a comment containing "SPDX-License-Identifier: <SPDX-License>" to each source file. Use "SPDX-License-Identifier: UNLICENSED" for non-open-source code. Please see https://spdx.org for more information.
--> ./lib/zelt/src/lib/RateLimitMidpointCommonLibrary.sol

Warning: SPDX license identifier not provided in source file. Before publishing, consider adding a comment containing "SPDX-License-Identifier: <SPDX-License>" to each source file. Use "SPDX-License-Identifier: UNLICENSED" for non-open-source code. Please see https://spdx.org for more information.
--> ./lib/zelt/src/lib/RateLimitedMidpointLibrary.sol

Warning: SPDX license identifier not provided in source file. Before publishing, consider adding a comment containing "SPDX-License-Identifier: <SPDX-License>" to each source file. Use "SPDX-License-Identifier: UNLICENSED" for non-open-source code. Please see https://spdx.org for more information.
--> ./lib/zelt/src/util/Math.sol

Warning: Contract code size is 36043 bytes and exceeds 24576 bytes (a limit introduced in Spurious Dragon). This contract may not be deployable on Mainnet. Consider enabling the optimizer (with a low "runs" value!), turning off revert strings, or using libraries.
  --> ./src/xWELL/xWELL.sol:15:1:
   |
15 | contract xWELL is
   | ^ (Relevant source part starts here and spans across multiple lines).

Warning: Contract code size is 43740 bytes and exceeds 24576 bytes (a limit introduced in Spurious Dragon). This contract may not be deployable on Mainnet. Consider enabling the optimizer (with a low "runs" value!), turning off revert strings, or using libraries.
  --> src/Governance/MultichainGovernor/MultichainGovernor.sol:22:1:
   |
22 | contract MultichainGovernor is
   | ^ (Relevant source part starts here and spans across multiple lines).

INFO:Detectors:
WormholeBridgeBase._bridgeOutAll(bytes) (src/wormhole/WormholeBridgeBase.sol#279-324) sends eth to arbitrary user
	Dangerous calls:
	- (success) = msg.sender.call{value: totalRefundAmount}() (src/wormhole/WormholeBridgeBase.sol#321)
Reference: https://github.com/crytic/slither/wiki/Detector-Documentation#functions-that-send-ether-to-arbitrary-destinations

INFO:Detectors:
xWELL.CLOCK_MODE() (src/xWELL/xWELL.sol#90-95) uses a dangerous strict equality:
	- require(bool,string)(clock() == uint48(block.timestamp),Incorrect clock) (src/xWELL/xWELL.sol#92)
ConfigurablePause.paused() (src/xWELL/ConfigurablePause.sol#41-46) uses a dangerous strict equality:
	- pauseStartTime == 0 (src/xWELL/ConfigurablePause.sol#42-45)
Reference: https://github.com/crytic/slither/wiki/Detector-Documentation#dangerous-strict-equalities

INFO:Detectors:
WormholeBridgeBase.bridgeCost(uint16) (src/wormhole/WormholeBridgeBase.sol#214-234) ignores return value by (cost) = wormholeRelayer.quoteEVMDeliveryPrice(dstWormholeChainId,0,gasLimit) (src/wormhole/WormholeBridgeBase.sol#217-233)
WormholeBridgeBase._bridgeOutAll(bytes) (src/wormhole/WormholeBridgeBase.sol#279-324) ignores return value by wormholeRelayer.sendPayloadToEvm{value: cost}(targetChain,targetAddress[targetChain],payload,0,gasLimit) (src/wormhole/WormholeBridgeBase.sol#293-312)
MultichainGovernor.execute(uint256) (src/Governance/MultichainGovernor/MultichainGovernor.sol#749-792) ignores return value by proposal.targets[i_scope_0].functionCallWithValue(proposal.calldatas[i_scope_0],proposal.values[i_scope_0],MultichainGovernor: execute call failed) (src/Governance/MultichainGovernor/MultichainGovernor.sol#783-787)
MultichainGovernor.executeBreakGlass(address[],bytes[]) (src/Governance/MultichainGovernor/MultichainGovernor.sol#1000-1031) ignores return value by targets[i].functionCall(calldatas[i],MultichainGovernor: break glass guardian call failed) (src/Governance/MultichainGovernor/MultichainGovernor.sol#1018-1021)
Reference: https://github.com/crytic/slither/wiki/Detector-Documentation#unused-return

INFO:Detectors:
WormholeBridgeBase.bridgeCost(uint16) (src/wormhole/WormholeBridgeBase.sol#214-234) has external calls inside a loop: (cost) = wormholeRelayer.quoteEVMDeliveryPrice(dstWormholeChainId,0,gasLimit) (src/wormhole/WormholeBridgeBase.sol#217-233)
Reference: https://github.com/crytic/slither/wiki/Detector-Documentation/#calls-inside-a-loop

INFO:Detectors:
Reentrancy in WormholeBridgeBase._bridgeOutAll(bytes) (src/wormhole/WormholeBridgeBase.sol#279-324):
	External calls:
	- wormholeRelayer.sendPayloadToEvm{value: cost}(targetChain,targetAddress[targetChain],payload,0,gasLimit) (src/wormhole/WormholeBridgeBase.sol#293-312)
	Event emitted after the call(s):
	- BridgeOutFailed(targetChain,payload,cost) (src/wormhole/WormholeBridgeBase.sol#311)
	- BridgeOutSuccess(targetChain,cost,targetAddress[targetChain],payload) (src/wormhole/WormholeBridgeBase.sol#303-308)
Reentrancy in MultichainGovernor.execute(uint256) (src/Governance/MultichainGovernor/MultichainGovernor.sol#749-792):
	External calls:
	- proposal.targets[i_scope_0].functionCallWithValue(proposal.calldatas[i_scope_0],proposal.values[i_scope_0],MultichainGovernor: execute call failed) (src/Governance/MultichainGovernor/MultichainGovernor.sol#783-787)
	Event emitted after the call(s):
	- ProposalExecuted(proposalId) (src/Governance/MultichainGovernor/MultichainGovernor.sol#791)
Reentrancy in MultichainGovernor.executeBreakGlass(address[],bytes[]) (src/Governance/MultichainGovernor/MultichainGovernor.sol#1000-1031):
	External calls:
	- targets[i].functionCall(calldatas[i],MultichainGovernor: break glass guardian call failed) (src/Governance/MultichainGovernor/MultichainGovernor.sol#1018-1021)
	Event emitted after the call(s):
	- BreakGlassExecuted(msg.sender,targets,calldatas) (src/Governance/MultichainGovernor/MultichainGovernor.sol#1030)
Reentrancy in MultichainGovernor.rebroadcastProposal(uint256) (src/Governance/MultichainGovernor/MultichainGovernor.sol#598-618):
	External calls:
	- _bridgeOutAll(payload) (src/Governance/MultichainGovernor/MultichainGovernor.sol#615)
		- wormholeRelayer.sendPayloadToEvm{value: cost}(targetChain,targetAddress[targetChain],payload,0,gasLimit) (src/wormhole/WormholeBridgeBase.sol#293-312)
		- (success) = msg.sender.call{value: totalRefundAmount}() (src/wormhole/WormholeBridgeBase.sol#321)
	Event emitted after the call(s):
	- ProposalRebroadcasted(proposalId,payload) (src/Governance/MultichainGovernor/MultichainGovernor.sol#617)
Reference: https://github.com/crytic/slither/wiki/Detector-Documentation#reentrancy-vulnerabilities-3

INFO:Detectors:
ConfigurablePause.paused() (src/xWELL/ConfigurablePause.sol#41-46) uses timestamp for comparisons
	Dangerous comparisons:
	- block.timestamp <= pauseStartTime + pauseDuration (src/xWELL/ConfigurablePause.sol#42-45)
ConfigurablePauseGuardian.pauseUsed() (src/xWELL/ConfigurablePauseGuardian.sol#26-28) uses timestamp for comparisons
	Dangerous comparisons:
	- pauseStartTime != 0 (src/xWELL/ConfigurablePauseGuardian.sol#27)
MintLimits._setRateLimitPerSecond(address,uint128) (src/xWELL/MintLimits.sol#89-109) uses timestamp for comparisons
	Dangerous comparisons:
	- require(bool,string)(rateLimits[from].bufferCap != 0,MintLimits: non-existent rate limit) (src/xWELL/MintLimits.sol#97-100)
MintLimits._setBufferCap(address,uint112) (src/xWELL/MintLimits.sol#116-134) uses timestamp for comparisons
	Dangerous comparisons:
	- require(bool,string)(rateLimits[from].bufferCap != 0,MintLimits: non-existent rate limit) (src/xWELL/MintLimits.sol#118-121)
MintLimits._addLimit(MintLimits.RateLimitMidPointInfo) (src/xWELL/MintLimits.sol#149-180) uses timestamp for comparisons
	Dangerous comparisons:
	- require(bool,string)(rateLimits[rateLimit.bridge].bufferCap == 0,MintLimits: rate limit already exists) (src/xWELL/MintLimits.sol#158-161)
MintLimits._removeLimit(address) (src/xWELL/MintLimits.sol#194-203) uses timestamp for comparisons
	Dangerous comparisons:
	- require(bool,string)(rateLimits[bridge].bufferCap != 0,MintLimits: cannot remove non-existent rate limit) (src/xWELL/MintLimits.sol#195-198)
xWELL.CLOCK_MODE() (src/xWELL/xWELL.sol#90-95) uses timestamp for comparisons
	Dangerous comparisons:
	- require(bool,string)(clock() == uint48(block.timestamp),Incorrect clock) (src/xWELL/xWELL.sol#92)
MultichainGovernor.proposalValid(uint256) (src/Governance/MultichainGovernor/MultichainGovernor.sol#254-259) uses timestamp for comparisons
	Dangerous comparisons:
	- proposalCount >= proposalId && proposalId > 0 && proposals[proposalId].proposer != address(0) (src/Governance/MultichainGovernor/MultichainGovernor.sol#255-258)
MultichainGovernor.state(uint256) (src/Governance/MultichainGovernor/MultichainGovernor.sol#549-586) uses timestamp for comparisons
	Dangerous comparisons:
	- block.timestamp <= proposal.votingEndTime (src/Governance/MultichainGovernor/MultichainGovernor.sol#562)
	- block.timestamp <= proposal.crossChainVoteCollectionEndTimestamp (src/Governance/MultichainGovernor/MultichainGovernor.sol#566)
MultichainGovernor.propose(address[],uint256[],bytes[],string) (src/Governance/MultichainGovernor/MultichainGovernor.sol#626-741) uses timestamp for comparisons
	Dangerous comparisons:
	- require(bool,string)(getVotes(msg.sender,block.timestamp - 1,block.number - 1) >= proposalThreshold,MultichainGovernor: proposer votes below proposal threshold) (src/Governance/MultichainGovernor/MultichainGovernor.sol#635-639)
MultichainGovernor.cancel(uint256) (src/Governance/MultichainGovernor/MultichainGovernor.sol#806-829) uses timestamp for comparisons
	Dangerous comparisons:
	- require(bool,string)(msg.sender == proposals[proposalId].proposer || getCurrentVotes(proposals[proposalId].proposer) < proposalThreshold,MultichainGovernor: unauthorized cancel) (src/Governance/MultichainGovernor/MultichainGovernor.sol#807-812)
MultichainGovernor.castVote(uint256,uint8) (src/Governance/MultichainGovernor/MultichainGovernor.sol#834-882) uses timestamp for comparisons
	Dangerous comparisons:
	- require(bool,string)(receipt.hasVoted == false,MultichainGovernor: voter already voted) (src/Governance/MultichainGovernor/MultichainGovernor.sol#850-853)
	- require(bool,string)(votes != 0,MultichainGovernor: voter has no votes) (src/Governance/MultichainGovernor/MultichainGovernor.sol#864)
Reference: https://github.com/crytic/slither/wiki/Detector-Documentation#block-timestamp

INFO:Detectors:
MultichainGovernor.castVote(uint256,uint8) (src/Governance/MultichainGovernor/MultichainGovernor.sol#834-882) compares to a boolean constant:
	-require(bool,string)(receipt.hasVoted == false,MultichainGovernor: voter already voted) (src/Governance/MultichainGovernor/MultichainGovernor.sol#850-853)
MultichainGovernor._updateApprovedCalldata(bytes,bool) (src/Governance/MultichainGovernor/MultichainGovernor.sol#1088-1109) compares to a boolean constant:
	-approved == true (src/Governance/MultichainGovernor/MultichainGovernor.sol#1093)
Reference: https://github.com/crytic/slither/wiki/Detector-Documentation#boolean-equality

INFO:Detectors:
WormholeTrustedSender._addTrustedSender(address,uint16) (src/Governance/WormholeTrustedSender.sol#53-64) is never used and should be removed
WormholeTrustedSender._addTrustedSenders(WormholeTrustedSender.TrustedSender[]) (src/Governance/WormholeTrustedSender.sol#37-48) is never used and should be removed
WormholeTrustedSender._removeTrustedSender(address,uint16) (src/Governance/WormholeTrustedSender.sol#69-83) is never used and should be removed
WormholeTrustedSender._removeTrustedSenders(WormholeTrustedSender.TrustedSender[]) (src/Governance/WormholeTrustedSender.sol#87-98) is never used and should be removed
Reference: https://github.com/crytic/slither/wiki/Detector-Documentation#dead-code

INFO:Detectors:
Pragma version0.8.19 (src/Governance/IWormholeTrustedSender.sol#2) necessitates a version too recent to be trusted. Consider deploying with 0.8.18.
Pragma version0.8.19 (src/Governance/MultichainGovernor/Constants.sol#1) necessitates a version too recent to be trusted. Consider deploying with 0.8.18.
Pragma version0.8.19 (src/Governance/MultichainGovernor/IMultichainGovernor.sol#1) necessitates a version too recent to be trusted. Consider deploying with 0.8.18.
Pragma version0.8.19 (src/Governance/MultichainGovernor/SnapshotInterface.sol#1) necessitates a version too recent to be trusted. Consider deploying with 0.8.18.
Pragma version0.8.19 (src/Governance/WormholeTrustedSender.sol#2) necessitates a version too recent to be trusted. Consider deploying with 0.8.18.
Pragma version0.8.19 (src/wormhole/IWormhole.sol#3) necessitates a version too recent to be trusted. Consider deploying with 0.8.18.
Pragma version^0.8.0 (src/wormhole/IWormholeReceiver.sol#3) allows old versions
Pragma version^0.8.0 (src/wormhole/IWormholeRelayer.sol#3) allows old versions
Pragma version0.8.19 (src/wormhole/WormholeBridgeBase.sol#1) necessitates a version too recent to be trusted. Consider deploying with 0.8.18.
Pragma version0.8.19 (src/xWELL/ConfigurablePause.sol#1) necessitates a version too recent to be trusted. Consider deploying with 0.8.18.
Pragma version0.8.19 (src/xWELL/ConfigurablePauseGuardian.sol#1) necessitates a version too recent to be trusted. Consider deploying with 0.8.18.
Pragma version0.8.19 (src/xWELL/MintLimits.sol#1) necessitates a version too recent to be trusted. Consider deploying with 0.8.18.
Pragma version0.8.19 (src/xWELL/interfaces/IXERC20.sol#1) necessitates a version too recent to be trusted. Consider deploying with 0.8.18.
Pragma version0.8.19 (src/xWELL/xERC20.sol#1) necessitates a version too recent to be trusted. Consider deploying with 0.8.18.
Pragma version0.8.19 (src/xWELL/xWELL.sol#1) necessitates a version too recent to be trusted. Consider deploying with 0.8.18.
Pragma version0.8.19 (src/Governance/MultichainGovernor/MultichainGovernor.sol#1) necessitates a version too recent to be trusted. Consider deploying with 0.8.18.
solc-0.8.19 is not recommended for deployment
Reference: https://github.com/crytic/slither/wiki/Detector-Documentation#incorrect-versions-of-solidity

INFO:Detectors:
Low level call in WormholeBridgeBase._bridgeOutAll(bytes) (src/wormhole/WormholeBridgeBase.sol#279-324):
	- (success) = msg.sender.call{value: totalRefundAmount}() (src/wormhole/WormholeBridgeBase.sol#321)
Reference: https://github.com/crytic/slither/wiki/Detector-Documentation#low-level-calls

INFO:Detectors:
Variable WormholeBridgeBase._targetChains (src/wormhole/WormholeBridgeBase.sol#54) is not in mixedCase
Contract xERC20 (src/xWELL/xERC20.sol#13-123) is not in CapWords
Contract xWELL (src/xWELL/xWELL.sol#15-299) is not in CapWords
Function xWELL.CLOCK_MODE() (src/xWELL/xWELL.sol#90-95) is not in mixedCase
Parameter MultichainGovernor.removeExternalChainConfigs(WormholeTrustedSender.TrustedSender[])._trustedSenders (src/Governance/MultichainGovernor/MultichainGovernor.sol#905) is not in mixedCase
Parameter MultichainGovernor.addExternalChainConfigs(WormholeTrustedSender.TrustedSender[])._trustedSenders (src/Governance/MultichainGovernor/MultichainGovernor.sol#915) is not in mixedCase
Reference: https://github.com/crytic/slither/wiki/Detector-Documentation#conformance-to-solidity-naming-conventions

INFO:Detectors:
Variable Constants.MAX_CROSS_CHAIN_VOTE_COLLECTION_PERIOD (src/Governance/MultichainGovernor/Constants.sol#27) is too similar to Constants.MIN_CROSS_CHAIN_VOTE_COLLECTION_PERIOD (src/Governance/MultichainGovernor/Constants.sol#24)
Variable Constants.MAX_PROPOSAL_THRESHOLD (src/Governance/MultichainGovernor/Constants.sol#33) is too similar to Constants.MIN_PROPOSAL_THRESHOLD (src/Governance/MultichainGovernor/Constants.sol#30)
Reference: https://github.com/crytic/slither/wiki/Detector-Documentation#variable-names-too-similar

INFO:Slither:src/Governance/MultichainGovernor/MultichainGovernor.sol analyzed (48 contracts with 88 detectors), 56 result(s) found
```
<br/><br/>

## stkWell/StakedWell.sol

### Command

```
slither ./src/stkWell/StakedWell.sol
```

### Output

```
Compilation warnings/errors on ./src/stkWell/StakedWell.sol:
Warning: SPDX license identifier not provided in source file. Before publishing, consider adding a comment containing "SPDX-License-Identifier: <SPDX-License>" to each source file. Use "SPDX-License-Identifier: UNLICENSED" for non-open-source code. Please see https://spdx.org for more information.
--> ./src/stkWell/ReentrancyGuardUpgradeable.sol

INFO:Detectors:
StakedToken.claimRewards(address,uint256) (src/stkWell/StakedToken.sol#200-221) uses arbitrary from in transferFrom: IERC20(REWARD_TOKEN).safeTransferFrom(REWARDS_VAULT,to,amountToClaim) (src/stkWell/StakedToken.sol#218)
Reference: https://github.com/crytic/slither/wiki/Detector-Documentation#arbitrary-from-in-transferfrom
INFO:Detectors:
DistributionManager._getAssetIndex(uint256,uint256,uint128,uint256) (src/stkWell/DistributionManager.sol#256-279) uses a dangerous strict equality:
	- emissionPerSecond == 0 || totalBalance == 0 || lastUpdateTimestamp == block.timestamp || lastUpdateTimestamp >= DISTRIBUTION_END (src/stkWell/DistributionManager.sol#263-266)
DistributionManager._updateAssetStateInternal(address,DistributionManager.AssetData,uint256) (src/stkWell/DistributionManager.sol#110-137) uses a dangerous strict equality:
	- block.timestamp == lastUpdateTimestamp (src/stkWell/DistributionManager.sol#118)
ERC20WithSnapshot._writeSnapshot(address,uint128,uint128) (src/stkWell/ERC20WithSnapshot.sol#96-122) uses a dangerous strict equality:
	- ownerCountOfSnapshots != 0 && snapshotsOwner[ownerCountOfSnapshots.sub(1)].blockTimestamp == currentBlock (src/stkWell/ERC20WithSnapshot.sol#108-110)
StakedToken.getNextCooldownTimestamp(uint256,uint256,address,uint256) (src/stkWell/StakedToken.sol#305-342) uses a dangerous strict equality:
	- toCooldownTimestamp == 0 (src/stkWell/StakedToken.sol#312)
Reference: https://github.com/crytic/slither/wiki/Detector-Documentation#dangerous-strict-equalities

INFO:Detectors:
Reentrancy in StakedToken.redeem(address,uint256) (src/stkWell/StakedToken.sol#146-181):
	External calls:
	- _burn(msg.sender,amountToRedeem) (src/stkWell/StakedToken.sol#172)
		- governance.onTransfer(from,to,amount) (src/stkWell/ERC20WithSnapshot.sol#162)
	State variables written after the call(s):
	- stakersCooldowns[msg.sender] = 0 (src/stkWell/StakedToken.sol#175)
	StakedToken.stakersCooldowns (src/stkWell/StakedToken.sol#41) can be used in cross function reentrancies:
	- StakedToken._transfer(address,address,uint256) (src/stkWell/StakedToken.sol#229-257)
	- StakedToken.cooldown() (src/stkWell/StakedToken.sol#187-193)
	- StakedToken.getNextCooldownTimestamp(uint256,uint256,address,uint256) (src/stkWell/StakedToken.sol#305-342)
	- StakedToken.stakersCooldowns (src/stkWell/StakedToken.sol#41)
Reference: https://github.com/crytic/slither/wiki/Detector-Documentation#reentrancy-vulnerabilities-1
INFO:Detectors:
ERC20.__ERC20_init_unchained(string,string,uint8).name (src/stkWell/ERC20.sol#25) shadows:
	- ERC20.name() (src/stkWell/ERC20.sol#37-39) (function)
	- IERC20Detailed.name() (src/stkWell/IERC20Detailed.sol#10) (function)
ERC20.__ERC20_init_unchained(string,string,uint8).symbol (src/stkWell/ERC20.sol#26) shadows:
	- ERC20.symbol() (src/stkWell/ERC20.sol#44-46) (function)
	- IERC20Detailed.symbol() (src/stkWell/IERC20Detailed.sol#11) (function)
ERC20.__ERC20_init_unchained(string,string,uint8).decimals (src/stkWell/ERC20.sol#27) shadows:
	- ERC20.decimals() (src/stkWell/ERC20.sol#51-53) (function)
	- IERC20Detailed.decimals() (src/stkWell/IERC20Detailed.sol#12) (function)
StakedToken.__StakedToken_init(IERC20,IERC20,uint256,uint256,address,address,uint128,string,string,uint8,address).name (src/stkWell/StakedToken.sol#67) shadows:
	- ERC20.name() (src/stkWell/ERC20.sol#37-39) (function)
	- IERC20Detailed.name() (src/stkWell/IERC20Detailed.sol#10) (function)
StakedToken.__StakedToken_init(IERC20,IERC20,uint256,uint256,address,address,uint128,string,string,uint8,address).symbol (src/stkWell/StakedToken.sol#68) shadows:
	- ERC20.symbol() (src/stkWell/ERC20.sol#44-46) (function)
	- IERC20Detailed.symbol() (src/stkWell/IERC20Detailed.sol#11) (function)
StakedToken.__StakedToken_init(IERC20,IERC20,uint256,uint256,address,address,uint128,string,string,uint8,address).decimals (src/stkWell/StakedToken.sol#69) shadows:
	- ERC20.decimals() (src/stkWell/ERC20.sol#51-53) (function)
	- IERC20Detailed.decimals() (src/stkWell/IERC20Detailed.sol#12) (function)
Reference: https://github.com/crytic/slither/wiki/Detector-Documentation#local-variable-shadowing
INFO:Detectors:
DistributionManager.setEmissionsManager(address).newEmissionsManager (src/stkWell/DistributionManager.sol#297) lacks a zero-check on :
		- EMISSION_MANAGER = newEmissionsManager (src/stkWell/DistributionManager.sol#299)
Reference: https://github.com/crytic/slither/wiki/Detector-Documentation#missing-zero-address-validation

INFO:Detectors:
DistributionManager._updateAssetStateInternal(address,DistributionManager.AssetData,uint256) (src/stkWell/DistributionManager.sol#110-137) uses timestamp for comparisons
	Dangerous comparisons:
	- block.timestamp == lastUpdateTimestamp (src/stkWell/DistributionManager.sol#118)
	- newIndex != oldIndex (src/stkWell/DistributionManager.sol#129)
DistributionManager._updateUserAssetInternal(address,address,uint256,uint256) (src/stkWell/DistributionManager.sol#147-173) uses timestamp for comparisons
	Dangerous comparisons:
	- userIndex != newIndex (src/stkWell/DistributionManager.sol#163)
DistributionManager._getAssetIndex(uint256,uint256,uint128,uint256) (src/stkWell/DistributionManager.sol#256-279) uses timestamp for comparisons
	Dangerous comparisons:
	- emissionPerSecond == 0 || totalBalance == 0 || lastUpdateTimestamp == block.timestamp || lastUpdateTimestamp >= DISTRIBUTION_END (src/stkWell/DistributionManager.sol#263-266)
	- block.timestamp > DISTRIBUTION_END (src/stkWell/DistributionManager.sol#271-273)
ERC20WithSnapshot.getPriorVotes(address,uint256) (src/stkWell/ERC20WithSnapshot.sol#50-88) uses timestamp for comparisons
	Dangerous comparisons:
	- require(bool,string)(blockTimestamp < block.timestamp,not yet determined) (src/stkWell/ERC20WithSnapshot.sol#54)
ERC20WithSnapshot._writeSnapshot(address,uint128,uint128) (src/stkWell/ERC20WithSnapshot.sol#96-122) uses timestamp for comparisons
	Dangerous comparisons:
	- ownerCountOfSnapshots != 0 && snapshotsOwner[ownerCountOfSnapshots.sub(1)].blockTimestamp == currentBlock (src/stkWell/ERC20WithSnapshot.sol#108-110)
StakedToken.stake(address,uint256) (src/stkWell/StakedToken.sol#104-139) uses timestamp for comparisons
	Dangerous comparisons:
	- accruedRewards != 0 (src/stkWell/StakedToken.sol#118)
StakedToken.redeem(address,uint256) (src/stkWell/StakedToken.sol#146-181) uses timestamp for comparisons
	Dangerous comparisons:
	- require(bool,string)(block.timestamp > cooldownStartTimestamp.add(COOLDOWN_SECONDS),INSUFFICIENT_COOLDOWN) (src/stkWell/StakedToken.sol#151-154)
	- require(bool,string)(block.timestamp.sub(cooldownStartTimestamp.add(COOLDOWN_SECONDS)) <= UNSTAKE_WINDOW,UNSTAKE_WINDOW_FINISHED) (src/stkWell/StakedToken.sol#155-159)
StakedToken._updateCurrentUnclaimedRewards(address,uint256,bool) (src/stkWell/StakedToken.sol#266-289) uses timestamp for comparisons
	Dangerous comparisons:
	- accruedRewards != 0 (src/stkWell/StakedToken.sol#281)
StakedToken.getNextCooldownTimestamp(uint256,uint256,address,uint256) (src/stkWell/StakedToken.sol#305-342) uses timestamp for comparisons
	Dangerous comparisons:
	- toCooldownTimestamp == 0 (src/stkWell/StakedToken.sol#312)
	- minimalValidCooldownTimestamp > toCooldownTimestamp (src/stkWell/StakedToken.sol#321)
	- fromCooldownTimestampFinal < toCooldownTimestamp (src/stkWell/StakedToken.sol#329)
	- (minimalValidCooldownTimestamp > fromCooldownTimestamp) (src/stkWell/StakedToken.sol#324-327)
Reference: https://github.com/crytic/slither/wiki/Detector-Documentation#block-timestamp

INFO:Detectors:
Address.isContract(address) (src/stkWell/Address.sol#26-37) uses assembly
	- INLINE ASM (src/stkWell/Address.sol#33-35)
Reference: https://github.com/crytic/slither/wiki/Detector-Documentation#assembly-usage

INFO:Detectors:
Address.sendValue(address,uint256) (src/stkWell/Address.sol#55-61) is never used and should be removed
Context._msgData() (src/stkWell/Context.sol#20-23) is never used and should be removed
DistributionManager._claimRewards(address,DistributionTypes.UserStakeInput[]) (src/stkWell/DistributionManager.sol#181-199) is never used and should be removed
ERC20._beforeTokenTransfer(address,address,uint256) (src/stkWell/ERC20.sol#237-241) is never used and should be removed
ERC20._setDecimals(uint8) (src/stkWell/ERC20.sol#233-235) is never used and should be removed
ERC20._setName(string) (src/stkWell/ERC20.sol#225-227) is never used and should be removed
ERC20._setSymbol(string) (src/stkWell/ERC20.sol#229-231) is never used and should be removed
SafeERC20.safeApprove(IERC20,address,uint256) (src/stkWell/SafeERC20.sol#41-54) is never used and should be removed
SafeERC20.safeIncreaseAllowance(IERC20,address,uint256) (src/stkWell/SafeERC20.sol#56-70) is never used and should be removed
SafeMath.mod(uint256,uint256) (src/stkWell/SafeMath.sol#141-143) is never used and should be removed
SafeMath.mod(uint256,uint256,string) (src/stkWell/SafeMath.sol#156-163) is never used and should be removed
Reference: https://github.com/crytic/slither/wiki/Detector-Documentation#dead-code

INFO:Detectors:
Pragma version0.6.12 (src/stkWell/Address.sol#2) allows old versions
Pragma version0.6.12 (src/stkWell/Context.sol#2) allows old versions
Pragma version0.6.12 (src/stkWell/DistributionManager.sol#2) allows old versions
Pragma version0.6.12 (src/stkWell/DistributionTypes.sol#2) allows old versions
Pragma version0.6.12 (src/stkWell/ERC20.sol#2) allows old versions
Pragma version0.6.12 (src/stkWell/ERC20WithSnapshot.sol#2) allows old versions
Pragma version0.6.12 (src/stkWell/IDistributionManager.sol#2) allows old versions
Pragma version0.6.12 (src/stkWell/IERC20.sol#2) allows old versions
Pragma version0.6.12 (src/stkWell/IERC20Detailed.sol#2) allows old versions
Pragma version0.6.12 (src/stkWell/IEcosystemReserve.sol#2) allows old versions
Pragma version0.6.12 (src/stkWell/IStakedToken.sol#2) allows old versions
Pragma version0.6.12 (src/stkWell/ITransferHook.sol#2) allows old versions
Pragma version0.6.12 (src/stkWell/Initializable.sol#4) allows old versions
Pragma version0.6.12 (src/stkWell/ReentrancyGuardUpgradeable.sol#1) allows old versions
Pragma version0.6.12 (src/stkWell/SafeERC20.sol#2) allows old versions
Pragma version0.6.12 (src/stkWell/SafeMath.sol#2) allows old versions
Pragma version0.6.12 (src/stkWell/StakedToken.sol#2) allows old versions
Pragma version0.6.12 (src/stkWell/StakedWell.sol#2) allows old versions
solc-0.6.12 is not recommended for deployment
Reference: https://github.com/crytic/slither/wiki/Detector-Documentation#incorrect-versions-of-solidity
INFO:Detectors:
Low level call in Address.sendValue(address,uint256) (src/stkWell/Address.sol#55-61):
	- (success) = recipient.call{value: amount}() (src/stkWell/Address.sol#59)
Low level call in SafeERC20._callOptionalReturn(IERC20,bytes) (src/stkWell/SafeERC20.sol#72-87):
	- (success,returndata) = address(token).call(data) (src/stkWell/SafeERC20.sol#76)
Reference: https://github.com/crytic/slither/wiki/Detector-Documentation#low-level-calls

INFO:Detectors:
Function DistributionManager.__DistributionManager_init_unchained(address,uint256) (src/stkWell/DistributionManager.sol#41-48) is not in mixedCase
Variable DistributionManager.DISTRIBUTION_END (src/stkWell/DistributionManager.sol#25) is not in mixedCase
Variable DistributionManager.EMISSION_MANAGER (src/stkWell/DistributionManager.sol#27) is not in mixedCase
Function ERC20.__ERC20_init_unchained(string,string,uint8) (src/stkWell/ERC20.sol#24-32) is not in mixedCase
Variable ERC20WithSnapshot._snapshots (src/stkWell/ERC20WithSnapshot.sol#19) is not in mixedCase
Variable ERC20WithSnapshot._countsSnapshots (src/stkWell/ERC20WithSnapshot.sol#20) is not in mixedCase
Variable ERC20WithSnapshot._governance (src/stkWell/ERC20WithSnapshot.sol#24) is not in mixedCase
Function ReentrancyGuardUpgradeable.__ReentrancyGuard_init() (src/stkWell/ReentrancyGuardUpgradeable.sol#38-40) is not in mixedCase
Function ReentrancyGuardUpgradeable.__ReentrancyGuard_init_unchained() (src/stkWell/ReentrancyGuardUpgradeable.sol#42-44) is not in mixedCase
Variable ReentrancyGuardUpgradeable.__gap (src/stkWell/ReentrancyGuardUpgradeable.sol#72) is not in mixedCase
Function StakedToken.__StakedToken_init(IERC20,IERC20,uint256,uint256,address,address,uint128,string,string,uint8,address) (src/stkWell/StakedToken.sol#59-86) is not in mixedCase
Function StakedToken.__StakedToken_init_unchained(IERC20,IERC20,uint256,uint256,address,address) (src/stkWell/StakedToken.sol#88-102) is not in mixedCase
Variable StakedToken.STAKED_TOKEN (src/stkWell/StakedToken.sol#30) is not in mixedCase
Variable StakedToken.REWARD_TOKEN (src/stkWell/StakedToken.sol#31) is not in mixedCase
Variable StakedToken.COOLDOWN_SECONDS (src/stkWell/StakedToken.sol#32) is not in mixedCase
Variable StakedToken.UNSTAKE_WINDOW (src/stkWell/StakedToken.sol#35) is not in mixedCase
Variable StakedToken.REWARDS_VAULT (src/stkWell/StakedToken.sol#38) is not in mixedCase
Reference: https://github.com/crytic/slither/wiki/Detector-Documentation#conformance-to-solidity-naming-conventions

INFO:Detectors:
Redundant expression "this (src/stkWell/Context.sol#21)" inContext (src/stkWell/Context.sol#15-25)
Reference: https://github.com/crytic/slither/wiki/Detector-Documentation#redundant-statements

INFO:Slither:./src/stkWell/StakedWell.sol analyzed (18 contracts with 88 detectors), 73 result(s) found
```