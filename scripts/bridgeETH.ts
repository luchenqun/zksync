import { Wallet, Provider, utils } from 'zksync-ethers';
import { ethers } from 'ethers';
import dotenv from 'dotenv';

dotenv.config();

const PRIVATE_KEY = process.env.WALLET_PRIVATE_KEY || 'f78a036930ce63791ea6ea20072986d8c3f16a6811f6a2583b0787c45086f769';
const L1_RPC = process.env.L1_RPC || 'http://127.0.0.1:8545';
const L2_RPC_PRIMARY = process.env.L2_RPC || 'http://127.0.0.1:3050';

// 配置参数
const DEPOSIT_AMOUNT = process.env.DEPOSIT_AMOUNT || '20'; // L1 -> L2
const WITHDRAW_AMOUNT = process.env.WITHDRAW_AMOUNT || '10'; // L2 -> L1
const DEPOSIT_WAIT_SECONDS = parseInt(process.env.DEPOSIT_WAIT_SECONDS || '10');
const WITHDRAW_FINALIZE_WAIT = parseInt(process.env.WITHDRAW_FINALIZE_WAIT || '120');

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
    // 创建一个带超时的 Provider，禁用自动重试
    const provider = new Provider(rpc, undefined, {
      staticNetwork: true,
      batchMaxCount: 1,
    });
    await provider.getNetwork();
    return true;
  } catch (error) {
    log(`测试 RPC 连接失败: ${rpc} ${error}`);
    return false;
  }
}

async function getWorkingL2Rpc(primaryRpc: string): Promise<string> {
  log(`测试主 RPC: ${primaryRpc}`);
  if (await testRpcConnection(primaryRpc)) {
    log(`✓ 主 RPC 连接成功`);
    return primaryRpc;
  }

  // 确定备用 RPC
  const fallbackRpc = primaryRpc.includes(':3050') ? primaryRpc.replace(':3050', ':3150') : primaryRpc.replace(':3150', ':3050');

  log(`⚠ 主 RPC 连接失败，尝试备用 RPC: ${fallbackRpc}`);
  if (await testRpcConnection(fallbackRpc)) {
    log(`✓ 备用 RPC 连接成功`);
    return fallbackRpc;
  }

  throw new Error(`无法连接到 L2 RPC，已尝试: ${primaryRpc}, ${fallbackRpc}`);
}

