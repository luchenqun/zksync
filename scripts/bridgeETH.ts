import { Wallet, Provider, utils } from 'zksync-ethers';
import { ethers } from 'ethers';
import dotenv from 'dotenv';

dotenv.config();

const PRIVATE_KEY = process.env.WALLET_PRIVATE_KEY || 'f78a036930ce63791ea6ea20072986d8c3f16a6811f6a2583b0787c45086f769';
const L1_RPC = process.env.L1_RPC || 'http://127.0.0.1:8545';
const L2_RPC = process.env.L2_RPC || 'http://127.0.0.1:3050';

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

async function main() {
  log('开始 L1 ↔ L2 ETH 跨链测试');
  log('========================================');
  log(`L1 RPC: ${L1_RPC}`);
  log(`L2 RPC: ${L2_RPC}`);
  log(`存款金额: ${DEPOSIT_AMOUNT} ETH`);
  log(`提现金额: ${WITHDRAW_AMOUNT} ETH`);
  log('========================================\n');

  const l1Provider = new ethers.JsonRpcProvider(L1_RPC);
  const l2Provider = new Provider(L2_RPC);
  const wallet = new Wallet(PRIVATE_KEY, l2Provider, l1Provider);

  log(`Wallet address: ${wallet.address}`);

  // === 第一步：检查初始余额 ===
  log('\n[1/5] 检查初始余额...');
  const l1BalanceBefore = await l1Provider.getBalance(wallet.address);
  const l2BalanceBefore = await l2Provider.getBalance(wallet.address);
  log(`L1 ETH Balance: ${ethers.formatEther(l1BalanceBefore)}`);
  log(`L2 ETH Balance: ${ethers.formatEther(l2BalanceBefore)}`);

  // === 第二步：存款 L1 -> L2 ===
  log(`\n[2/5] 存款 ${DEPOSIT_AMOUNT} ETH 从 L1 到 L2...`);
  const depositAmount = ethers.parseEther(DEPOSIT_AMOUNT);

  const depositTx = await wallet.deposit({
    token: utils.ETH_ADDRESS_IN_CONTRACTS,
    amount: depositAmount,
  });

  log(`存款交易哈希: ${depositTx.hash}`);
  await depositTx.wait();
  log('✓ 存款完成！');

  // 等待 L2 同步
  await sleep(DEPOSIT_WAIT_SECONDS);

  // 检查存款后余额
  const l2BalanceAfterDeposit = await l2Provider.getBalance(wallet.address);
  log(`L2 存款后余额: ${ethers.formatEther(l2BalanceAfterDeposit)}`);

  // === 第三步：提现 L2 -> L1 ===
  log(`\n[3/5] 提现 ${WITHDRAW_AMOUNT} ETH 从 L2 到 L1...`);
  const withdrawAmount = ethers.parseEther(WITHDRAW_AMOUNT);

  const withdrawTx = await wallet.withdraw({
    token: utils.ETH_ADDRESS_IN_CONTRACTS,
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
  const l2BalanceAfter = await l2Provider.getBalance(wallet.address);
  log(`L1 ETH Balance: ${ethers.formatEther(l1BalanceAfter)}`);
  log(`L2 ETH Balance: ${ethers.formatEther(l2BalanceAfter)}`);

  log('\n余额变化:');
  log(`L1: ${ethers.formatEther(l1BalanceBefore)} -> ${ethers.formatEther(l1BalanceAfter)} (${ethers.formatEther(l1BalanceAfter - l1BalanceBefore)})`);
  log(`L2: ${ethers.formatEther(l2BalanceBefore)} -> ${ethers.formatEther(l2BalanceAfter)} (${ethers.formatEther(l2BalanceAfter - l2BalanceBefore)})`);
  log('========================================\n');
  log('✓ 跨链测试完成！');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
