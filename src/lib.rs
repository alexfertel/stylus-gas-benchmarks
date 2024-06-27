pub mod erc20;

pub async fn run() -> eyre::Result<()> {
    dotenv::dotenv()?;

    erc20::bench().await?;

    Ok(())
}
