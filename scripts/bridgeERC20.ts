import { Wallet, Provider, utils } from 'zksync-ethers';
import { ethers } from 'ethers';
import * as fs from 'fs';
import * as path from 'path';
import dotenv from 'dotenv';

dotenv.config();

const PRIVATE_KEY = process.env.WALLET_PRIVATE_KEY || 'f78a036930ce63791ea6ea20072986d8c3f16a6811f6a2583b0787c45086f769';
const L1_RPC = process.env.L1_RPC || 'http://127.0.0.1:8545';
const L2_RPC_PRIMARY = process.env.L2_RPC || 'http://127.0.0.1:3050';

// 配置参数
const TOKEN_NAME = 'USD Coin';
const now = new Date();
const pad = (n: number) => n.toString().padStart(2, '0');
const formattedDateTime = `${pad(now.getMonth() + 1)}${pad(now.getDate())}${pad(now.getHours())}${pad(now.getMinutes())}${pad(now.getSeconds())}`;
const TOKEN_SYMBOL = `USDC-${formattedDateTime}`;
const DEPOSIT_AMOUNT = '100'; // L1 -> L2
const WITHDRAW_AMOUNT = '10'; // L2 -> L1
const DEPOSIT_WAIT_SECONDS = parseInt(process.env.DEPOSIT_WAIT_SECONDS || '10');
const WITHDRAW_FINALIZE_WAIT = parseInt(process.env.WITHDRAW_FINALIZE_WAIT || '120');

// 加载 CustomBaseToken artifact
function loadCustomBaseTokenArtifact() {
  const artifactPath = path.join(__dirname, '../artifacts/contracts/CustomBaseToken.sol/CustomBaseToken.json');
  const artifactJson = fs.readFileSync(artifactPath, 'utf8');
  return JSON.parse(artifactJson);
}

function log(message: string) {
  const timestamp = new Date().toLocaleTimeString();
  console.log(`\x1b[32m[${timestamp}]\x1b[0m ${message}`);
}

async function sleep(seconds: number) {
  log(`等待 ${seconds} 秒...`);
  await new Promise((resolve) => setTimeout(resolve, seconds * 1000));
}

async function testRpcConnection(rpc: string): Promise<boolean> {
  try {
    const provider = new Provider(rpc, undefined, {
      staticNetwork: true,
      batchMaxCount: 1,
    });
    await provider.getNetwork();
    return true;
  } catch (error) {
    return false;
  }
}

async function getWorkingL2Rpc(primaryRpc: string): Promise<string> {
  log(`测试主 RPC: ${primaryRpc}`);
  if (await testRpcConnection(primaryRpc)) {
    log(`✓ 主 RPC 连接成功`);
    return primaryRpc;
  }

  const fallbackRpc = primaryRpc.includes(':3050') ? primaryRpc.replace(':3050', ':3150') : primaryRpc.replace(':3150', ':3050');

  log(`⚠ 主 RPC 连接失败，尝试备用 RPC: ${fallbackRpc}`);
  if (await testRpcConnection(fallbackRpc)) {
    log(`✓ 备用 RPC 连接成功`);
    return fallbackRpc;
  }

  throw new Error(`无法连接到 L2 RPC，已尝试: ${primaryRpc}, ${fallbackRpc}`);
}

async function deployERC20(wallet: ethers.Wallet, name: string, symbol: string): Promise<string> {
  log(`部署 ${name}, 符号: ${symbol} 代币...`);

  // 加载编译后的合约
  const artifact = loadCustomBaseTokenArtifact();
  const factory = new ethers.ContractFactory(artifact.abi, artifact.bytecode, wallet);

  // CustomBaseToken 构造函数只需要 name 和 symbol，初始供应量固定为 100000000
  const contract = await factory.deploy(name, symbol);
  await contract.waitForDeployment();

  const address = await contract.getAddress();
  const totalSupply = await contract.totalSupply();
  log(`✓ ${TOKEN_NAME}, ${TOKEN_SYMBOL} 代币部署成功: ${address}`);
  log(`总供应量: ${ethers.formatEther(totalSupply)} ${symbol}`);

  return address;
}

