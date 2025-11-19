# ERC20 Token 部署与配置自动化指南

## 功能说明

执行 `npm run deploy:token` 后，系统会自动：

1. 部署 ERC20 token 到 L1
2. 提取部署的 token 地址
3. 自动更新以下配置文件中的 token 地址：
   - `.env` 文件中的 `TOKEN_ADDRESS`
   - `chains/custom_zk_chain/ZkStack.yaml` 中的 `base_token.address`
   - `chains/custom_zk_chain/configs/contracts.yaml` 中的 `l1.base_token_addr`

## 使用方法

### 方法一：使用 npm 命令（推荐）

```bash
npm run deploy:token
```

这会执行 `scripts/deployToken.ts`，自动完成部署和配置更新。

### 方法二：使用 Shell 脚本

```bash
./scripts/deploy_token.sh
```

这也会自动完成部署和配置更新。

### 方法三：手动更新配置

如果你已经有一个部署好的 token，可以手动更新配置：

```bash
./scripts/update_token_config.sh <TOKEN_ADDRESS>
```

例如：
```bash
./scripts/update_token_config.sh 0x1234567890123456789012345678901234567890
```

## 输出示例

```
[17:30:45] 开始部署 ERC20 Base Token...
[17:30:47] 执行 Hardhat Ignition 部署...

✔ Confirm deploy to network localRethNode (31337)? … yes
Hardhat Ignition 🚀

Deploying [ CustomBaseTokenModule ]

Batch #1
  Executed CustomBaseTokenModule#CustomBaseToken

[ CustomBaseTokenModule ] successfully deployed 🚀

Deployed Addresses

CustomBaseTokenModule#CustomBaseToken - 0x5FbDB2315678afecb367f032d93F642f64180aa3

[17:30:49] ✓ Token 部署成功: 0x5FbDB2315678afecb367f032d93F642f64180aa3

[17:30:49] 开始更新配置文件...
[17:30:49] 更新 .env 文件...
[17:30:49] ✓ 已更新 .env: TOKEN_ADDRESS=0x5FbDB2315678afecb367f032d93F642f64180aa3
[17:30:49] 更新 custom_zk_chain/ZkStack.yaml...
[17:30:49] ✓ 已更新 custom_zk_chain/ZkStack.yaml: base_token.address=0x5FbDB2315678afecb367f032d93F642f64180aa3
[17:30:49] 更新 custom_zk_chain/configs/contracts.yaml...
[17:30:49] ✓ 已更新 custom_zk_chain/configs/contracts.yaml: l1.base_token_addr=0x5FbDB2315678afecb367f032d93F642f64180aa3

=========================================
部署完成！
=========================================
Token Address: 0x5FbDB2315678afecb367f032d93F642f64180aa3
已自动更新以下文件:
  - .env
  - chains/custom_zk_chain/ZkStack.yaml
  - chains/custom_zk_chain/configs/contracts.yaml
=========================================
```

## 配置文件位置

### .env
```bash
TOKEN_ADDRESS=0x5FbDB2315678afecb367f032d93F642f64180aa3
```

### chains/custom_zk_chain/ZkStack.yaml
```yaml
base_token:
  address: 0x5FbDB2315678afecb367f032d93F642f64180aa3
  nominator: 1
  denominator: 1
```

### chains/custom_zk_chain/configs/contracts.yaml
```yaml
l1:
  base_token_addr: 0x5FbDB2315678afecb367f032d93F642f64180aa3
  # ... 其他配置
```

## 环境变量

可以通过环境变量自定义链名称：

```bash
CHAIN_NAME=my_custom_chain npm run deploy:token
```

默认链名称是 `custom_zk_chain`。

## 故障排除

### 配置文件不存在

如果链还没有创建，脚本会跳过更新 ZkStack.yaml 和 contracts.yaml：

```
⚠ 链配置文件不存在，跳过更新: chains/custom_zk_chain/ZkStack.yaml
⚠ 合约配置文件不存在，跳过更新: chains/custom_zk_chain/configs/contracts.yaml
```

解决方法：先使用 `zkstack chain create` 创建链，然后再次运行部署脚本。

### 部署失败

检查：
1. L1 节点是否运行：`docker ps`
2. 私钥是否正确：检查 `.env` 或 `configs/wallets.yaml`
3. 钱包是否有足够的 L1 ETH

### 无法提取 token 地址

查看部署日志：
```bash
cat logs/token-deploy.log
```

## 完整流程示例

```bash
# 1. 安装依赖
npm install

# 2. 启动 L1 节点
zkstack containers

# 3. 部署 token（自动更新配置）
npm run deploy:token

# 4. 创建链（使用部署的 token 地址）
zkstack chain create

# 5. 初始化链
zkstack chain init --dev

# 6. 启动链服务器
zkstack server

# 7. Bridge token 到 L2
npm run bridge:base-token
```

## 相关脚本

- `scripts/deployToken.ts` - TypeScript 部署脚本（npm 使用）
- `scripts/deploy_token.sh` - Shell 部署脚本
- `scripts/update_token_config.sh` - 手动更新配置辅助脚本
- `scripts/depositBaseToken.ts` - Bridge base token 到 L2
- `scripts/depositETH.ts` - Bridge ETH 到 L2
