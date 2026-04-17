//! SVM-level integration test for the Zignocchio Counter program.
//!
//! Prerequisites: `zig build -Dexample=counter` must be run before these tests.
//! The test loads `zig-out/lib/counter.so` at runtime.

use mollusk_svm::Mollusk;
use solana_account::Account;
use solana_instruction::{AccountMeta, Instruction};
use solana_pubkey::Pubkey;

const PROGRAM_ID_BYTES: [u8; 32] = [2u8; 32];

fn program_id() -> Pubkey {
    Pubkey::new_from_array(PROGRAM_ID_BYTES)
}

fn setup_mollusk() -> Mollusk {
    let elf_path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .unwrap()
        .join("zig-out")
        .join("lib")
        .join("counter.so");
    let elf = std::fs::read(&elf_path).unwrap_or_else(|error| {
        panic!(
            "failed to read sBPF artifact at {}: {}. Run `zig build -Dexample=counter` first.",
            elf_path.display(),
            error
        )
    });
    let pid = program_id();
    let loader_v3 = solana_pubkey::pubkey!("BPFLoaderUpgradeab1e11111111111111111111111");
    let mut mollusk = Mollusk::default();
    mollusk.add_program_with_loader_and_elf(&pid, &loader_v3, &elf);
    mollusk
}

#[test]
fn test_counter_increment() {
    let mollusk = setup_mollusk();
    let counter = Pubkey::new_unique();

    let ix = Instruction {
        program_id: program_id(),
        accounts: vec![
            AccountMeta::new(counter, false), // counter account, writable
        ],
        data: vec![0], // instruction 0 = increment
    };

    let counter_acc = Account {
        lamports: 1_000_000,
        data: vec![0u8; 8],
        owner: program_id(),
        executable: false,
        rent_epoch: 0,
    };

    let result = mollusk.process_instruction(&ix, &[(counter, counter_acc)]);
    assert!(
        !result.program_result.is_err(),
        "counter increment should succeed: {:?}",
        result.program_result
    );

    let counter_post = &result.resulting_accounts[0].1;
    let value = u64::from_le_bytes(
        counter_post.data[0..8].try_into().unwrap(),
    );
    assert_eq!(value, 1, "counter should be incremented to 1");
}