async function main() {
  log('开始 L1 ↔ L2 ERC20 跨链测试');
  log('========================================');

  // 测试并获取可用的 L2 RPC
  const L2_RPC = await getWorkingL2Rpc(L2_RPC_PRIMARY);

  log(`L1 RPC: ${L1_RPC}`);
  log(`L2 RPC: ${L2_RPC}`);
  log(`代币名称: ${TOKEN_NAME}`);
  log(`代币符号: ${TOKEN_SYMBOL}`);
  log(`存款金额: ${DEPOSIT_AMOUNT} ${TOKEN_SYMBOL}`);
  log(`提现金额: ${WITHDRAW_AMOUNT} ${TOKEN_SYMBOL}`);
  log('========================================\n');

  const l1Provider = new ethers.JsonRpcProvider(L1_RPC);
  const l2Provider = new Provider(L2_RPC);
  const wallet = new Wallet(PRIVATE_KEY, l2Provider, l1Provider);

  log(`Wallet address: ${wallet.address}`);

  // === 第一步：部署 ERC20 代币到 L1 ===
  log(`\n[1/6] 部署 ${TOKEN_NAME}, ${TOKEN_SYMBOL} 代币到 L1...`);
  // 创建标准的 ethers.Wallet 用于 L1 部署
  const l1Wallet = new ethers.Wallet(PRIVATE_KEY, l1Provider);
  const tokenAddress = await deployERC20(l1Wallet, TOKEN_NAME, TOKEN_SYMBOL);

  // 加载合约 ABI 并创建代币合约实例
  const artifact = loadCustomBaseTokenArtifact();
  const l1TokenContract = new ethers.Contract(tokenAddress, artifact.abi, l1Wallet);

  // === 第二步：检查初始余额 ===
  log('\n[2/6] 检查初始余额...');
  const l1BalanceBefore = await l1TokenContract.balanceOf(wallet.address);
  log(`L1 ${TOKEN_SYMBOL} Balance: ${ethers.formatEther(l1BalanceBefore)}`);

  // === 第三步：存款 L1 -> L2 ===
  log(`\n[3/6] 存款 ${DEPOSIT_AMOUNT} ${TOKEN_SYMBOL} 从 L1 到 L2...`);
  const depositAmount = ethers.parseEther(DEPOSIT_AMOUNT);

  const depositTx = await wallet.deposit({
    token: tokenAddress,
    amount: depositAmount,
    approveERC20: true,
  });

  log(`存款交易哈希: ${depositTx.hash}`);
  await depositTx.wait();
  log('✓ 存款完成！');

  // 等待 L2 同步
  await sleep(DEPOSIT_WAIT_SECONDS);

  // 获取 L2 代币地址
  const l2TokenAddress = await l2Provider.l2TokenAddress(tokenAddress);
  log(`L2 代币地址: ${l2TokenAddress}`);

  // 检查存款后余额
  const l2TokenContract = new ethers.Contract(l2TokenAddress, artifact.abi, wallet.connect(l2Provider));
  const l2BalanceAfterDeposit = await l2TokenContract.balanceOf(wallet.address);
  log(`L2 存款后余额: ${ethers.formatEther(l2BalanceAfterDeposit)}`);

  // === 第四步：提现 L2 -> L1 ===
  log(`\n[4/6] 提现 ${WITHDRAW_AMOUNT} ${TOKEN_SYMBOL} 从 L2 到 L1...`);
  const withdrawAmount = ethers.parseEther(WITHDRAW_AMOUNT);

  const withdrawTx = await wallet.withdraw({
    token: l2TokenAddress,
    amount: withdrawAmount,
  });

  log(`提现交易哈希: ${withdrawTx.hash}`);
  await withdrawTx.wait();
  log('✓ 提现交易已提交！');

  // === 第五步：等待并 Finalize 提现 ===
  log(`\n[5/6] 等待并 Finalize 提现...`);

  const CHECK_INTERVAL = 3; // 每 3 秒重试一次
  let waitedTime = 0;
  let finalized = false;

  while (waitedTime < WITHDRAW_FINALIZE_WAIT && !finalized) {
    try {
      log(`尝试 finalize... (${waitedTime}s/${WITHDRAW_FINALIZE_WAIT}s)`);
      const finalizeWithdrawTx = await wallet.finalizeWithdrawal(withdrawTx.hash);
      log(`Finalize 交易哈希: ${finalizeWithdrawTx.hash}`);
      await finalizeWithdrawTx.wait();
      log(`✓ Finalize 完成！(等待了 ${waitedTime} 秒)`);
      finalized = true;
    } catch (error: any) {
      await new Promise((resolve) => setTimeout(resolve, CHECK_INTERVAL * 1000));
      waitedTime += CHECK_INTERVAL;
    }
  }

  if (!finalized) {
    log(`⚠ Finalize 超时或失败，请稍后手动执行 finalize`);
    log(`提现交易哈希: ${withdrawTx.hash}`);
  }

  // === 第六步：最终余额检查 ===
  log('\n========================================');
  log('[6/6] 最终余额:');
  const l1BalanceAfter = await l1TokenContract.balanceOf(wallet.address);
  const l2BalanceAfter = await l2TokenContract.balanceOf(wallet.address);
  log(`L1 ${TOKEN_SYMBOL} Balance: ${ethers.formatEther(l1BalanceAfter)}`);
  log(`L2 ${TOKEN_SYMBOL} Balance: ${ethers.formatEther(l2BalanceAfter)}`);

  log('\n余额变化:');
  log(`L1: ${ethers.formatEther(l1BalanceBefore)} -> ${ethers.formatEther(l1BalanceAfter)} (${ethers.formatEther(l1BalanceAfter - l1BalanceBefore)})`);
  log(`L2: 0 -> ${ethers.formatEther(l2BalanceAfter)} (+${ethers.formatEther(l2BalanceAfter)})`);
  log('========================================\n');
  log('✓ 跨链测试完成！');
  log(`\nL1 代币地址: ${tokenAddress}`);
  log(`L2 代币地址: ${l2TokenAddress}`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
