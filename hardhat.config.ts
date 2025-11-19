import { HardhatUserConfig } from 'hardhat/config';
import '@nomicfoundation/hardhat-toolbox';
import dotenv from 'dotenv';
import fs from 'fs';
import path from 'path';

dotenv.config();

const getDeployerPrivateKey = (): string => {
  if (process.env.WALLET_PRIVATE_KEY && process.env.WALLET_PRIVATE_KEY.length > 0) {
    return process.env.WALLET_PRIVATE_KEY;
  }

  try {
    const walletsPath = path.resolve(__dirname, 'configs', 'wallets.yaml');
    const raw = fs.readFileSync(walletsPath, 'utf8');
    const match = raw.match(/private_key:\s*(0x[a-fA-F0-9]+)/);
    if (match?.[1]) {
      return match[1];
    }
  } catch (error) {
    console.warn('无法读取 configs/wallets.yaml，且未提供 WALLET_PRIVATE KEY 环境变量。', error);
  }

  throw new Error('WALLET_PRIVATE_KEY 未设置，请在环境变量或 configs/wallets.yaml 中提供 deployer.private_key。');
};

const config: HardhatUserConfig = {
  solidity: '0.8.28',
  networks: {
    localRethNode: {
      url: 'http://localhost:8545',
      accounts: [getDeployerPrivateKey()],
    },
  },
};

export default config;
