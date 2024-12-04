# MemeBlindBox

## Dex Version

### Overview
This contract records ETH donations, creates memeToken according to the blind box opening time, and allocates the created memeToken to the contributors of the meme blind box based on their contribution ratio. The donated ETH is used to create a liquidity pool, and it cannot be unlocked. It also includes features like airdrop distribution and more.

### Install
```
    forge soldeer update
```

### Deploy
```
    forge script script/DeployMemeBlindBoxDex.s.sol --rpc-url $NETWORK --broadcast
```

### Verify contract
#### memeBlindBoxDex
``` 
    forge verify-contract --watch \
    --compiler-version "v0.8.24+commit.e11b9ed9" --optimizer-runs 200 --via-ir \
    --constructor-args $(cast abi-encode "constructor(address)" "NONFUNGIBLE_POSITION_MANAGER_BASE_SEPOLIA") \
    CA MemeBlindBoxDex \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    --chain-id 84532
```

#### Token20
```
    forge verify-contract --watch \
    --compiler-version "v0.8.24+commit.e11b9ed9" --optimizer-runs 200 --via-ir \
    --constructor-args $(cast abi-encode "constructor(string memory, string memory)" name symbol) \
    CA Token20 \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    --chain-id 84532
```
