use alloy::{
    network::EthereumWallet, primitives::Address, providers::ProviderBuilder,
    signers::local::PrivateKeySigner, sol, transports::http::reqwest::Url, uint,
};
use tokio::process::Command;

sol!(
    #[sol(rpc)]
    contract Erc20 {
        function name() external view returns (string name);
        function symbol() external view returns (string symbol);
        function decimals() external view returns (uint8 decimals);
        function totalSupply() external view returns (uint256 totalSupply);
        function balanceOf(address account) external view returns (uint256 balance);
        function transfer(address recipient, uint256 amount) external returns (bool);
        function allowance(address owner, address spender) external view returns (uint256 allowance);
        function approve(address spender, uint256 amount) external returns (bool);
        function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
        function mint(address account, uint256 amount) external;
        function burn(address account, uint256 amount) external;
    }
);

pub async fn bench() -> eyre::Result<()> {
    let rpc_url = std::env::var("RPC_URL")?.parse::<Url>()?;
    let pk = std::env::var("PRIVATE_KEY")?;
    let alice = pk.parse::<PrivateKeySigner>()?;
    let alice_addr = alice.address();
    let alice = ProviderBuilder::new()
        .with_recommended_fillers()
        .wallet(EthereumWallet::from(alice))
        .on_http(rpc_url.clone());

    let bob = PrivateKeySigner::random();
    let bob_addr = bob.address();

    let contract_addr = deploy("erc20").await?;
    let contract = Erc20::new(contract_addr, &alice);
    let gas = contract.name().estimate_gas().await?;
    println!("name(): estimated {gas}");
    let gas = contract.symbol().estimate_gas().await?;
    println!("symbol(): estimated {gas}");
    let gas = contract.decimals().estimate_gas().await?;
    println!("decimals(): estimated {gas}");
    let gas = contract.totalSupply().estimate_gas().await?;
    println!("totalSupply(): estimated {gas}");
    let gas = contract.balanceOf(alice_addr).estimate_gas().await?;
    println!("balanceOf(account): estimated {gas}");

    let gas = contract
        .mint(alice_addr, uint!(100_U256))
        .from(alice_addr)
        .estimate_gas()
        .await?;
    println!("mint(account, amount): estimate {gas}");

    let receipt = contract
        .mint(alice_addr, uint!(100_U256))
        .send()
        .await?
        .get_receipt()
        .await?;
    println!("mint(account, amount): used {}", receipt.gas_used);
    let gas = contract
        .burn(alice_addr, uint!(1_U256))
        .from(alice_addr)
        .estimate_gas()
        .await?;
    println!("burn(amount): estimated {gas}");
    let gas = contract
        .transfer(bob_addr, uint!(1_U256))
        .from(alice_addr)
        .estimate_gas()
        .await?;
    println!("transfer(account, amount): estimated {gas}");
    let receipt = contract
        .transfer(bob_addr, uint!(1_U256))
        .from(alice_addr)
        .send()
        .await?
        .get_receipt()
        .await?;
    println!("transfer(account, amount): used {}", receipt.gas_used);

    Ok(())
}

async fn deploy(contract_name: &str) -> eyre::Result<Address> {
    let rpc_url = std::env::var("RPC_URL")?;
    let pk = std::env::var("PRIVATE_KEY")?;
    let manifest_dir = std::env::current_dir()?.canonicalize()?;
    let contract_dir = manifest_dir
        .join("contracts")
        .join(contract_name.to_lowercase());
    let output = Command::new("cargo-stylus")
        .current_dir(contract_dir)
        .arg("deploy")
        .args(["-e", &rpc_url])
        .args(["--private-key", &pk])
        .output()
        .await?;
    let output = String::from_utf8_lossy(&output.stdout);
    println!("{output}");
    let address_line = output
        .lines()
        .find(|l| l.contains("deployed"))
        .expect("should output deployed contract's address");
    let start = address_line
        .find("0x")
        .expect("deployed line should contain the contract's address");
    Ok(address_line[start + 2..start + 42].parse::<Address>()?)
}
