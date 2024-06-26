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

# Initialize an associative array to store contract addresses
declare -A contract_addresses

for dir in ./contracts/*/; do
    if [ -d "$dir" ]; then
        # Get the contract name from the directory name
        contract_name=$(basename "$dir")
        echo "Deploying contract in $dir"
        cd "$dir"
        output=$(cargo stylus deploy -e $RPC_URL --private-key $PRIVATE_KEY)
        address=$(echo "$output" | grep -oP 'Deploying program to address \K[0-9a-fA-F]+')
        if [ -n "$address" ]; then
            echo "Deployed contract address for $contract_name: $address"
            # Store the address in the associative array
            contract_addresses["$contract_name"]=$address
        else
            echo "Failed to deploy contract in $dir"
        fi
        cd -
    fi
done

# Print all stored addresses
echo "Deployed contract addresses:"
for contract in "${!contract_addresses[@]}"; do
    echo "$contract: ${contract_addresses[$contract]}"
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
    
    # Define function signatures and their arguments for this contract
    declare -A function_args
    case $contract in
        "erc20")
            function_args=(
                ["name()"]=""
                ["symbol()"]=""
                ["decimals()"]=""
                ["totalSupply()"]=""
                ["balanceOf(address)"]="0x1234567890123456789012345678901234567890"
                ["transfer(address,uint256)"]="0x1234567890123456789012345678901234567890 100"
                ["transferFrom(address,address,uint256)"]="0x1234567890123456789012345678901234567890 0x0987654321098765432109876543210987654321 100"
                ["approve(address,uint256)"]="0x1234567890123456789012345678901234567890 100"
                ["allowance(address,address)"]="0x1234567890123456789012345678901234567890 0x0987654321098765432109876543210987654321"
            )
            ;;
        "erc721")
            function_args=(
                ["name()"]=""
                ["symbol()"]=""
                ["tokenURI(uint256)"]="1"
                ["ownerOf(uint256)"]="1"
                ["balanceOf(address)"]="0x1234567890123456789012345678901234567890"
                ["transferFrom(address,address,uint256)"]="0x1234567890123456789012345678901234567890 0x0987654321098765432109876543210987654321 1"
                ["safeTransferFrom(address,address,uint256)"]="0x1234567890123456789012345678901234567890 0x0987654321098765432109876543210987654321 1"
                ["approve(address,uint256)"]="0x1234567890123456789012345678901234567890 1"
                ["getApproved(uint256)"]="1"
                ["setApprovalForAll(address,bool)"]="0x1234567890123456789012345678901234567890 true"
                ["isApprovedForAll(address,address)"]="0x1234567890123456789012345678901234567890 0x0987654321098765432109876543210987654321"
            )
            ;;
        *)
            echo "Unknown contract type: $contract"
            return
            ;;
    esac
    
    for function in "${!function_args[@]}"; do
        args=${function_args[$function]}
        
        # Estimate gas using cast
        gas_estimate=$(cast estimate --rpc-url $RPC_URL $address "$function" $args 2>/dev/null)
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
for contract in "${!contract_addresses[@]}"; do
    address=${contract_addresses[$contract]}
    estimate_gas_for_contract "$contract" "$address"
done
