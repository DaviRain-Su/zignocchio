//! SVM-level integration test for the Zignocchio Vault program.
//!
//! Prerequisites: `zig build -Dexample=vault` must be run before these tests.
//! The test loads `zig-out/lib/vault.so` at runtime.

use mollusk_svm::{program::keyed_account_for_system_program, result::Check, Mollusk};
use solana_account::Account;
use solana_instruction::{AccountMeta, Instruction};
use solana_pubkey::Pubkey;

const PROGRAM_ID_BYTES: [u8; 32] = [3u8; 32];
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
        .join("vault.so");
    let elf = std::fs::read(&elf_path).unwrap_or_else(|error| {
        panic!(
            "failed to read sBPF artifact at {}: {}. Run `zig build -Dexample=vault` first.",
            elf_path.display(),
            error
        )
    });
    let pid = program_id();
    let loader_v3 = solana_pubkey::pubkey!("BPFLoaderUpgradeab1e11111111111111111111111");
    let mut mollusk = Mollusk::default();
    mollusk.add_program_with_loader_and_elf(&pid, &loader_v3, &elf);
    // Add System Program builtin so CPI transfers work
    mollusk.program_cache.add_builtin(mollusk_svm::program::Builtin {
        program_id: SYSTEM_PROGRAM_ID,
        name: "system_program",
        entrypoint: solana_system_program::system_processor::Entrypoint::vm,
    });
    mollusk
}

fn find_vault_pda(owner: &Pubkey) -> (Pubkey, u8) {
    Pubkey::find_program_address(&[b"vault", owner.as_ref()], &program_id())
}

#[test]
fn test_vault_deposit_happy() {
    let mollusk = setup_mollusk();
    let user = Pubkey::new_unique();
    let (vault_pda, _bump) = find_vault_pda(&user);
    let deposit_amount: u64 = 100_000_000;

    let ix = Instruction {
        program_id: program_id(),
        accounts: vec![
            AccountMeta::new(user, true),        // signer + writable
            AccountMeta::new(vault_pda, false),  // writable
            AccountMeta::new_readonly(SYSTEM_PROGRAM_ID, false),
        ],
        data: {
            let mut data = vec![0u8]; // discriminator = 0 (deposit)
            data.extend_from_slice(&deposit_amount.to_le_bytes());
            data
        },
    };

    let user_acc = Account {
        lamports: 1_000_000_000,
        ..Account::default()
    };
    let vault_acc = Account {
        lamports: 0,
        data: vec![],
        owner: SYSTEM_PROGRAM_ID,
        executable: false,
        rent_epoch: 0,
    };

    let result = mollusk.process_instruction(
        &ix,
        &[
            (user, user_acc),
            (vault_pda, vault_acc),
            keyed_account_for_system_program(),
        ],
    );

    assert!(
        !result.program_result.is_err(),
        "deposit should succeed: {:?}",
        result.program_result
    );

    let vault_post = &result.resulting_accounts[1].1;
    assert_eq!(vault_post.lamports, deposit_amount);
}

#[test]
fn test_vault_deposit_zero_amount_fails() {
    let mollusk = setup_mollusk();
    let user = Pubkey::new_unique();
    let (vault_pda, _bump) = find_vault_pda(&user);

    let ix = Instruction {
        program_id: program_id(),
        accounts: vec![
            AccountMeta::new(user, true),
            AccountMeta::new(vault_pda, false),
            AccountMeta::new_readonly(SYSTEM_PROGRAM_ID, false),
        ],
        data: {
            let mut data = vec![0u8];
            data.extend_from_slice(&0u64.to_le_bytes());
            data
        },
    };

    let user_acc = Account {
        lamports: 1_000_000_000,
        ..Account::default()
    };
    let vault_acc = Account {
        lamports: 0,
        data: vec![],
        owner: SYSTEM_PROGRAM_ID,
        executable: false,
        rent_epoch: 0,
    };

    mollusk.process_and_validate_instruction(
        &ix,
        &[
            (user, user_acc),
            (vault_pda, vault_acc),
            keyed_account_for_system_program(),
        ],
        &[Check::err(solana_program_error::ProgramError::Custom(4))],
    );
}
