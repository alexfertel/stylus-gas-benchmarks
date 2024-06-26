#!/bin/bash

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check and install latest Rust version
if ! command_exists rustc; then
    echo "Rust is not installed. Installing..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source $HOME/.cargo/env
else
    echo "Rust is already installed."
fi

# Check and install wasm32-unknown-unknown target
if ! rustup target list | grep -q "wasm32-unknown-unknown (installed)"; then
    echo "Installing wasm32-unknown-unknown target..."
    rustup target add wasm32-unknown-unknown
else
    echo "wasm32-unknown-unknown target is already installed."
fi

# Check and install cargo-stylus
if ! command_exists cargo-stylus; then
    echo "Installing cargo-stylus..."
    cargo install --force cargo-stylus cargo-stylus-check
else
    echo "cargo-stylus is already installed."
fi

# Read environment variables
if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
else
    echo ".env file not found. Please create one with RPC_URL and PRIVATE_KEY."
    exit 1
fi

# Initialize arrays to store contract names and addresses
contract_names=()
contract_addresses=()

for dir in ./contracts/*/; do
    if [ -d "$dir" ]; then
        # Get the contract name from the directory name
        contract_name=$(basename "$dir")
        echo "Deploying contract in $dir"
        cd "$dir"
        output=$(cargo stylus deploy -e $RPC_URL --private-key $PRIVATE_KEY)
        address=$(echo "$output" | grep 'deployed' | grep -oE '0x[a-fA-F0-9]+')
        if [ -n "$address" ]; then
            echo "Deployed contract address for $contract_name: $address"
            # Store the name and address in the arrays
            contract_names+=("$contract_name")
            contract_addresses+=("$address")
        else
            echo "Failed to deploy contract in $dir"
        fi
        cd -
    fi
done

# Print all stored addresses
echo "Deployed contract addresses:"
for i in "${!contract_names[@]}"; do
    echo "${contract_names[$i]}: ${contract_addresses[$i]}"
done

# Check and install Foundry
if ! command_exists forge; then
    echo "Installing Foundry..."
    curl -L https://foundry.paradigm.xyz | bash
    source $HOME/.bashrc
    foundryup
else
    echo "Foundry is already installed."
fi

estimate_gas_for_contract() {
    local contract=$1
    local address=$2
    
    echo "Estimating gas consumption for contract: $contract"
    echo "Contract address: $address"
    
    local functions=()
    local args=()
    
    case $contract in
        "erc20")
            functions=(
                "name()"
                "symbol()"
                "decimals()"
                "totalSupply()"
                "balanceOf(address)"
                "transfer(address,uint256)"
                "transferFrom(address,address,uint256)"
                "approve(address,uint256)"
                "allowance(address,address)"
            )
            args=(
                ""
                ""
                ""
                ""
                "0x100d353062d922e769a34b9e95cd30495460e131"
                "0x100d353062d922e769a34b9e95cd30495460e131 100"
                "0x100d353062d922e769a34b9e95cd30495460e131 0x9f48b6948d6dab0d628e3e41f732fd8f22b1f395 100"
                "0x100d353062d922e769a34b9e95cd30495460e131 100"
                "0x100d353062d922e769a34b9e95cd30495460e131 0x9f48b6948d6dab0d628e3e41f732fd8f22b1f395"
            )
            ;;
        "erc721")
            functions=(
                "name()"
                "symbol()"
                "tokenURI(uint256)"
                "ownerOf(uint256)"
                "balanceOf(address)"
                "transferFrom(address,address,uint256)"
                "safeTransferFrom(address,address,uint256)"
                "approve(address,uint256)"
                "getApproved(uint256)"
                "setApprovalForAll(address,bool)"
                "isApprovedForAll(address,address)"
            )
            args=(
                ""
                ""
                "1"
                "1"
                "0x100d353062d922e769a34b9e95cd30495460e131"
                "0x100d353062d922e769a34b9e95cd30495460e131 0x9f48b6948d6dab0d628e3e41f732fd8f22b1f395 1"
                "0x100d353062d922e769a34b9e95cd30495460e131 0x9f48b6948d6dab0d628e3e41f732fd8f22b1f395 1"
                "0x100d353062d922e769a34b9e95cd30495460e131 1"
                "1"
                "0x100d353062d922e769a34b9e95cd30495460e131 true"
                "0x100d353062d922e769a34b9e95cd30495460e131 0x9f48b6948d6dab0d628e3e41f732fd8f22b1f395"
            )
            ;;
        *)
            echo "Unknown contract type: $contract"
            return
            ;;
    esac
    
    for i in "${!functions[@]}"; do
        local function="${functions[$i]}"
        local arg="${args[$i]}"
        
        # Estimate gas using cast
        gas_estimate=$(cast estimate --rpc-url $RPC_URL $address "$function" $arg 2>/dev/null)
        if [ $? -eq 0 ]; then
            echo "  $function: $gas_estimate gas"
        else
            echo "  $function: Failed to estimate gas"
        fi
    done
    echo ""
}

# Estimate gas consumption for each deployed contract
echo "Estimating gas consumption for deployed contracts:"
for i in "${!contract_names[@]}"; do
    contract="${contract_names[$i]}"
    address="${contract_addresses[$i]}"
    estimate_gas_for_contract "$contract" "$address"
done

echo "Gas estimation completed."
