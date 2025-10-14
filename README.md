# 🪙 Pecunity-Protocol

![Pecunity banner](./assets/pecunity_banner.png)

**Pecunity-Protocol** is a Hardhat 2.26 project for deploying and verifying the **Pecunity Token (PEC)** — an ERC-20 token with burn and permit functionality based on OpenZeppelin Contracts v5.4.

---

## ⚙️ Environment Setup

Before running any commands, make sure the following **Hardhat vars** (or environment variables) are set:

| Variable            | Description                                      |
| ------------------- | ------------------------------------------------ |
| `ALCHEMY_API_KEY`   | Your Alchemy API key for network access          |
| `PRIVATE_KEY`       | The deployer wallet private key                  |
| `ETHERSCAN_API_KEY` | Your Etherscan API key for contract verification |

### Example (using Hardhat vars)

```bash
npx hardhat vars set ALCHEMY_API_KEY
npx hardhat vars set PRIVATE_KEY
npx hardhat vars set ETHERSCAN_API_KEY
```

---

## 🧩 Available Commands

| Command                | Description                                    |
| ---------------------- | ---------------------------------------------- |
| `npm run compile`      | Compile all smart contracts                    |
| `npm run test`         | Run the test suite                             |
| `npm run deploy:token` | Compile and deploy the Pecunity Token contract |
| `npm run verify`       | Verify deployed contracts on Etherscan         |

---

### 🔧 Command Details

#### 🏗️ Deploy the Token

Deploy to a specific network (e.g., **bnbTestnet** or **bnbMainnet**):

```bash
NETWORK=bnbMainnet npm run deploy:token
```

#### 🧾 Verify the Contract

After deployment, verify on Etherscan (requires `CHAIN_ID`):

```bash
CHAIN_ID=57 npm run verify
```

#### 🧪 Run Tests

Execute the test suite locally:

```bash
npm run test
```

#### 🧱 Compile Contracts

Recompile all contracts:

```bash
npm run compile
```

---

## 📘 Notes

- Ensure your **`PRIVATE_KEY`** account has sufficient test BNB before deployment.
- The project uses **Hardhat Ignition** for verification and deployment management.
- Contract verification includes unrelated contracts with the `--include-unrelated-contracts` flag for completeness.

---

## 🤝 Credits

Built with ❤️ using  
**Hardhat 2.26 • OpenZeppelin 5.4 • Ethers.js 6 • Alchemy RPC • Etherscan API**

© 2025 **Pecunity Protocol**
