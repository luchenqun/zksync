import { execSync } from "child_process";
import fs from "fs";
import path from "path";
import dotenv from "dotenv";

dotenv.config();

const PROJECT_ROOT = path.resolve(__dirname, "..");
const ENV_FILE = path.join(PROJECT_ROOT, ".env");
const DEPLOY_LOG = path.join(PROJECT_ROOT, "logs", "token-deploy.log");

function log(message: string) {
  const timestamp = new Date().toLocaleTimeString();
  console.log(`\x1b[32m[${timestamp}]\x1b[0m ${message}`);
}

function error(message: string) {
  const timestamp = new Date().toLocaleTimeString();
  console.error(`\x1b[31m[${timestamp}] ERROR:\x1b[0m ${message}`);
}

function updateEnvFile(tokenAddress: string) {
  log("更新 .env 文件...");

  let envContent = "";
  if (fs.existsSync(ENV_FILE)) {
    envContent = fs.readFileSync(ENV_FILE, "utf8");
  }

  // 检查是否已有 TOKEN_ADDRESS
  if (envContent.includes("TOKEN_ADDRESS=")) {
    // 替换现有的
    envContent = envContent.replace(
      /TOKEN_ADDRESS=.*/,
      `TOKEN_ADDRESS=${tokenAddress}`
    );
  } else {
    // 添加新的
    envContent += `\nTOKEN_ADDRESS=${tokenAddress}\n`;
  }

  fs.writeFileSync(ENV_FILE, envContent);
  log(`✓ 已更新 .env: TOKEN_ADDRESS=${tokenAddress}`);
}

function updateZkStackYaml(tokenAddress: string) {
  const chainName = process.env.CHAIN_NAME || "custom_zk_chain";
  const zkStackYamlPath = path.join(
    PROJECT_ROOT,
    "chains",
    chainName,
    "ZkStack.yaml"
  );

  if (!fs.existsSync(zkStackYamlPath)) {
    log(`⚠ 链配置文件不存在，跳过更新: ${zkStackYamlPath}`);
    return;
  }

  log(`更新 ${chainName}/ZkStack.yaml...`);

  let content = fs.readFileSync(zkStackYamlPath, "utf8");

  // 更新 base_token.address
  if (content.includes("base_token:")) {
    content = content.replace(
      /(base_token:\s*\n\s*address:\s*).*/,
      `$1${tokenAddress}`
    );
  }

  fs.writeFileSync(zkStackYamlPath, content);
  log(`✓ 已更新 ${chainName}/ZkStack.yaml: base_token.address=${tokenAddress}`);
}

function updateContractsYaml(tokenAddress: string) {
  const chainName = process.env.CHAIN_NAME || "custom_zk_chain";
  const contractsYamlPath = path.join(
    PROJECT_ROOT,
    "chains",
    chainName,
    "configs",
    "contracts.yaml"
  );

  if (!fs.existsSync(contractsYamlPath)) {
    log(`⚠ 合约配置文件不存在，跳过更新: ${contractsYamlPath}`);
    return;
  }

  log(`更新 ${chainName}/configs/contracts.yaml...`);

  let content = fs.readFileSync(contractsYamlPath, "utf8");

  // 更新 l1.base_token_addr
  if (content.includes("base_token_addr:")) {
    content = content.replace(
      /(base_token_addr:\s*).*/,
      `$1${tokenAddress}`
    );
  }

  fs.writeFileSync(contractsYamlPath, content);
  log(`✓ 已更新 ${chainName}/configs/contracts.yaml: l1.base_token_addr=${tokenAddress}`);
}

