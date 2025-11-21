import { Wallet, Provider, utils } from 'zksync-ethers';
import { ethers } from 'ethers';
import dotenv from 'dotenv';

dotenv.config();

const PRIVATE_KEY = process.env.WALLET_PRIVATE_KEY || 'f78a036930ce63791ea6ea20072986d8c3f16a6811f6a2583b0787c45086f769';
const L1_RPC = process.env.L1_RPC || 'http://127.0.0.1:8545';
const L2_RPC = process.env.L2_RPC || 'http://127.0.0.1:3150';

async function main() {
  console.log(`L1 RPC: ${L1_RPC}`);
  console.log(`L2 RPC: ${L2_RPC}`);

  const l1Provider = new ethers.JsonRpcProvider(L1_RPC);
  const l2Provider = new Provider(L2_RPC);
  const wallet = new Wallet(PRIVATE_KEY, l2Provider, l1Provider);

  console.log(`Wallet address: ${wallet.address}`);

  // Get L2 ETH token address
  const l2EthAddress = await l2Provider.l2TokenAddress(utils.ETH_ADDRESS_IN_CONTRACTS);
  console.log(`L2 ETH Token Address: ${l2EthAddress}`);

  // Check L1 ETH balance
  const l1EthBalance = await l1Provider.getBalance(wallet.address);
  console.log(`L1 ETH Balance: ${ethers.formatEther(l1EthBalance)}`);

  // Deposit ETH to L2
  const depositAmount = ethers.parseEther('20');
  console.log(`\nDepositing ${ethers.formatEther(depositAmount)} ETH to L2...`);

  const depositTx = await wallet.deposit({
    token: utils.ETH_ADDRESS_IN_CONTRACTS,
    amount: depositAmount,
  });

  console.log(`Deposit transaction hash: ${depositTx.hash}`);

  // Wait for L1 transaction
  const l1Receipt = await depositTx.wait();
  console.log('L1 deposit transaction confirmed!');

  // Wait for L2 transaction to be processed
  console.log('Waiting for L2 transaction to be processed...');
  const l2Receipt = await depositTx.waitL2();
  console.log(`L2 transaction hash: ${l2Receipt.transactionHash}`);
  console.log('Deposit completed on L2!');

  // Check L2 ETH token balance
  const l2Erc20ABI = ['function balanceOf(address) view returns (uint256)'];
  const l2EthContract = new ethers.Contract(l2EthAddress, l2Erc20ABI, wallet.connect(l2Provider));
  const l2EthBalance = await l2EthContract.balanceOf(wallet.address);
  console.log(`L2 ETH Token Balance: ${ethers.formatEther(l2EthBalance)}`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
