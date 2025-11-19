import { Wallet, Provider, utils } from "zksync-ethers";
import { ethers } from "ethers";
import dotenv from "dotenv";

dotenv.config();

const PRIVATE_KEY = process.env.WALLET_PRIVATE_KEY || "";
const L1_RPC = process.env.L1_RPC || "http://127.0.0.1:8545";
const L2_RPC = process.env.L2_RPC || "http://127.0.0.1:3150";
const TOKEN_ADDRESS = process.env.TOKEN_ADDRESS || "";

async function main() {
  if (!TOKEN_ADDRESS) {
    throw new Error("TOKEN_ADDRESS is not set in .env file");
  }

  console.log(`L1 RPC: ${L1_RPC}`);
  console.log(`L2 RPC: ${L2_RPC}`);
  console.log(`Token Address: ${TOKEN_ADDRESS}`);

  const l1Provider = new ethers.JsonRpcProvider(L1_RPC);
  const l2Provider = new Provider(L2_RPC);
  const wallet = new Wallet(PRIVATE_KEY, l2Provider, l1Provider);

  console.log(`Wallet address: ${wallet.address}`);

  // Check L1 base token balance
  const l1Erc20ABI = ["function balanceOf(address) view returns (uint256)"];
  const l1Erc20Contract = new ethers.Contract(TOKEN_ADDRESS, l1Erc20ABI, wallet.connect(l1Provider));
  const l1Balance = await l1Erc20Contract.balanceOf(wallet.address);
  console.log(`L1 Base Token Balance: ${ethers.formatEther(l1Balance)}`);

  // Deposit base token to L2
  const depositAmount = ethers.parseEther("10");
  console.log(`\nDepositing ${ethers.formatEther(depositAmount)} base tokens to L2...`);

  const depositTx = await wallet.deposit({
    token: TOKEN_ADDRESS,
    amount: depositAmount,
    approveERC20: true,
    approveBaseERC20: true,
  });

  console.log(`Deposit transaction hash: ${depositTx.hash}`);
  await depositTx.wait();
  console.log("Deposit completed!");

  // Check L2 balance
  const l2Balance = await wallet.getBalance();
  console.log(`L2 Balance: ${ethers.formatEther(l2Balance)}`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
