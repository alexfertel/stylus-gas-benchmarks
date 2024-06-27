// Only run this as a WASM if the export-abi feature is not set.
#![cfg_attr(not(any(feature = "export-abi", test)), no_main)]
extern crate alloc;

use alloc::vec::Vec;

use alloy_primitives::B256;
use crypto::{merkle::Verifier, KeccakBuilder};
use stylus_sdk::{
    prelude::{entrypoint, external},
    stylus_proc::solidity_storage,
};

#[global_allocator]
static ALLOC: mini_alloc::MiniAlloc = mini_alloc::MiniAlloc::INIT;

#[solidity_storage]
#[entrypoint]
pub struct VerifierContract;

#[external]
impl VerifierContract {
    pub fn verify(&self, proof: Vec<B256>, root: B256, leaf: B256) -> bool {
        let proof: Vec<[u8; 32]> = proof.into_iter().map(|m| *m).collect();
        Verifier::<KeccakBuilder>::verify(&proof, *root, *leaf)
    }

    pub fn verify_multi_proof(
        &self,
        proof: Vec<B256>,
        proof_flags: Vec<bool>,
        root: B256,
        leaves: Vec<B256>,
    ) -> bool {
        let proof: Vec<[u8; 32]> = proof.into_iter().map(|m| *m).collect();
        let leaves: Vec<[u8; 32]> = leaves.into_iter().map(|m| *m).collect();

        Verifier::<KeccakBuilder>::verify_multi_proof(&proof, &proof_flags, *root, &leaves).unwrap()
    }
}