function updatePortalConfig(tokenAddress: string) {
  const chainName = process.env.CHAIN_NAME || "custom_zk_chain";
  const portalConfigPath = path.join(
    PROJECT_ROOT,
    "configs",
    "apps",
    "portal.config.json"
  );

  if (!fs.existsSync(portalConfigPath)) {
    log(`⚠ Portal 配置文件不存在，跳过更新: ${portalConfigPath}`);
    return;
  }

  log(`更新 configs/apps/portal.config.json...`);

  const content = fs.readFileSync(portalConfigPath, "utf8");
  const config = JSON.parse(content);

  // 查找对应的链配置
  if (config.hyperchainsConfig && Array.isArray(config.hyperchainsConfig)) {
    for (const chain of config.hyperchainsConfig) {
      if (chain.network && chain.network.key === chainName) {
        // 更新 tokens 中的 l1Address
        if (chain.tokens && Array.isArray(chain.tokens)) {
          for (const token of chain.tokens) {
            // 更新 base token 的 l1Address（通常是第一个 token）
            if (token.address === "0x000000000000000000000000000000000000800A") {
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
  fs.writeFileSync(portalConfigPath, JSON.stringify(config, null, 2) + "\n");
  log(`✓ 已更新 configs/apps/portal.config.json: l1Address=${tokenAddress}`);
}

function updateExplorerConfig(tokenAddress: string) {
  const chainName = process.env.CHAIN_NAME || "custom_zk_chain";
  const explorerConfigPath = path.join(
    PROJECT_ROOT,
    "configs",
    "apps",
    "explorer.config.json"
  );

  if (!fs.existsSync(explorerConfigPath)) {
    log(`⚠ Explorer 配置文件不存在，跳过更新: ${explorerConfigPath}`);
    return;
  }

  log(`更新 configs/apps/explorer.config.json...`);

  const content = fs.readFileSync(explorerConfigPath, "utf8");
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
  fs.writeFileSync(explorerConfigPath, JSON.stringify(config, null, 2) + "\n");
  log(`✓ 已更新 configs/apps/explorer.config.json: baseTokenAddress=${tokenAddress}`);
}

async function main() {
  try {
    log("开始部署 ERC20 Base Token...");

    // 创建 logs 目录
    const logsDir = path.join(PROJECT_ROOT, "logs");
    if (!fs.existsSync(logsDir)) {
      fs.mkdirSync(logsDir, { recursive: true });
    }

    // 执行部署
    log("执行 Hardhat Ignition 部署...");
    const deployCommand = "npx hardhat ignition deploy ./ignition/modules/CustomBaseToken.ts --network localRethNode --reset";

    try {
      const output = execSync(deployCommand, {
        cwd: PROJECT_ROOT,
        encoding: "utf8",
        stdio: "pipe",
      });

      // 保存日志
      fs.writeFileSync(DEPLOY_LOG, output);
      console.log(output);

      // 从输出中提取 token address
      const match = output.match(/CustomBaseToken#CustomBaseToken - (0x[0-9a-fA-F]{40})/);
      if (!match || !match[1]) {
        error("无法从部署输出中提取 token address");
        console.log("\n部署输出:");
        console.log(output);
        process.exit(1);
      }

      const tokenAddress = match[1];
      log(`\n✓ Token 部署成功: ${tokenAddress}`);

      // 更新配置文件
      log("\n开始更新配置文件...");
      updateEnvFile(tokenAddress);
      updateZkStackYaml(tokenAddress);
      updateContractsYaml(tokenAddress);
      updatePortalConfig(tokenAddress);
      updateExplorerConfig(tokenAddress);

      log("\n=========================================");
      log("部署完成！");
      log("=========================================");
      log(`Token Address: ${tokenAddress}`);
      log("已自动更新以下文件:");
      log("  - .env");
      log("  - chains/custom_zk_chain/ZkStack.yaml");
      log("  - chains/custom_zk_chain/configs/contracts.yaml");
      log("  - configs/apps/portal.config.json");
      log("  - configs/apps/explorer.config.json");
      log("=========================================\n");

    } catch (err: any) {
      error("部署失败");
      console.error(err.stdout || err.message);
      fs.writeFileSync(DEPLOY_LOG, err.stdout || err.message);
      process.exit(1);
    }

  } catch (err) {
    error(`发生错误: ${err}`);
    process.exit(1);
  }
}

main();
