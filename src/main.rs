#[tokio::main]
async fn main() -> eyre::Result<()> {
    if let Err(e) = benches::run().await {
        eprintln!("{e:?}");
        std::process::exit(1);
    }

    Ok(())
}
