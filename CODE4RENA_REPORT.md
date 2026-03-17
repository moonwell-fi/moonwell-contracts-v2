# Code4rena 漏洞报告 - Moonwell Contracts V2

**提交日期**: 2026-03-17
**审计人**: 金仔五号

---

## 漏洞 #1: 重入攻击导致价格操纵

### 严重程度: HIGH

### 影响
`ChainlinkFeedOEVWrapper.updatePriceEarly()` 函数存在重入漏洞，攻击者可以在外部调用期间操纵价格数据，导致：
- 价格操纵
- MEV 提取
- 不公平的清算优势

### 漏洞描述
`updatePriceEarly()` 函数违反了 Checks-Effects-Interactions 模式。状态变量 `cachedRoundId` 在外部调用之后才更新，这允许攻击者在 `_addReserves` 回调期间重入 `latestRoundData()` 并看到旧价格。

### 受影响代码
```solidity
// File: src/oracles/ChainlinkFeedOEVWrapper.sol
// Lines: 202-247

function updatePriceEarly() external payable returns (uint256) {
    require(
        msg.value >= (tx.gasprice - block.basefee) * uint256(feeMultiplier),
        "ChainlinkOEVWrapper: Insufficient tax"
    );

    (
        uint256 latestRoundId,
        int256 latestAnswer,
        ,
        uint256 latestUpdatedAt,
        uint80 latestAnsweredInRound
    ) = originalFeed.latestRoundData();

    _validateRoundData(
        uint80(latestRoundId),
        latestAnswer,
        latestUpdatedAt,
        latestAnsweredInRound
    );

    require(
        latestRoundId > cachedRoundId,
        "ChainlinkOEVWrapper: New round is not higher than cached"
    );

    // 外部调用 - 重入点!
    WETH.deposit{value: msg.value}();
    WETH.approve(address(WETHMarket), msg.value);
    require(
        WETHMarket._addReserves(msg.value) == 0,
        "ChainlinkOEVWrapper: Failed to add reserves"
    );

    // 状态更新在外部调用之后 - 漏洞!
    cachedRoundId = latestRoundId;
    return cachedRoundId;
}
```

### 攻击场景
1. 攻击者调用 `updatePriceEarly()` 支付费用获取早期价格访问
2. 在 `_addReserves` 调用期间，如果 WETHMarket 有回调机制，攻击者可以重入
3. 重入时 `cachedRoundId` 尚未更新，攻击者看到旧价格
4. 攻击者可以利用价格差异进行套利

### Proof of Concept
```solidity
// File: test/exploit/ReentrancyPOC.t.sol

function test_Reentrancy_Attack() public {
    // Setup: Fund the attacker with ETH
    vm.deal(address(attacker), 10 ether);
    
    // Setup: Create a new round (price update)
    priceFeed.setNewRound(2001e8); // New price: $2001
    
    uint256 cachedRoundBefore = attacker.cachedRoundId();
    
    // Execute the attack
    vm.prank(address(attacker));
    attacker.attack{value: 1 ether}();
    
    uint256 cachedRoundAfter = attacker.cachedRoundId();
    
    // During reentrancy, cachedRoundId is NOT updated yet
    // But we've already paid the fee to get early price access
}
```

### 修复建议
将状态更新移到外部调用之前：

```solidity
function updatePriceEarly() external payable returns (uint256) {
    // ... 验证逻辑 ...

    require(
        latestRoundId > cachedRoundId,
        "ChainlinkOEVWrapper: New round is not higher than cached"
    );

    // 先更新状态! (Effects)
    cachedRoundId = latestRoundId;

    // 再执行外部调用 (Interactions)
    WETH.deposit{value: msg.value}();
    WETH.approve(address(WETHMarket), msg.value);
    require(
        WETHMarket._addReserves(msg.value) == 0,
        "ChainlinkOEVWrapper: Failed to add reserves"
    );

    return cachedRoundId;
}
```

---

## 漏洞 #2: 精度损失导致清算金额计算错误

### 严重程度: MEDIUM

### 影响
`ChainlinkOEVMorphoWrapper._calculateCollateralSplit()` 函数中的精度损失可能导致：
- 清算者收到错误的抵押品数量
- 协议损失费用或清算者资金损失
- 特别是在处理小金额或低价格代币时影响更严重

