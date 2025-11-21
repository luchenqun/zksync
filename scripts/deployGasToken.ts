import { ethers } from 'ethers';
import fs from 'fs';
import path from 'path';
import dotenv from 'dotenv';

dotenv.config();

const PROJECT_ROOT = path.resolve(__dirname, '..');
const ENV_FILE = path.join(PROJECT_ROOT, '.env');
const DEPLOY_LOG = path.join(PROJECT_ROOT, 'logs', 'token-deploy.log');

const PRIVATE_KEY = process.env.WALLET_PRIVATE_KEY || '0xf12e28c0eb1ef4ff90478f6805b68d63737b7f33abfa091601140805da450d93';
const L1_RPC = process.env.L1_RPC || 'http://127.0.0.1:8545';
const TOKEN_NAME = process.env.TOKEN_NAME || 'Gas Token';
const TOKEN_SYMBOL = process.env.TOKEN_SYMBOL || 'Gas';

function log(message: string) {
  const timestamp = new Date().toLocaleTimeString();
  console.log(`\x1b[32m[${timestamp}]\x1b[0m ${message}`);
}

function error(message: string) {
  const timestamp = new Date().toLocaleTimeString();
  console.error(`\x1b[31m[${timestamp}] ERROR:\x1b[0m ${message}`);
}

// 加载 CustomBaseToken artifact
function loadCustomBaseTokenArtifact() {
  const artifactPath = path.join(PROJECT_ROOT, 'artifacts/contracts/CustomBaseToken.sol/CustomBaseToken.json');
  if (!fs.existsSync(artifactPath)) {
    throw new Error(`合约 artifact 不存在: ${artifactPath}\n请先运行: npm run build`);
  }
  const artifactJson = fs.readFileSync(artifactPath, 'utf8');
  return JSON.parse(artifactJson);
}

// 部署合约
async function deployToken(wallet: ethers.Wallet, name: string, symbol: string): Promise<string> {
  log(`部署 ${name} (${symbol}) 代币到 L1...`);

  const artifact = loadCustomBaseTokenArtifact();
  const factory = new ethers.ContractFactory(artifact.abi, artifact.bytecode, wallet);

  log('发送部署交易...');
  const contract = await factory.deploy(name, symbol);

  log('等待部署确认...');
  await contract.waitForDeployment();

  const address = await contract.getAddress();

  // 创建合约实例以调用方法
  const tokenContract = new ethers.Contract(address, artifact.abi, wallet);
  const totalSupply = await tokenContract.totalSupply();

  log(`✓ 代币部署成功: ${address}`);
  log(`总供应量: ${ethers.formatEther(totalSupply)} ${symbol}`);

  return address;
}

function updateEnvFile(tokenAddress: string) {
  log('更新 .env 文件...');

  let envContent = '';
  if (fs.existsSync(ENV_FILE)) {
    envContent = fs.readFileSync(ENV_FILE, 'utf8');
  }

  // 检查是否已有 TOKEN_ADDRESS
  if (envContent.includes('TOKEN_ADDRESS=')) {
    // 替换现有的
    envContent = envContent.replace(/TOKEN_ADDRESS=.*/, `TOKEN_ADDRESS=${tokenAddress}`);
  } else {
    // 添加新的
    envContent += `\nTOKEN_ADDRESS=${tokenAddress}\n`;
  }

  fs.writeFileSync(ENV_FILE, envContent);
  log(`✓ 已更新 .env: TOKEN_ADDRESS=${tokenAddress}`);
}

function updateZkStackYaml(tokenAddress: string) {
  const chainName = process.env.CHAIN_NAME || 'custom_zkchain';
  const zkStackYamlPath = path.join(PROJECT_ROOT, 'chains', chainName, 'ZkStack.yaml');

  if (!fs.existsSync(zkStackYamlPath)) {
    log(`⚠ 链配置文件不存在，跳过更新: ${zkStackYamlPath}`);
    return;
  }

  log(`更新 ${chainName}/ZkStack.yaml...`);

  let content = fs.readFileSync(zkStackYamlPath, 'utf8');

  // 更新 base_token.address
  if (content.includes('base_token:')) {
    content = content.replace(/(base_token:\s*\n\s*address:\s*).*/, `$1${tokenAddress}`);
  }

  fs.writeFileSync(zkStackYamlPath, content);
  log(`✓ 已更新 ${chainName}/ZkStack.yaml: base_token.address=${tokenAddress}`);
}

function updateContractsYaml(tokenAddress: string) {
  const chainName = process.env.CHAIN_NAME || 'custom_zkchain';
  const contractsYamlPath = path.join(PROJECT_ROOT, 'chains', chainName, 'configs', 'contracts.yaml');

  if (!fs.existsSync(contractsYamlPath)) {
    log(`⚠ 合约配置文件不存在，跳过更新: ${contractsYamlPath}`);
    return;
  }

  log(`更新 ${chainName}/configs/contracts.yaml...`);

  let content = fs.readFileSync(contractsYamlPath, 'utf8');

  // 更新 l1.base_token_addr
  if (content.includes('base_token_addr:')) {
    content = content.replace(/(base_token_addr:\s*).*/, `$1${tokenAddress}`);
  }

  fs.writeFileSync(contractsYamlPath, content);
  log(`✓ 已更新 ${chainName}/configs/contracts.yaml: l1.base_token_addr=${tokenAddress}`);
}

