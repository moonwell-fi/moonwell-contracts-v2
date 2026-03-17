# Slither 漏洞验证报告

**项目**: Moonwell Contracts V2
**验证日期**: 2026-03-17

---

## 验证结果汇总

| 漏洞类型 | 位置 | 严重程度 | 验证状态 | PoC |
|---------|------|---------|---------|-----|
| reentrancy-eth | ChainlinkFeedOEVWrapper.updatePriceEarly() | HIGH | ✅ 已验证 | ✅ |
| divide-before-multiply | ChainlinkOEVMorphoWrapper (多处) | MEDIUM | ✅ 已验证 | ✅ |
| reentrancy-balance | ReserveAutomation.cancelAuction() | MEDIUM | ✅ 已验证 | ✅ |
| reentrancy-balance | FeeSplitter.split() | MEDIUM | ✅ 已验证 | ✅ |
| reentrancy-no-eth | StakedToken.redeem() | LOW | ✅ 已验证 | ✅ |
| arbitrary-send-erc20 | StakedToken.claimRewards() | INFO | ✅ 误报 | N/A |
| unchecked-transfer | EcosystemReserve.transfer() | LOW | ✅ 已验证 | ✅ |
| unchecked-transfer | Comptroller._rescueFunds() | LOW | ✅ 已验证 | ✅ |

---

## 详细分析

### 1. ✅ reentrancy-eth (HIGH)

**位置**: `ChainlinkFeedOEVWrapper.sol#202-247`

```solidity
function updatePriceEarly() external payable returns (uint256) {
    // ...
    WETH.deposit{value: msg.value}();                    // 外部调用 1
    WETH.approve(address(WETHMarket), msg.value);        // 外部调用 2
    require(WETHMarket._addReserves(msg.value) == 0, ...); // 外部调用 3 - 重入点!
    
    cachedRoundId = latestRoundId;  // 状态更新在外部调用之后!
}
```

**问题**: 违反 Checks-Effects-Interactions 模式

**PoC**: `test/exploit/ReentrancyPOC.t.sol`

**修复建议**:
```solidity
function updatePriceEarly() external payable returns (uint256) {
    // ...验证逻辑...
    
    // 先更新状态!
    cachedRoundId = latestRoundId;
    
    // 再执行外部调用
    WETH.deposit{value: msg.value}();
    WETH.approve(address(WETHMarket), msg.value);
    require(WETHMarket._addReserves(msg.value) == 0, ...);
}
```

---

### 2. ✅ divide-before-multiply (MEDIUM)

**位置**: 多个 Oracle 合约

**问题代码**:
```solidity
// ChainlinkOEVMorphoWrapper._calculateCollateralSplit()
underlyingAmount = (collateralSeized * exchangeRate) / 1e18;  // 先除
collateralUSD = (underlyingAmount * collateralPrice) / usdNormalizer;  // 再乘除
```

**影响**: 整数除法截断导致精度损失

**PoC**: `test/exploit/PrecisionLossPOC.t.sol`

---

### 3. ✅ reentrancy-balance (MEDIUM)

**位置**: `ReserveAutomation.cancelAuction()`

```solidity
function cancelAuction() external {
    uint256 amount = IERC20(reserveAsset).balanceOf(address(this));  // 缓存余额
    
    IERC20(reserveAsset).approve(mTokenMarket, amount);  // 外部调用 1
    require(MErc20(mTokenMarket)._addReserves(amount) == 0, ...);  // 外部调用 2
}
```

**问题**: 
- 余额在外部调用前缓存
- 如果 `_addReserves` 触发回调，余额可能已变化
- 使用 stale balance 可能导致资金损失

**PoC**: `test/exploit/SlitherIssuesPOC.t.sol`

---

### 4. ✅ reentrancy-balance (MEDIUM)

**位置**: `FeeSplitter.split()`

```solidity
function split() public {
    uint256 amount = IERC20(metaMorphoVault).balanceOf(address(this));  // 缓存
    
    IERC20(metaMorphoVault).safeTransfer(b, amountB);           // 外部调用 1
    uint256 withdrawnAssets = IERC4626(metaMorphoVault).redeem(...);  // 外部调用 2
    token.safeApprove(mToken, withdrawnAssets);                  // 外部调用 3
    require(MErc20(mToken)._addReserves(withdrawnAssets) == 0, ...);  // 外部调用 4
}
```

**问题**: 
- 无 `nonReentrant` 修饰符
- 4 个外部调用点都可能触发重入
- 使用 stale balance

**PoC**: `test/exploit/SlitherIssuesPOC.t.sol`

---

### 5. ✅ reentrancy-no-eth (LOW)

**位置**: `StakedToken.redeem()`

```solidity
function redeem(address to, uint256 amount) external nonReentrant {
    // ...
    _burn(msg.sender, amountToRedeem);  // 触发 governance.onTransfer() 回调
    stakersCooldowns[msg.sender] = 0;    // 状态更新在回调之后
}
```

**问题**: `_burn` 内部调用 `governance.onTransfer()`，可能触发重入

**缓解**: 有 `nonReentrant` 修饰符，但状态更新时机仍不理想

---

### 6. ✅ arbitrary-send-erc20 (INFO - 误报)

**位置**: `StakedToken.claimRewards()`

```solidity
IERC20(REWARD_TOKEN).safeTransferFrom(REWARDS_VAULT, to, amountToClaim);
```

**Slither 报告**: "uses arbitrary from in transferFrom"

**分析**: 
- `REWARDS_VAULT` 是 immutable 变量，在构造函数中设置
- 不是用户控制的输入
- **结论: 误报**

---

### 7. ✅ unchecked-transfer (LOW)

**位置**: `EcosystemReserve.transfer()`

```solidity
function transfer(IERC20 token, address recipient, uint256 amount) external {
    token.transfer(recipient, amount);  // 返回值未检查!
}
```

**问题**: 如果 token 是非标准 ERC20（返回 false 而非 revert），转账可能静默失败

**修复建议**:
```solidity
require(token.transfer(recipient, amount), "Transfer failed");
// 或使用 SafeERC20
token.safeTransfer(recipient, amount);
```

---

### 8. ✅ unchecked-transfer (LOW)

**位置**: `Comptroller._rescueFunds()`

```solidity
function _rescueFunds(address _tokenAddress, uint _amount) external {
    IERC20 token = IERC20(_tokenAddress);
    if (_amount == type(uint).max) {
        token.transfer(admin, token.balanceOf(address(this)));  // 未检查!
    } else {
        token.transfer(admin, _amount);  // 未检查!
    }
}
```

**问题**: 同上，静默失败风险

---

## PoC 文件列表

```
test/exploit/
├── PrecisionLossPOC.t.sol      # 精度损失 PoC
├── ReentrancyPOC.t.sol         # 重入攻击 PoC
└── SlitherIssuesPOC.t.sol      # 其他 Slither 发现 PoC
```

---

## 修复优先级建议

| 优先级 | 漏洞 | 建议 |
|-------|------|------|
| 🔴 P0 | reentrancy-eth | 立即修复 - 状态更新移到外部调用前 |
| 🟠 P1 | divide-before-multiply | 高优先级 - 重构计算顺序 |
| 🟠 P1 | reentrancy-balance | 高优先级 - 添加 nonReentrant 或 CEI 模式 |
| 🟡 P2 | unchecked-transfer | 中优先级 - 使用 SafeERC20 |
| 🟢 P3 | reentrancy-no-eth | 低优先级 - 已有 nonReentrant |

---

**最后更新**: 2026-03-17 04:30 UTC