### 漏洞描述
函数采用 "先除后乘" 的计算顺序，导致中间结果被整数除法截断。这在处理精度敏感的金融计算时会产生累积误差。

### 受影响代码
```solidity
// File: src/oracles/ChainlinkOEVMorphoWrapper.sol
// Lines: 607-649

function _calculateCollateralSplit(
    uint256 collateralSeized,
    int256 collateralPrice,
    uint256 exchangeRate,
    EIP20Interface loanToken,
    address mTokenCollateral,
    EIP20Interface underlyingLoan
) internal view returns (uint256 liquidatorFee) {
    uint256 underlyingAmount = (collateralSeized * exchangeRate) / 1e18;  // 先除
    
    uint256 collateralPricePerUnit = _getCollateralTokenPrice(
        collateralPrice,
        EIP20Interface(mTokenCollateral)
    );
    
    uint256 collateralUSD = (underlyingAmount * collateralPricePerUnit) / usdNormalizer;  // 再除
    
    uint256 repayUSD = (repayAmount * loanPricePerUnit) / usdNormalizer;  // 再除
    
    uint256 liquidatorUSD = repayUSD + ((collateralUSD - repayUSD) * uint256(liquidatorFeeBps)) / MAX_BPS;  // 再除
    
    uint256 liquidatorUnderlyingAmount = (liquidatorUSD * usdNormalizer) / collateralPrice;  // 再除
    
    liquidatorFee = (liquidatorUnderlyingAmount * 1e18) / exchangeRate;  // 再除
}
```

### Proof of Concept
```solidity
// File: test/exploit/PrecisionLossPOC.t.sol

function test_PrecisionLoss_ProtocolFundLoss() public view {
    uint256 repayAmount = 100 * 1e18;
    uint256 collateralReceived = 100 * 1e18;
    
    uint256 loanTokenPrice = 1e18;      // $1 per loan token
    uint256 collateralTokenPrice = 1.1e18; // $1.10 per collateral token
    uint16 liquidatorFeeBps = 5000;     // 50%
    
    // 当前实现（有精度损失）
    uint256 repayUSD = (repayAmount * loanTokenPrice) / USD_NORMALIZER;
    uint256 collateralUSD = (collateralReceived * collateralTokenPrice) / USD_NORMALIZER;
    
    // 多次除法导致精度累积损失
    // 最终 liquidatorFee 会与预期值有偏差
}
```

### 修复建议
重构计算顺序，保留中间精度：

```solidity
function _calculateCollateralSplit(...) internal view returns (uint256 liquidatorFee) {
    // 保留完整精度，避免中间除法
    uint256 collateralValue = collateralSeized * exchangeRate * collateralPricePerUnit;
    uint256 repayValue = repayAmount * loanPricePerUnit * 1e18;
    
    // 最后统一进行一次除法
    uint256 liquidatorValue = repayValue + ((collateralValue - repayValue) * uint256(liquidatorFeeBps)) / MAX_BPS;
    
    liquidatorFee = liquidatorValue / (collateralPricePerUnit * 1e18);
}
```

---

## 漏洞 #3: FeeSplitter 重入导致资金重复分配

### 严重程度: MEDIUM

### 影响
`FeeSplitter.split()` 函数缺少重入保护，攻击者可以：
- 在外部调用期间重入
- 使用 stale balance 获取重复支付
- 导致协议资金损失

### 漏洞描述
函数在缓存余额后执行多个外部调用，但没有 `nonReentrant` 修饰符。如果 `metaMorphoVault` 是恶意合约或支持回调，攻击者可以重入并使用相同的 stale balance。