function updatePortalConfig(tokenAddress: string) {
  const chainName = process.env.CHAIN_NAME || 'custom_zkchain';
  const portalConfigPath = path.join(PROJECT_ROOT, 'configs', 'apps', 'portal.config.json');

  if (!fs.existsSync(portalConfigPath)) {
    log(`⚠ Portal 配置文件不存在，跳过更新: ${portalConfigPath}`);
    return;
  }

  log(`更新 configs/apps/portal.config.json...`);

  const content = fs.readFileSync(portalConfigPath, 'utf8');
  const config = JSON.parse(content);

  // 查找对应的链配置
  if (config.hyperchainsConfig && Array.isArray(config.hyperchainsConfig)) {
    for (const chain of config.hyperchainsConfig) {
      if (chain.network && chain.network.key === chainName) {
        // 更新 tokens 中的 l1Address
        if (chain.tokens && Array.isArray(chain.tokens)) {
          for (const token of chain.tokens) {
            // 更新 base token 的 l1Address（通常是第一个 token）
            if (token.address === '0x000000000000000000000000000000000000800A') {
              token.l1Address = tokenAddress;
              log(`✓ 更新了 ${chainName} 的 base token l1Address`);
              break;
            }
          }
        }
        break;
      }
    }
  }

  // 保存更新后的配置
  fs.writeFileSync(portalConfigPath, JSON.stringify(config, null, 2) + '\n');
  log(`✓ 已更新 configs/apps/portal.config.json: l1Address=${tokenAddress}`);
}

function updateExplorerConfig(tokenAddress: string) {
  const chainName = process.env.CHAIN_NAME || 'custom_zkchain';
  const explorerConfigPath = path.join(PROJECT_ROOT, 'configs', 'apps', 'explorer.config.json');

  if (!fs.existsSync(explorerConfigPath)) {
    log(`⚠ Explorer 配置文件不存在，跳过更新: ${explorerConfigPath}`);
    return;
  }

  log(`更新 configs/apps/explorer.config.json...`);

  const content = fs.readFileSync(explorerConfigPath, 'utf8');
  const config = JSON.parse(content);

  // 查找对应的网络配置
  if (config.environmentConfig && config.environmentConfig.networks && Array.isArray(config.environmentConfig.networks)) {
    for (const network of config.environmentConfig.networks) {
      if (network.name === chainName) {
        network.baseTokenAddress = tokenAddress;
        log(`✓ 更新了 ${chainName} 的 baseTokenAddress`);
        break;
      }
    }
  }

  // 保存更新后的配置
  fs.writeFileSync(explorerConfigPath, JSON.stringify(config, null, 2) + '\n');
  log(`✓ 已更新 configs/apps/explorer.config.json: baseTokenAddress=${tokenAddress}`);
}

async function main() {
  try {
    log('开始部署 ERC20 Base Token...');
    log('=========================================');
    log(`L1 RPC: ${L1_RPC}`);
    log(`代币名称: ${TOKEN_NAME}`);
    log(`代币符号: ${TOKEN_SYMBOL}`);
    log('=========================================\n');

    // 创建 logs 目录
    const logsDir = path.join(PROJECT_ROOT, 'logs');
    if (!fs.existsSync(logsDir)) {
      fs.mkdirSync(logsDir, { recursive: true });
    }

    // 创建 provider 和 wallet
    log('连接到 L1...');
    const provider = new ethers.JsonRpcProvider(L1_RPC);
    const wallet = new ethers.Wallet(PRIVATE_KEY, provider);

    const balance = await provider.getBalance(wallet.address);
    log(`钱包地址: ${wallet.address}`);
    log(`钱包余额: ${ethers.formatEther(balance)} ETH\n`);

    if (balance === 0n) {
      error('钱包余额不足，无法部署合约');
      process.exit(1);
    }

    // 执行部署
    const tokenAddress = await deployToken(wallet, TOKEN_NAME, TOKEN_SYMBOL);

    // 保存部署日志
    const deployInfo = {
      timestamp: new Date().toISOString(),
      tokenAddress,
      tokenName: TOKEN_NAME,
      tokenSymbol: TOKEN_SYMBOL,
      deployer: wallet.address,
      l1Rpc: L1_RPC,
    };
    fs.writeFileSync(DEPLOY_LOG, JSON.stringify(deployInfo, null, 2));

    // 更新配置文件
    log('\n开始更新配置文件...');
    updateEnvFile(tokenAddress);
    updateZkStackYaml(tokenAddress);
    updateContractsYaml(tokenAddress);
    updatePortalConfig(tokenAddress);
    updateExplorerConfig(tokenAddress);

    log('\n=========================================');
    log('部署完成！');
    log('=========================================');
    log(`Token Address: ${tokenAddress}`);
    log(`Token Name: ${TOKEN_NAME}`);
    log(`Token Symbol: ${TOKEN_SYMBOL}`);
    log('\n已自动更新以下文件:');
    log('  - .env');
    log('  - chains/custom_zkchain/ZkStack.yaml');
    log('  - chains/custom_zkchain/configs/contracts.yaml');
    log('  - configs/apps/portal.config.json');
    log('  - configs/apps/explorer.config.json');
    log('=========================================\n');
  } catch (err) {
    error(`发生错误: ${err}`);
    if (err instanceof Error) {
      console.error(err.stack);
    }
    process.exit(1);
  }
}

main();
