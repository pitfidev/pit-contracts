# Yearn V3 Vaults

This repository contains the Smart Contracts for Yearns V3 vault implementation.

[VaultFactory.vy](contracts/VaultFactory.vy) - The base factory that all vaults will be deployed from and used to configure protocol fees

[Vault.vy](contracts/VaultV3.vy) - The ERC4626 compliant Vault that will handle all logic associated with deposits, withdraws, strategy management, profit reporting etc.

For the V3 strategy implementation see the [Tokenized Strategy](https://github.com/yearn/tokenized-strategy) repo.

## Requirements

This repository runs on [ApeWorx](https://www.apeworx.io/). A python based development tool kit.

You will need:
 - Python 3.8 or later
 - [Vyper 0.3.7](https://docs.vyperlang.org/en/stable/installing-vyper.html)
 - [Foundry](https://book.getfoundry.sh/getting-started/installation)
 - Linux or macOS
 - Windows: Install Windows Subsystem Linux (WSL) with Python 3.8 or later
 - [Hardhat](https://hardhat.org/) installed globally

## Installation

Fork the repository and clone onto your local device 

```
git clone --recursive https://github.com/user/yearn-vaults-v3
cd yearn-vaults-v3
```

Set up your python virtual environment and activate it.

```
python3 -m venv venv
source venv/bin/activate
```

Install requirements.

```
python3 -m pip install -r requirements.txt
yarn
```

Fetch the ape plugins:

```
ape plugins install .
```

Compile smart contracts with:

```
ape compile
```

and test smart contracts with:

**WARNING: Sei EVM**

_If using SEI EVM, you will need to comment out some portions of code in the  ape-ethereum provider and ape-foundry provider. Specifically regarding the initial block reported by the nodes._

```
ape test --network sei:mainnet-fork:foundry
```

## Deployment

Deployments of the Vault Factory are done using create2 to be at a deterministic address on any EVM chain.

Check the [docs](https://docs.yearn.fi/developers/v3/overview) for the most updated deployment address.

Deployments on new chains can be done permissionlessly by anyone using the included script.

```
ape run scripts/deploy.py --network YOUR_RPC_URL
```

If the deployments do not end at the same address you can also manually send the calldata used in the previous deployments on other chains.

### To make a contribution please follow the [guidelines](https://github.com/yearn/yearn-vaults-v3/bloc/master/CONTRIBUTING.md)

See the ApeWorx [documentation](https://docs.apeworx.io/ape/stable/) and [github](https://github.com/ApeWorX/ape) for more information.

You will need hardhat to run the test `yarn`


## HARDHAT

Hardhat is a development environment to compile, deploy, test, and debug your Ethereum software. It helps developers manage and automate the recurring tasks that are inherent to the process of building smart contracts and dApps, as well as easily introducing more functionality around this workflow.

### Installation

```bash
npm install
```

### Compile

```bash
npm run hardhat:compile
```

The command will also generate typescript interface for the contracts.

### Deploy

```bash
npx hardhat run scripts/hardhat/vault.init.ts --network sei_atlantic_2
```

```bash
npx hardhat run scripts/hardhat/vault.deploy.ts --network sei_atlantic_2
```

### Test

```bash
npx hardhat test --config pacific-1-forked.config.ts
```