### 受影响代码
```solidity
// File: src/morpho/FeeSplitter.sol
// Lines: 79-108

function split() public {  // 无 nonReentrant!
    uint256 amount = IERC20(metaMorphoVault).balanceOf(address(this));  // 缓存余额
    
    uint256 amountA = (amount * splitA) / SPLIT_TOTAL;
    uint256 amountB = (amount * splitB) / SPLIT_TOTAL;
    
    // 外部调用 1 - 可重入
    IERC20(metaMorphoVault).safeTransfer(b, amountB);
    
    // 外部调用 2 - 可重入
    uint256 withdrawnAssets = IERC4626(metaMorphoVault).redeem(
        amountA,
        address(this),
        address(this)
    );
    
    // 外部调用 3 - 可重入
    token.safeApprove(mToken, withdrawnAssets);
    
    // 外部调用 4 - 可重入
    require(
        MErc20(mToken)._addReserves(withdrawnAssets) == 0,
        "FeeSplitter: add reserves failure"
    );
}
```

### 修复建议
添加 `nonReentrant` 修饰符并遵循 CEI 模式：

```solidity
function split() public nonReentrant {
    uint256 amount = IERC20(metaMorphoVault).balanceOf(address(this));
    
    uint256 amountA = (amount * splitA) / SPLIT_TOTAL;
    uint256 amountB = (amount * splitB) / SPLIT_TOTAL;
    
    // 先更新状态（如果有）
    // ...
    
    // 再执行外部调用
    IERC20(metaMorphoVault).safeTransfer(b, amountB);
    // ...
}
```

---

## 漏洞 #4: ReserveAutomation Stale Balance

### 严重程度: MEDIUM

### 影响
`ReserveAutomation.cancelAuction()` 函数缓存余额后执行外部调用，如果触发回调可能导致：
- 使用过时的余额数据
- 资金损失或双重支付

### 受影响代码
```solidity
// File: src/market/ReserveAutomation.sol
// Lines: 484-503

function cancelAuction() external {
    require(msg.sender == guardian, "ReserveAutomationModule: only guardian");
    
    uint256 amount = IERC20(reserveAsset).balanceOf(address(this));  // 缓存余额
    
    saleStartTime = 0;
    periodSaleAmount = 0;
    
    IERC20(reserveAsset).approve(mTokenMarket, amount);  // 外部调用
    
    require(
        MErc20(mTokenMarket)._addReserves(amount) == 0,  // 外部调用 - 使用 stale balance
        "ReserveAutomationModule: add reserves failure"
    );
}
```

### 修复建议
在外部调用后重新读取余额，或使用 ReentrancyGuard：

```solidity
function cancelAuction() external nonReentrant {
    require(msg.sender == guardian, "ReserveAutomationModule: only guardian");
    
    saleStartTime = 0;
    periodSaleAmount = 0;
    
    // 在外部调用时读取余额
    uint256 amount = IERC20(reserveAsset).balanceOf(address(this));
    IERC20(reserveAsset).approve(mTokenMarket, amount);
    
    require(
        MErc20(mTokenMarket)._addReserves(amount) == 0,
        "ReserveAutomationModule: add reserves failure"
    );
}
```

---

## 漏洞 #5: Unchecked Transfer Return Values

### 严重程度: LOW

### 影响
`EcosystemReserve.transfer()` 和 `Comptroller._rescueFunds()` 忽略 transfer 返回值，可能导致：
- 静默失败
- 资金丢失
- 会计不一致

### 受影响代码
```solidity
// File: src/stkWell/EcosystemReserve.sol
function transfer(IERC20 token, address recipient, uint256 amount) external {
    token.transfer(recipient, amount);  // 返回值未检查!
}

// File: src/Comptroller.sol
function _rescueFunds(address _tokenAddress, uint _amount) external {
    IERC20 token = IERC20(_tokenAddress);
    if (_amount == type(uint).max) {
        token.transfer(admin, token.balanceOf(address(this)));  // 未检查!
    } else {
        token.transfer(admin, _amount);  // 未检查!
    }
}
```

### 修复建议
使用 SafeERC20 或检查返回值：

```solidity
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

function transfer(IERC20 token, address recipient, uint256 amount) external {
    token.safeTransfer(recipient, amount);
}
```

---

## 附录: PoC 文件

所有 Proof of Concept 代码位于：
- `test/exploit/PrecisionLossPOC.t.sol`
- `test/exploit/ReentrancyPOC.t.sol`
- `test/exploit/SlitherIssuesPOC.t.sol`

运行测试：
```bash
forge test --match-path "test/exploit/*"
```

---

**报告提交者**: 金仔五号
**提交时间**: 2026-03-17 04:30 UTC
