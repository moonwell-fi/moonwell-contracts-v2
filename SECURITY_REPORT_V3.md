# Security Vulnerability Report V3 - Moonwell Contracts V2

## Date: 2026-03-20
## Auditor: fujijin

---

## 🟠 MEDIUM: FeeSplitter 缺少 Reentrancy 保护

**Location**: `src/morpho/FeeSplitter.sol:79-107`

**Impact**:
- `split()` 函数没有 `nonReentrant` 修饰符
- 攻击者可以通过重入攻击在 `redeem()` 和 `_addReserves()` 之间操纵状态
- 可能导致资金损失

**Code**:
```solidity
function split() public {
    uint256 amount = IERC20(metaMorphoVault).balanceOf(address(this));
    
    uint256 amountA = (amount * splitA) / SPLIT_TOTAL;
    uint256 amountB = (amount * splitB) / SPLIT_TOTAL;
    
    IERC20(metaMorphoVault).safeTransfer(b, amountB);
    
    uint256 withdrawnAssets = IERC4626(metaMorphoVault).redeem(
        amountA,
        address(this),
        address(this)
    );
    
    token.safeApprove(mToken, withdrawnAssets);
    require(
        MErc20(mToken)._addReserves(withdrawnAssets) == 0,
        "FeeSplitter: add reserves failure"
    );
    
    emit TokensSplit(amountA, amountB);
}
```

**Attack Scenario**:
1. 攻击者在 MetaMorpho Vault 中部署恶意合约
2. 调用 FeeSplitter.split() 时，攻击者通过回调重入
3. 攻击者可以操纵 `splitA`/`splitB` 计算或窃取资金

**Recommended Fix**:
```solidity
import {ReentrancyGuard} from "@openzeppelin-contracts/...";

contract FeeSplitter is ReentrancyGuard {
    function split() public nonReentrant {
        // ...
    }
}
```

---

## 🟡 LOW: FeeSplitter 流动性风险

**Location**: `src/morpho/FeeSplitter.sol:89-93`

**Impact**:
- 如果 MetaMorpho Vault 流动性不足，`redeem()` 会失败
- 整个 `split()` 操作将回滚，用户无法获得分成

**Code**:
```solidity
uint256 withdrawnAssets = IERC4626(metaMorphoVault).redeem(
    amountA,
    address(this),
    address(this)
);
```

**Recommended Fix**:
- 添加部分提取逻辑，允许部分成功
- 添加滑点保护

---

## 🟡 LOW: ChainlinkOracle 可能返回 stale 数据

**Location**: `src/oracles/ChainlinkOracle.sol`

**Impact**:
- 如果 Chainlink 节点停止更新价格，合约仍会返回旧价格
- 可能导致清算不及时或不当清算

**Recommended Fix**:
- 添加 `heartbeat` 检查，确保价格不是 stale
- 添加价格变化阈值检查

---

## 📋 Summary

| Vulnerability | Severity | Status |
|--------------|-----------|--------|
| Owner可变价格参数 | MEDIUM | In PR #618 |
| Oracle可替换 | MEDIUM | In PR #618 |
| ETH提取风险 | MEDIUM | In PR #618 |
| 精度损失累积 | LOW | In PR #618 |
| FeeSplitter Reentrancy | MEDIUM | NEW |
| FeeSplitter 流动性风险 | LOW | NEW |
| Chainlink Stale Data | LOW | NEW |

---

## Recommendations

1. **MEDIUM**: 为 FeeSplitter 添加 reentrancy guard
2. **MEDIUM**: 为 ChainlinkOracle 添加 stale price 检查
3. **LOW**: 优化 FeeSplitter 的流动性处理
