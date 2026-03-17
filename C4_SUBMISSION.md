# Code4rena Submission - Moonwell Contracts V2

## 漏洞 #1: Reentrancy in ChainlinkFeedOEVWrapper.updatePriceEarly()

### Severity: HIGH

**Impact:**
Attacker can exploit the reentrancy vulnerability to manipulate price data during the callback, leading to price manipulation, MEV extraction, and unfair liquidation advantages.

**Description:**
The `updatePriceEarly()` function violates the Checks-Effects-Interactions pattern. The state variable `cachedRoundId` is updated after external calls, allowing an attacker to re-enter `latestRoundData()` during the `_addReserves` callback and see stale prices.

**PoC:**
```solidity
// See test/exploit/ReentrancyPOC.t.sol

function test_Reentrancy_Attack() public {
    vm.deal(address(attacker), 10 ether);
    priceFeed.setNewRound(2001e8);
    
    vm.prank(address(attacker));
    attacker.attack{value: 1 ether}();
    
    // During reentrancy, cachedRoundId is NOT updated yet
    // But attacker has already paid for early price access
}
```

**Recommended Mitigation:**
Move state updates before external calls:
```solidity
// Update state FIRST
cachedRoundId = latestRoundId;

// THEN external calls
WETH.deposit{value: msg.value}();
WETH.approve(address(WETHMarket), msg.value);
WETHMarket._addReserves(msg.value);
```

---

## 漏洞 #2: Precision Loss in Collateral Split Calculation

### Severity: MEDIUM

**Impact:**
Liquidators may receive incorrect collateral amounts due to integer division truncation. The protocol may lose fees or liquidators may lose funds, especially when dealing with small amounts or low-priced tokens.

**Description:**
The `_calculateCollateralSplit()` function uses a "divide-before-multiply" calculation order, causing intermediate results to be truncated by integer division. This creates cumulative errors in precision-sensitive financial calculations.

**PoC:**
```solidity
// See test/exploit/PrecisionLossPOC.t.sol

// Current implementation (with precision loss):
uint256 repayUSD = (repayAmount * loanTokenPrice) / usdNormalizer;  // Division truncates
uint256 collateralUSD = (collateralReceived * collateralTokenPrice) / usdNormalizer;  // Division truncates
liquidatorFee = (liquidatorUSD * usdNormalizer) / collateralPrice;  // More division

// Result: liquidatorFee differs from expected due to cumulative truncation
```

**Recommended Mitigation:**
Restructure calculations to preserve intermediate precision:
```solidity
// Keep full precision, avoid intermediate division
uint256 collateralValue = collateralSeized * exchangeRate * collateralPricePerUnit;
uint256 repayValue = repayAmount * loanPricePerUnit * 1e18;

// Perform single division at the end
uint256 liquidatorValue = repayValue + ((collateralValue - repayValue) * liquidatorFeeBps) / MAX_BPS;
liquidatorFee = liquidatorValue / (collateralPricePerUnit * 1e18);
```

---

## 漏洞 #3: Reentrancy in FeeSplitter.split()

### Severity: MEDIUM

**Impact:**
Attacker can re-enter during external calls and receive duplicate payments using stale balance, causing protocol fund loss.

**Description:**
The `split()` function lacks a `nonReentrant` modifier and executes multiple external calls after caching the balance. If `metaMorphoVault` supports callbacks, an attacker can re-enter with the same stale balance.

**PoC:**
```solidity
// See test/exploit/SlitherIssuesPOC.t.sol

// Attack scenario:
// 1. Attacker calls split()
// 2. During safeTransfer callback, attacker re-enters split()
// 3. Second call reads the same balance (not yet updated)
// 4. Attacker gets paid twice
```

**Recommended Mitigation:**
Add `nonReentrant` modifier:
```solidity
function split() public nonReentrant {
    // ...
}
```

---

## 漏洞 #4: Stale Balance in ReserveAutomation.cancelAuction()

### Severity: MEDIUM

**Impact:**
If callbacks are triggered during external calls, stale balance data may be used, potentially causing fund loss or double-spending.

**Description:**
The function caches balance before external calls but doesn't update it after potential reentry points.

**PoC:**
```solidity
// See test/exploit/SlitherIssuesPOC.t.sol

function cancelAuction() external {
    uint256 amount = IERC20(reserveAsset).balanceOf(address(this));  // Cached
    
    IERC20(reserveAsset).approve(mTokenMarket, amount);  // External call 1
    MErc20(mTokenMarket)._addReserves(amount);  // External call 2 - REENTRY POINT
    
    // If callback transfers more tokens to contract, they won't be added
}
```

**Recommended Mitigation:**
Add `nonReentrant` modifier or read balance immediately before use.

---

## 漏洞 #5: Unchecked Transfer Return Values

### Severity: LOW

**Impact:**
Silent failures in transfers could cause lost funds or accounting inconsistencies.

**Description:**
`EcosystemReserve.transfer()` and `Comptroller._rescueFunds()` ignore transfer return values. For non-standard ERC20 tokens that return false instead of reverting, transfers could fail silently.

**PoC:**
```solidity
// See test/exploit/SlitherIssuesPOC.t.sol

function transfer(IERC20 token, address recipient, uint256 amount) external {
    token.transfer(recipient, amount);  // Return value ignored!
    // If token.transfer() returns false, transfer failed but function succeeds
}
```

**Recommended Mitigation:**
Use SafeERC20 or check return values:
```solidity
token.safeTransfer(recipient, amount);
// OR
require(token.transfer(recipient, amount), "Transfer failed");
```
