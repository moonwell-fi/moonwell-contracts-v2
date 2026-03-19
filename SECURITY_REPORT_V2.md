# Security Vulnerability Report V2 - Moonwell Contracts V2

## Date: 2026-03-19
## Auditor: 金仔五号

---

## 🟠 MEDIUM: Owner 可变价格参数

**Location**: 
- `src/oracles/ChainlinkFeedOEVWrapper.sol:252` - `setFeeMultiplier()`
- `src/oracles/ChainlinkFeedOEVWrapper.sol:261` - `setMaxDecrements()`
- `src/oracles/ChainlinkCompositeOEVWrapper.sol:286` - `setLiquidatorFeeBps()`

**Impact**:
- 管理员可随意修改手续费参数
- 可能导致价格计算不公平
- 闪电贷攻击风险

**Code**:
```solidity
function setFeeMultiplier(uint8 newMultiplier) external onlyOwner {
    s_feeMultiplier = newMultiplier;
}

function setMaxDecrements(uint8 _maxDecrements) external onlyOwner {
    s_maxDecrements = _maxDecrements;
}
```

**Recommended Fix**:
- 添加参数修改时间锁
- 设置参数范围限制
- 多签机制

---

## 🟠 MEDIUM: Oracle 可被替换绕过验证

**Location**: `src/oracles/ChainlinkBoundedCompositeOracle.sol:130`

**Impact**:
- 管理员可更换为核心预言机
- 可能绕过安全检查
- 资金安全风险

**Code**:
```solidity
function setPrimaryOracle(address _primaryOracle) external onlyOwner {
    s_primaryOracle = IChainlinkOracle(_primaryOracle);
}
```

**Recommended Fix**:
- 限制可设置的 Oracle 列表
- 添加 Oracle 变更时间锁

---

## 🟠 MEDIUM: ETH 提取无限制

**Location**: `src/oracles/ChainlinkCompositeOEVWrapper.sol:349`

**Impact**:
- 仅 `onlyOwner` 可提取合约内 ETH
- 无监督机制

**Code**:
```solidity
function recoverETH(address payable to) external onlyOwner {
    (bool success, ) = to.call{value: address(this).balance}("");
    require(success, "Transfer failed");
}
```

---

## 🟡 LOW: 精度损失累积

**Location**: `src/oracles/ChainlinkOEVMorphoWrapper.sol`

**Impact**: Liquidators 可能收到略少的抵押品

---

## 📋 Summary

| Vulnerability | Severity | Status |
|--------------|-----------|--------|
| Reentrancy (已报告) | HIGH | In PR #610 |
| Precision Loss (已报告) | MEDIUM | In PR #610 |
| FeeSplitter Reentrancy (已报告) | MEDIUM | In PR #610 |
| Stale Balance (已报告) | MEDIUM | In PR #610 |
| Owner可变价格参数 | MEDIUM | NEW |
| Oracle可替换 | MEDIUM | NEW |
| ETH提取风险 | MEDIUM | NEW |
| 精度损失累积 | LOW | NEW |
