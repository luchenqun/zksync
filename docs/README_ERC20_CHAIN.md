# ZKsync ERC20 Base Token Chain 设置指南

本项目提供了一套完整的脚本和配置，用于创建和管理使用 ERC20 token 作为 gas 费的 ZKsync Chain。

## 目录结构

```
.
├── contracts/
│   └── CustomBaseToken.sol          # ERC20 base token 合约
├── ignition/
│   └── modules/
│       └── CustomBaseToken.ts       # Hardhat Ignition 部署模块
├── scripts/
│   ├── setup_erc20_chain.sh        # 主自动化设置脚本
│   ├── depositBaseToken.ts         # Bridge base token 到 L2
│   ├── depositETH.ts               # Bridge ETH 到 L2
│   └── test_bridge.sh              # 桥接测试脚本
├── hardhat.config.ts               # Hardhat 配置
├── package.json                    # 项目依赖
├── tsconfig.json                   # TypeScript 配置
└── .env.example                    # 环境变量模板

```

## 前置要求

1. Docker 和 Docker Compose
2. Node.js (v18+)
3. zkstack CLI
4. Foundry (cast 命令)
5. yq (YAML 处理工具)

## 快速开始

### 1. 启动 L1 节点

确保你的 L1 节点（reth）已经在运行：

```bash
zkstack containers
```

### 2. 安装依赖

```bash
npm install
```

### 3. 配置环境变量

复制 `.env.example` 到 `.env`：

```bash
cp .env.example .env
```

从 `configs/wallets.yaml` 获取 governor 的 private key，并更新 `.env` 文件中的 `WALLET_PRIVATE_KEY`。

### 4. 运行自动化设置脚本

```bash
./scripts/setup_erc20_chain.sh
```

该脚本将自动完成以下步骤：

1. 安装项目依赖
2. 部署 ERC20 token 到 L1
3. 创建新的 ZK Chain（需要手动确认配置）
4. 初始化链
5. 启动链服务器
6. Bridge base token 到 L2

### 5. 配置说明

在创建链时，脚本会提示你输入以下配置（默认值已在脚本中设置）：

- **Chain name**: `custom_zkchain`
- **Chain ID**: `272`
- **Wallet**: `Localhost`
- **Prover mode**: `NoProofs`
- **Commit data**: `Rollup`
- **Base token**: `Custom` (使用部署的 ERC20 token)
- **Token address**: 自动从部署输出获取
- **Price nominator**: `1`
- **Price denominator**: `1`
- **EVM emulator**: `true`
- **Set as default**: `true`

## 手动步骤（如果不使用自动化脚本）

### 1. 部署 ERC20 Token

```bash
npx hardhat ignition deploy ./ignition/modules/CustomBaseToken.ts --network localRethNode
```

记录输出的 token address，并更新 `.env` 文件中的 `TOKEN_ADDRESS`。

### 2. 创建链

```bash
zkstack chain create
```

按照提示输入配置，使用上面部署的 token address。

### 3. 初始化链

```bash
zkstack chain init --dev
```

### 4. 启动服务器

```bash
zkstack server
```

服务器将监听 `3150` 端口（可在 `chains/custom_zkchain/configs/general.yaml` 中查看）。

### 5. Bridge Base Token

```bash
npx hardhat run scripts/depositBaseToken.ts
```

### 6. (可选) Bridge ETH

```bash
npx hardhat run scripts/depositETH.ts
```

## NPM 脚本

```bash
# 部署 token 到 L1
npm run deploy:token

# Bridge base token 到 L2
npm run bridge:base-token

# Bridge ETH 到 L2
npm run bridge:eth
```

## 测试桥接功能

```bash
./scripts/test_bridge.sh
```

该脚本将测试：
- L1 → L2 存款
- L2 → L1 提现
- 提现的 finalization

## 环境变量说明

| 变量                 | 说明             | 默认值                  |
| -------------------- | ---------------- | ----------------------- |
| `WALLET_PRIVATE_KEY` | 部署者钱包私钥   | -                       |
| `L1_RPC`             | L1 节点 RPC URL  | `http://127.0.0.1:8545` |
| `L2_RPC`             | L2 节点 RPC URL  | `http://127.0.0.1:3150` |
| `TOKEN_ADDRESS`      | ERC20 token 地址 | 部署后自动填充          |
| `CHAIN_NAME`         | 链名称           | `custom_zkchain`        |
| `CHAIN_ID`           | 链 ID            | `272`                   |
| `TOKEN_NAME`         | Token 名称       | `ZK Base Token`         |
| `TOKEN_SYMBOL`       | Token 符号       | `ZKBT`                  |

## 常见操作

### 查看服务器日志

```bash
tail -f logs/server.log
```

### 停止服务器

```bash
kill $(cat .pids/server.pid)
```

### 切换链

```bash
zkstack ecosystem change-default-chain
zkstack server
```

### 完全关闭生态系统

```bash
docker-compose down
```

### 重启生态系统

1. 启动容器：`zkstack containers`
2. 重新部署 token：`npm run deploy:token`
3. 更新配置文件中的 token address：
   - `chains/custom_zkchain/configs/contracts.yaml` 中的 `l1.base_token_addr`
   - `chains/custom_zkchain/ZkStack.yaml` 中的 `base_token.address`
4. 初始化：`zkstack ecosystem init --dev`
5. 启动服务器：`zkstack server`
6. Bridge token：`npm run bridge:base-token`

## Base Token 与 ETH 的关系

在使用 ERC20 作为 base token 的链上：

- **Base Token**: 用作 gas 费，在 L2 上的余额可通过 `wallet.getBalance()` 查询
- **ETH**: 作为普通 ERC20 token，有独立的 L2 合约地址，需要使用 `l2TokenAddress(ETH_ADDRESS_IN_CONTRACTS)` 获取地址

## Price Nominator 和 Denominator

这两个参数用于定义 base token 与 ETH 的价格关系：

- **关系**: `价格比率 = nominator / denominator`
- **示例**: 如果 `nominator=20, denominator=1`，则 20 个 token 的价值等于 1 ETH 的 gas 成本
- **测试用途**: 建议使用 `1:1` 比率

## 故障排除

### Token 部署失败

- 检查 L1 节点是否运行
- 验证 `WALLET_PRIVATE_KEY` 是否正确
- 确保钱包有足够的 L1 ETH

### 链初始化失败

- 确保之前的链服务器已停止
- 检查 token address 是否正确
- 查看日志文件了解详细错误

### Bridge 失败

- 确保 L2 节点完全启动
- 检查钱包是否有足够的 token
- 验证 RPC URLs 是否正确

## 文件说明

### CustomBaseToken.sol

标准的 ERC20 token 合约，包含：
- 初始铸造 100 个 token 给部署者
- Owner 可以铸造更多 token
- 可销毁功能

### depositBaseToken.ts

使用 `zksync-ethers` SDK bridge base token 到 L2：
- 自动批准 ERC20 token
- 执行 deposit 操作
- 显示 L1 和 L2 余额

### depositETH.ts

Bridge 常规 ETH 到使用 ERC20 base token 的链：
- 获取 L2 ETH token 地址
- 执行 ETH deposit
- 显示 L2 ETH token 余额

## 参考文档

- [ZKsync Documentation](https://docs.zksync.io/)
- [zkstack CLI](https://github.com/matter-labs/zksync-era)
- [Customizing Your Chain](./docs/customizing-your-chain.md)