async function main() {
  log('开始 L1 ↔ L2 ETH 跨链测试');
  log('========================================');

  // 测试并获取可用的 L2 RPC
  const L2_RPC = await getWorkingL2Rpc(L2_RPC_PRIMARY);

  log(`L1 RPC: ${L1_RPC}`);
  log(`L2 RPC: ${L2_RPC}`);
  log(`存款金额: ${DEPOSIT_AMOUNT} ETH`);
  log(`提现金额: ${WITHDRAW_AMOUNT} ETH`);
  log('========================================\n');

  const l1Provider = new ethers.JsonRpcProvider(L1_RPC);
  const l2Provider = new Provider(L2_RPC);
  const wallet = new Wallet(PRIVATE_KEY, l2Provider, l1Provider);

  log(`Wallet address: ${wallet.address}`);

  // 检测 L2 是否使用 ETH 作为 base token
  log('\n检测 L2 配置...');
  const baseTokenAddress = await l2Provider.getBaseTokenContractAddress();
  const isETHBaseToken = baseTokenAddress.toLowerCase() === utils.ETH_ADDRESS_IN_CONTRACTS.toLowerCase();
  log(`L2 Base Token: ${baseTokenAddress}`);
  log(`使用 ETH 作为 gas: ${isETHBaseToken ? '是' : '否'}`);

  // 获取 ETH 在 L2 上的地址
  const l2EthTokenAddress = await l2Provider.l2TokenAddress(utils.ETH_ADDRESS_IN_CONTRACTS);
  if (!isETHBaseToken) {
    log(`L2 上的 ETH token 地址: ${l2EthTokenAddress}`);
    log('ℹ️  此链使用自定义 base token 作为 gas，ETH 将作为普通 ERC20 跨链\n');
  }

  // === 第一步：检查初始余额 ===
  log('[1/5] 检查初始余额...');
  const l1BalanceBefore = await l1Provider.getBalance(wallet.address);

  // 如果使用自定义 base token，检查 L1 上的 base token 余额
  if (!isETHBaseToken) {
    const erc20ABI = ['function balanceOf(address) view returns (uint256)', 'function symbol() view returns (string)'];
    const baseTokenContract = new ethers.Contract(baseTokenAddress, erc20ABI, l1Provider);
    const baseTokenBalance = await baseTokenContract.balanceOf(wallet.address);
    const baseTokenSymbol = await baseTokenContract.symbol();
    log(`L1 ${baseTokenSymbol} Balance (gas token): ${ethers.formatEther(baseTokenBalance)}`);

    if (baseTokenBalance === 0n) {
      log('\n========================================');
      log('⚠️  错误: L1 上没有 base token 余额');
      log('========================================');
      log(`您需要 ${baseTokenSymbol} 来支付 L2 的 gas 费用`);
      log(`Base Token 地址: ${baseTokenAddress}`);
      log('请先获取一些 base token 再进行存款');
      log('========================================\n');
      process.exit(1);
    }
  }

  // 查询 L2 上的 ETH 余额
  let l2EthBalanceBefore = 0n;
  if (isETHBaseToken) {
    // ETH 是 base token，直接查余额
    l2EthBalanceBefore = await l2Provider.getBalance(wallet.address);
  } else {
    // ETH 是普通 ERC20，查询 token 余额
    try {
      const erc20ABI = ['function balanceOf(address) view returns (uint256)'];
      const l2EthContract = new ethers.Contract(l2EthTokenAddress, erc20ABI, l2Provider);
      l2EthBalanceBefore = await l2EthContract.balanceOf(wallet.address);
    } catch (error) {
      // 如果查询失败（比如合约还未部署），默认为 0
      log(`⚠️  无法查询 L2 ETH 余额，可能是首次存款，默认为 0`);
      l2EthBalanceBefore = 0n;
    }
  }

  log(`L1 ETH Balance: ${ethers.formatEther(l1BalanceBefore)}`);
  log(`L2 ETH Balance: ${ethers.formatEther(l2EthBalanceBefore)}`);

  // === 第二步：存款 L1 -> L2 ===
  log(`\n[2/5] 存款 ${DEPOSIT_AMOUNT} ETH 从 L1 到 L2...`);
  const depositAmount = ethers.parseEther(DEPOSIT_AMOUNT);

  // 如果 L2 使用自定义 base token，需要 approve base token 用于支付 gas
  const depositTx = await wallet.deposit({
    token: utils.ETH_ADDRESS_IN_CONTRACTS,
    amount: depositAmount,
    approveBaseERC20: !isETHBaseToken, // 如果不是 ETH，需要 approve base token
    approveERC20: false, // ETH 不需要 approve
  });

  log(`存款交易哈希: ${depositTx.hash}`);
  await depositTx.wait();
  log('✓ 存款完成！');

  // 等待 L2 同步
  await sleep(DEPOSIT_WAIT_SECONDS);

  // 检查存款后余额
  let l2EthBalanceAfterDeposit = 0n;
  if (isETHBaseToken) {
    l2EthBalanceAfterDeposit = await l2Provider.getBalance(wallet.address);
  } else {
    try {
      const erc20ABI = ['function balanceOf(address) view returns (uint256)'];
      const l2EthContract = new ethers.Contract(l2EthTokenAddress, erc20ABI, l2Provider);
      l2EthBalanceAfterDeposit = await l2EthContract.balanceOf(wallet.address);
    } catch (error) {
      log(`⚠️  无法查询存款后余额`);
      l2EthBalanceAfterDeposit = 0n;
    }
  }
  log(`L2 存款后余额: ${ethers.formatEther(l2EthBalanceAfterDeposit)}`);

  // === 第三步：提现 L2 -> L1 ===
  log(`\n[3/5] 提现 ${WITHDRAW_AMOUNT} ETH 从 L2 到 L1...`);
  const withdrawAmount = ethers.parseEther(WITHDRAW_AMOUNT);

  const withdrawTx = await wallet.withdraw({
    token: l2EthTokenAddress,
    amount: withdrawAmount,
  });

  log(`提现交易哈希: ${withdrawTx.hash}`);
  await withdrawTx.wait();
  log('✓ 提现交易已提交！');

  // === 第四步 & 第五步：等待并 Finalize 提现 ===
  log(`\n[4/5] 等待并 Finalize 提现...`);

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

  // === 最终余额检查 ===
  log('\n========================================');
  log('最终余额:');
  const l1BalanceAfter = await l1Provider.getBalance(wallet.address);

  let l2EthBalanceAfter = 0n;
  if (isETHBaseToken) {
    l2EthBalanceAfter = await l2Provider.getBalance(wallet.address);
  } else {
    try {
      const erc20ABI = ['function balanceOf(address) view returns (uint256)'];
      const l2EthContract = new ethers.Contract(l2EthTokenAddress, erc20ABI, l2Provider);
      l2EthBalanceAfter = await l2EthContract.balanceOf(wallet.address);
    } catch (error) {
      log(`⚠️  无法查询最终余额`);
      l2EthBalanceAfter = 0n;
    }
  }

  log(`L1 ETH Balance: ${ethers.formatEther(l1BalanceAfter)}`);
  log(`L2 ETH Balance: ${ethers.formatEther(l2EthBalanceAfter)}`);

  log('\n余额变化:');
  log(`L1: ${ethers.formatEther(l1BalanceBefore)} -> ${ethers.formatEther(l1BalanceAfter)} (${ethers.formatEther(l1BalanceAfter - l1BalanceBefore)})`);
  log(`L2: ${ethers.formatEther(l2EthBalanceBefore)} -> ${ethers.formatEther(l2EthBalanceAfter)} (${ethers.formatEther(l2EthBalanceAfter - l2EthBalanceBefore)})`);
  log('========================================\n');
  log('✓ 跨链测试完成！');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
