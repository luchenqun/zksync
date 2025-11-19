# Base Token 跨链测试指南

## 功能说明

`scripts/depositBaseToken.ts` 脚本现在执行完整的 Base Token 往返测试：

1. **存款 L1 → L2**: 将 20 个 base tokens 从 L1 跨到 L2
2. **等待同步**: 等待 60 秒让 L2 同步存款
3. **提现 L2 → L1**: 将 10 个 base tokens 从 L2 跨回 L1
4. **等待 finalize**: 等待 120 秒让提现准备就绪
5. **完成提现**: Finalize 提现，让资金真正回到 L1
6. **显示余额变化**: 展示整个过程的余额变化

## 使用方法

### 方法一：使用默认配置

```bash
npm run bridge:base-token
```

默认配置：
- 存款 20 个 tokens (L1 → L2)
- 提现 10 个 tokens (L2 → L1)
- 等待 60 秒同步存款
- 等待 120 秒 finalize 提现

### 方法二：自定义配置

在 `.env` 文件中设置：

```bash
DEPOSIT_AMOUNT=20              # L1 -> L2 存款金额
WITHDRAW_AMOUNT=10             # L2 -> L1 提现金额
DEPOSIT_WAIT_SECONDS=60        # 存款后等待 L2 同步的时间
WITHDRAW_FINALIZE_WAIT=120     # 等待提现可以 finalize 的时间
```

或者通过环境变量运行：

```bash
DEPOSIT_AMOUNT=30 WITHDRAW_AMOUNT=15 npm run bridge:base-token
```

## 执行流程

```
初始状态
├─ L1: 100 tokens
└─ L2: 0 tokens

[1/5] 检查初始余额
├─ L1 Base Token Balance: 100.0
└─ L2 Base Token Balance: 0.0

[2/5] 存款 20 tokens 从 L1 到 L2
├─ 存款交易哈希: 0x...
├─ ✓ 存款完成！
├─ 等待 60 秒...
└─ L2 存款后余额: 20.0

[3/5] 提现 10 tokens 从 L2 到 L1
├─ 提现交易哈希: 0x...
└─ ✓ 提现交易已提交！

[4/5] 等待提现可以 finalize
└─ 等待 120 秒...

[5/5] Finalizing 提现
├─ Finalize 交易哈希: 0x...
└─ ✓ Finalize 完成！

最终余额
├─ L1 Base Token Balance: 90.0
└─ L2 Base Token Balance: 10.0

余额变化
├─ L1: 100.0 -> 90.0 (-10.0)
└─ L2: 0.0 -> 10.0 (+10.0)

✓ 跨链测试完成！
```

## 输出示例

```
[17:45:30] 开始 L1 ↔ L2 Base Token 跨链测试
========================================
[17:45:30] L1 RPC: http://127.0.0.1:8545
[17:45:30] L2 RPC: http://127.0.0.1:3150
[17:45:30] Token Address: 0x5FbDB2315678afecb367f032d93F642f64180aa3
[17:45:30] 存款金额: 20 tokens
[17:45:30] 提现金额: 10 tokens
========================================

[17:45:30] Wallet address: 0x36615Cf349d7F6344891B1e7CA7C72883F5dc049

[17:45:31] [1/5] 检查初始余额...
[17:45:31] L1 Base Token Balance: 100.0
[17:45:31] L2 Base Token Balance: 0.0

[17:45:31] [2/5] 存款 20 tokens 从 L1 到 L2...
[17:45:33] 存款交易哈希: 0xabc123...
[17:45:33] ✓ 存款完成！
[17:45:33] 等待 60 秒...
[17:46:33] L2 存款后余额: 20.0

[17:46:33] [3/5] 提现 10 tokens 从 L2 到 L1...
[17:46:35] 提现交易哈希: 0xdef456...
[17:46:35] ✓ 提现交易已提交！

[17:46:35] [4/5] 等待提现可以 finalize...
[17:46:35] 等待 120 秒...

[17:48:35] [5/5] Finalizing 提现...
[17:48:37] Finalize 交易哈希: 0xghi789...
[17:48:37] ✓ Finalize 完成！

========================================
[17:48:37] 最终余额:
[17:48:37] L1 Base Token Balance: 90.0
[17:48:37] L2 Base Token Balance: 10.0

[17:48:37] 余额变化:
[17:48:37] L1: 100.0 -> 90.0 (-10.0)
[17:48:37] L2: 0.0 -> 10.0 (+10.0)
========================================

[17:48:37] ✓ 跨链测试完成！
```

## 环境变量说明

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `DEPOSIT_AMOUNT` | L1 → L2 存款金额 | `20` |
| `WITHDRAW_AMOUNT` | L2 → L1 提现金额 | `10` |
| `DEPOSIT_WAIT_SECONDS` | 存款后等待 L2 同步的时间（秒） | `60` |
| `WITHDRAW_FINALIZE_WAIT` | 等待提现可以 finalize 的时间（秒） | `120` |

## 常见问题

### Finalize 失败

如果看到以下错误：
```
⚠ Finalize 失败: Withdrawal is not ready to be finalized yet
提现可能还未准备好，请稍后手动执行 finalize
```

这是正常的，说明提现还未完全准备好。可以：

1. 增加 `WITHDRAW_FINALIZE_WAIT` 时间
2. 或稍后手动执行 finalize：

```bash
# 使用 zksync-cli
npx zksync-cli bridge withdraw-finalize \
  --chain dockerized-node \
  --hash <WITHDRAW_TX_HASH> \
  --l1-rpc http://127.0.0.1:8545 \
  --rpc http://127.0.0.1:3150 \
  --private-key <YOUR_PRIVATE_KEY>
```

### 余额不足

确保：
1. L1 有足够的 base tokens（至少 `DEPOSIT_AMOUNT`）
2. L1 有足够的 ETH 支付 gas 费
3. L2 有足够的 base tokens 支付 gas 费（从存款中扣除）

### 超时

如果脚本运行时间过长，可以调整等待时间：
```bash
DEPOSIT_WAIT_SECONDS=30 WITHDRAW_FINALIZE_WAIT=60 npm run bridge:base-token
```

注意：时间太短可能导致操作失败。

## 与其他脚本的区别

### depositBaseToken.ts (新)
- 完整的往返测试
- 存款 + 提现 + finalize
- 显示余额变化
- 适合测试完整流程

### depositETH.ts
- 只测试 ETH 的存款
- 在使用 ERC20 base token 的链上，ETH 作为普通 ERC20 token
- 不包含提现

### test_bridge.sh
- 使用 `zksync-cli` 的 shell 脚本版本
- 功能类似但使用不同的工具

## 相关文档

- [ZKsync Ethers SDK](https://docs.zksync.io/build/sdks/js/zksync-ethers)
- [Bridge 文档](https://docs.zksync.io/build/start-coding/quick-start/bridge-to-zksync)
- [Withdrawal Finalization](https://docs.zksync.io/build/start-coding/quick-start/withdraw-funds)
