# ZKsync Era 本地开发环境

本项目提供了一套完整的 ZKsync Era 本地开发环境，支持自定义 Gas Token（ERC20 作为 Base Token）、跨链桥接、区块浏览器等功能。

## 📋 目录

- [环境要求](#环境要求)
- [快速开始](#快速开始)
- [L1 操作](#l1-操作)
- [L2 操作](#l2-操作)
- [跨链操作](#跨链操作)
- [Blockscout 浏览器](#blockscout-浏览器)
- [项目结构](#项目结构)
- [常见问题](#常见问题)

## 🔧 环境要求

- Docker & Docker Compose
- Node.js >= 18
- zkstack CLI 工具
- TypeScript

## 🚀 快速开始

### 1. 安装依赖

```bash
npm install
```

### 2. 配置环境变量

复制 `.env.example` 到 `.env` 并根据需要修改配置：

```bash
cp .env.example .env
```

主要配置项：
- `L1_RPC`: L1 RPC 地址（默认：http://127.0.0.1:8545）
- `L2_RPC`: L2 RPC 地址（默认：http://127.0.0.1:3050）
- `WALLET_PRIVATE_KEY`: 钱包私钥
- `TOKEN_ADDRESS`: Gas Token 合约地址（部署后填入）

### 3. 启动完整环境

```bash
# 重置并初始化 L1 + 生态系统
./scripts/l1.sh reset-init

# 部署 Gas Token（用于 custom_zkchain）
npm run deploy:gas-token

# 初始化 custom_zkchain
./scripts/l2.sh init-custom-zkchain

# 启动 L2 服务（选择链）
./scripts/l2.sh --chain zkchain start          # ETH 作为 Gas Token
./scripts/l2.sh --chain custom_zkchain start   # 自定义 ERC20 作为 Gas Token
```

## 🔵 L1 操作

L1 脚本管理本地以太坊节点（Reth）、PostgreSQL 和 Blockscout。

### 基本命令

```bash
./scripts/l1.sh <command>
```

| 命令 | 说明 |
|------|------|
| `start` | 启动 L1 服务（Reth + Postgres + Blockscout） |
| `stop` | 停止所有 L1 服务 |
| `reset` | 重置 L1（删除数据卷并重启） |
| `reset-init` | 重置并初始化生态系统（zkstack ecosystem init） |
| `status` | 查看 L1 服务状态 |
| `init` | 初始化生态系统（不重置） |

### 示例

```bash
# 启动 L1
./scripts/l1.sh start

# 查看状态
./scripts/l1.sh status

# 完全重置（清除所有数据）
./scripts/l1.sh reset

# 重置并初始化生态系统
./scripts/l1.sh reset-init
```

### 注意事项

- `reset` 命令会：
  1. 自动检测并停止运行中的 L2 服务
  2. 停止并删除 L1 数据卷（postgres-data、reth-data）
  3. 重置 Blockscout 数据
  4. 重新启动所有服务

## 🟢 L2 操作

L2 脚本管理 ZKsync 链节点、Portal 和 Explorer。

### 访问地址

#### zkchain（默认链）
- **Portal 钱包**: http://127.0.0.1:3030
- **Block Explorer**: http://127.0.0.1:3010
- **RPC 端点**: http://127.0.0.1:3050
- **WebSocket**: ws://127.0.0.1:3051
- **Explorer API**: http://127.0.0.1:3002
- **Explorer Data Fetcher**: http://127.0.0.1:3040

#### custom_zkchain（自定义 Gas Token）
- **Portal 钱包**: http://127.0.0.1:3030
- **Block Explorer**: http://127.0.0.1:3010
- **RPC 端点**: http://127.0.0.1:3150
- **WebSocket**: ws://127.0.0.1:3151
- **Explorer API**: http://127.0.0.1:3102
- **Explorer Data Fetcher**: http://127.0.0.1:3140

### 基本命令

```bash
./scripts/l2.sh [--chain <链名称>] <command>
```

| 命令 | 说明 |
|------|------|
| `start` | 启动所有 L2 服务（Server + Portal + Explorer） |
| `stop` | 停止所有 L2 服务 |
| `restart` | 重启所有 L2 服务 |
| `status` | 查看服务状态 |
| `clean` | 清理 Explorer 数据库 |
| `init-custom-zkchain` | 初始化 custom_zkchain（需要先部署 Gas Token） |

### 单独服务控制

| 命令 | 说明 |
|------|------|
| `start-server` | 启动 L2 服务器 |
| `stop-server` | 停止 L2 服务器 |
| `start-portal` | 启动 Portal 网页钱包 |
| `stop-portal` | 停止 Portal |
| `start-explorer-backend` | 启动 Explorer 后端 |
| `stop-explorer-backend` | 停止 Explorer 后端 |
| `start-explorer` | 启动 Explorer 前端 |
| `stop-explorer` | 停止 Explorer 前端 |

### 示例

```bash
# 启动默认链（zkchain）
./scripts/l2.sh start

# 启动 custom_zkchain（使用自定义 Gas Token）
./scripts/l2.sh --chain custom_zkchain start

# 查看状态
./scripts/l2.sh --chain custom_zkchain status

# 只启动 Server
./scripts/l2.sh --chain zkchain start-server

# 清理 Explorer 数据
./scripts/l2.sh --chain custom_zkchain clean
```

### 链说明

- **zkchain**: 使用 ETH 作为 Gas Token 的标准链
- **custom_zkchain**: 使用自定义 ERC20 作为 Gas Token 的链

## 🌉 跨链操作

### 1. 部署 Gas Token

```bash
# 部署自定义 Gas Token 到 L1
npm run deploy:gas-token
```

### 2. 桥接 Gas Token

```bash
# 将 Gas Token 从 L1 桥接到 L2
npm run bridge:gas-token
```

### 3. 桥接 ETH

```bash
# 将 ETH 从 L1 桥接到 L2（双向）
npm run bridge:eth
```

**说明**：
- 在 ETH-based 链上，ETH 是原生 Gas Token
- 在 custom_zkchain 上，ETH 会被当作普通 ERC20 代币跨链

### 4. 桥接 ERC20

```bash
# 部署并桥接 ERC20 代币（双向）
npm run bridge:erc20
```

**流程**：
1. 在 L1 部署 ERC20 代币
2. 存款（L1 → L2）
3. 提现（L2 → L1）
4. Finalize 提现

### 跨链配置

在脚本中可以配置：

- `DEPOSIT_AMOUNT`: 存款数量（L1 → L2）
- `WITHDRAW_AMOUNT`: 提现数量（L2 → L1）
- `DEPOSIT_WAIT_SECONDS`: 存款后等待时间（默认 10 秒）
- `WITHDRAW_FINALIZE_WAIT`: 提现 finalize 超时时间（默认 120 秒）

## 🔍 Blockscout 浏览器

Blockscout 是一个开源的区块链浏览器，用于查看 L1 交易和区块信息。

### 访问地址

- **前端**: http://127.0.0.1:8000
- **API**: http://127.0.0.1:8000/api
- **Stats**: http://127.0.0.1:8080

### 独立管理

Blockscout 会随 L1 自动启动/停止，也可以独立管理：

```bash
cd blockscout

# 启动
./deploy.sh start

# 停止
./deploy.sh stop

# 重置（清除数据）
./deploy.sh reset
```

### 配置

主要配置文件：
- `blockscout/mud.yml`: Docker Compose 配置
- `blockscout/envs/mud-common-frontend.env`: 前端配置

## 📁 项目结构

```
.
├── scripts/
│   ├── l1.sh                      # L1 管理脚本
│   ├── l2.sh                      # L2 管理脚本
│   ├── deployGasToken.ts          # 部署 Gas Token
│   ├── bridgeGasToken.ts          # 桥接 Gas Token
│   ├── bridgeETH.ts               # 桥接 ETH
│   └── bridgeERC20.ts             # 桥接 ERC20
├── contracts/
│   └── CustomBaseToken.sol        # 自定义 Gas Token 合约
├── blockscout/                    # Blockscout 浏览器
│   ├── deploy.sh                  # Blockscout 管理脚本
│   └── mud.yml                    # Docker Compose 配置
├── chains/                        # 链配置目录
│   ├── zkchain/                   # ETH 作为 Gas Token
│   └── custom_zkchain/            # 自定义 ERC20 作为 Gas Token
├── docker-compose.yml             # L1 服务配置
├── package.json                   # NPM 脚本
├── hardhat.config.ts              # Hardhat 配置
└── .env                           # 环境变量
```

## ❓ 常见问题

### 1. L1 启动失败

**问题**: Docker 容器无法启动

**解决**:
```bash
# 检查 Docker 服务是否运行
docker ps

# 查看日志
docker logs zksync-reth-1
docker logs zksync-postgres-1

# 完全重置
./scripts/l1.sh reset
```

### 2. L2 启动失败

**问题**: zkstack server 启动失败

**解决**:
```bash
# 查看日志
cat logs/server.log

# 确保 L1 已启动
./scripts/l1.sh status

# 重新初始化
./scripts/l1.sh reset-init
```

### 3. 跨链失败

**问题**: 存款或提现交易失败

**解决**:

对于 custom_zkchain：
- 确保已部署 Gas Token：`npm run deploy:gas-token`
- 确保有足够的 Gas Token 余额
- 查看错误日志确认具体原因

对于 zkchain：
- 确保有足够的 ETH 余额

### 4. init-custom-zkchain 失败

**问题**: 提示 TOKEN_ADDRESS 不是有效的 ERC20 合约

**解决**:
```bash
# 先部署 Gas Token
npm run deploy:gas-token

# 然后再执行初始化
./scripts/l2.sh init-custom-zkchain
```

### 5. Blockscout 连接失败

**问题**: 前端无法连接到 API

**解决**:
```bash
# 重启 Blockscout
cd blockscout && ./deploy.sh reset

# 确保 L1 服务正常运行
docker ps | grep reth

# 检查网络连接
docker network inspect zksync_default
```

### 6. 端口冲突

**问题**: 端口已被占用

**解决**:
```bash
# 查看端口占用
lsof -i :8545   # L1 RPC
lsof -i :3050   # L2 RPC
lsof -i :8000   # Blockscout

# 修改 docker-compose.yml 或 .env 中的端口配置
```

## 📝 日志文件

所有日志保存在 `logs/` 目录：

- `logs/ecosystem-init.log`: 生态系统初始化日志
- `logs/chain-init-custom_zkchain.log`: custom_zkchain 初始化日志
- `logs/server.log`: L2 服务器日志
- `logs/portal.log`: Portal 日志
- `logs/explorer.log`: Explorer 前端日志

## 🔗 相关链接

- [ZKsync Era Documentation](https://docs.zksync.io/)
- [zkstack CLI Documentation](https://github.com/matter-labs/zksync-era)
- [Blockscout Documentation](https://docs.blockscout.com/)

## 📄 License

MIT
