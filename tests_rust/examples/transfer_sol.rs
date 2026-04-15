//! SVM-level integration test for the Zignocchio Transfer SOL program.
//!
//! Prerequisites: `zig build -Dexample=transfer-sol` must be run before these tests.
//! The test loads `zig-out/lib/transfer-sol.so` at runtime.

use mollusk_svm::{program::keyed_account_for_system_program, result::Check, Mollusk};
use solana_account::Account;
use solana_instruction::{AccountMeta, Instruction};
use solana_pubkey::Pubkey;

const PROGRAM_ID_BYTES: [u8; 32] = [4u8; 32];
const SYSTEM_PROGRAM_ID: Pubkey = solana_pubkey::pubkey!("11111111111111111111111111111111");

fn program_id() -> Pubkey {
    Pubkey::new_from_array(PROGRAM_ID_BYTES)
}

fn setup_mollusk() -> Mollusk {
    let elf_path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .unwrap()
        .join("zig-out")
        .join("lib")
        .join("transfer-sol.so");
    let elf = std::fs::read(&elf_path).unwrap_or_else(|error| {
        panic!(
            "failed to read sBPF artifact at {}: {}. Run `zig build -Dexample=transfer-sol` first.",
            elf_path.display(),
            error
        )
    });
    let pid = program_id();
    let loader_v3 = solana_pubkey::pubkey!("BPFLoaderUpgradeab1e11111111111111111111111");
    let mut mollusk = Mollusk::default();
    mollusk.add_program_with_loader_and_elf(&pid, &loader_v3, &elf);
    mollusk.program_cache.add_builtin(mollusk_svm::program::Builtin {
        program_id: SYSTEM_PROGRAM_ID,
        name: "system_program",
        entrypoint: solana_system_program::system_processor::Entrypoint::vm,
    });
    mollusk
}

#[test]
fn test_transfer_sol_happy() {
    let mollusk = setup_mollusk();
    let from = Pubkey::new_unique();
    let to = Pubkey::new_unique();
    let amount: u64 = 100_000_000;

    let ix = Instruction {
        program_id: program_id(),
        accounts: vec![
            AccountMeta::new(from, true),
            AccountMeta::new(to, false),
            AccountMeta::new_readonly(SYSTEM_PROGRAM_ID, false),
        ],
        data: amount.to_le_bytes().to_vec(),
    };

    let from_acc = Account {
        lamports: 1_000_000_000,
        ..Account::default()
    };
    let to_acc = Account::default();

    let result = mollusk.process_instruction(
        &ix,
        &[
            (from, from_acc),
            (to, to_acc),
            keyed_account_for_system_program(),
        ],
    );

    assert!(
        !result.program_result.is_err(),
        "transfer should succeed: {:?}",
        result.program_result
    );

    let from_post = &result.resulting_accounts[0].1;
    let to_post = &result.resulting_accounts[1].1;
    assert_eq!(from_post.lamports, 900_000_000);
    assert_eq!(to_post.lamports, amount);
}

#[test]
fn test_transfer_sol_zero_amount_fails() {
    let mollusk = setup_mollusk();
    let from = Pubkey::new_unique();
    let to = Pubkey::new_unique();

    let ix = Instruction {
        program_id: program_id(),
        accounts: vec![
            AccountMeta::new(from, true),
            AccountMeta::new(to, false),
            AccountMeta::new_readonly(SYSTEM_PROGRAM_ID, false),
        ],
        data: 0u64.to_le_bytes().to_vec(),
    };

    let from_acc = Account {
        lamports: 1_000_000_000,
        ..Account::default()
    };
    let to_acc = Account::default();

    mollusk.process_and_validate_instruction(
        &ix,
        &[
            (from, from_acc),
            (to, to_acc),
            keyed_account_for_system_program(),
        ],
        &[Check::err(solana_program_error::ProgramError::Custom(4))],
    );
}
