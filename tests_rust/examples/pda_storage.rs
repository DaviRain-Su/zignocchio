//! SVM-level integration test for the Zignocchio PDA Storage program.
//!
//! Prerequisites: `zig build -Dexample=pda-storage` must be run before these tests.
//! The test loads `zig-out/lib/pda-storage.so` at runtime.

use mollusk_svm::{program::keyed_account_for_system_program, result::Check, Mollusk};
use solana_account::Account;
use solana_instruction::{AccountMeta, Instruction};
use solana_pubkey::Pubkey;

const PROGRAM_ID_BYTES: [u8; 32] = [5u8; 32];
const SYSTEM_PROGRAM_ID: Pubkey = solana_pubkey::pubkey!("11111111111111111111111111111111");
const STORAGE_SEED: &[u8] = b"storage";

fn program_id() -> Pubkey {
    Pubkey::new_from_array(PROGRAM_ID_BYTES)
}

fn setup_mollusk() -> Mollusk {
    let elf_path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .unwrap()
        .join("zig-out")
        .join("lib")
        .join("pda-storage.so");
    let elf = std::fs::read(&elf_path).unwrap_or_else(|error| {
        panic!(
            "failed to read sBPF artifact at {}: {}. Run `zig build -Dexample=pda-storage` first.",
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

fn find_storage_pda(user: &Pubkey) -> (Pubkey, u8) {
    Pubkey::find_program_address(&[STORAGE_SEED, user.as_ref()],
        &program_id()
    )
}

#[test]
fn test_pda_storage_init_and_update() {
    let mollusk = setup_mollusk();
    let payer = Pubkey::new_unique();
    let user = Pubkey::new_unique();
    let (storage_pda, _bump) = find_storage_pda(&user);
    let initial_value: u64 = 42;

    // --- Init ---
    let init_ix = Instruction {
        program_id: program_id(),
        accounts: vec![
            AccountMeta::new(payer, true),
            AccountMeta::new(storage_pda, false),
            AccountMeta::new(user, true),
            AccountMeta::new_readonly(SYSTEM_PROGRAM_ID, false),
        ],
        data: {
            let mut data = vec![0u8]; // discriminator = init
            data.extend_from_slice(&initial_value.to_le_bytes());
            data
        },
    };

    let payer_acc = Account {
        lamports: 2_000_000_000,
        ..Account::default()
    };
    let storage_acc = Account {
        lamports: 0,
        data: vec![],
        owner: SYSTEM_PROGRAM_ID,
        executable: false,
        rent_epoch: 0,
    };
    let user_acc = Account {
        lamports: 1_000_000,
        ..Account::default()
    };

    let result = mollusk.process_instruction(
        &init_ix,
        &[
            (payer, payer_acc),
            (storage_pda, storage_acc),
            (user, user_acc),
            keyed_account_for_system_program(),
        ],
    );

    assert!(
        !result.program_result.is_err(),
        "init should succeed: {:?}",
        result.program_result
    );

    let storage_post = &result.resulting_accounts[1].1;
    assert_eq!(&storage_post.data[0..32], user.as_ref());
    let stored_value = u64::from_le_bytes(storage_post.data[32..40].try_into().unwrap());
    assert_eq!(stored_value, initial_value);

    // --- Update ---
    let new_value: u64 = 100;
    let update_ix = Instruction {
        program_id: program_id(),
        accounts: vec![
            AccountMeta::new(storage_pda, false),
            AccountMeta::new(user, true),
        ],
        data: {
            let mut data = vec![1u8]; // discriminator = update
            data.extend_from_slice(&new_value.to_le_bytes());
            data
        },
    };

    let result2 = mollusk.process_instruction(
        &update_ix,
        &[
            (storage_pda, storage_post.clone()),
            (user, result.resulting_accounts[2].1.clone()),
        ],
    );

    assert!(
        !result2.program_result.is_err(),
        "update should succeed: {:?}",
        result2.program_result
    );

    let storage_post2 = &result2.resulting_accounts[0].1;
    let stored_value2 = u64::from_le_bytes(storage_post2.data[32..40].try_into().unwrap());
    assert_eq!(stored_value2, new_value);
}

#[test]
fn test_pda_storage_update_with_wrong_signer_fails() {
    let mollusk = setup_mollusk();
    let payer = Pubkey::new_unique();
    let user = Pubkey::new_unique();
    let attacker = Pubkey::new_unique();
    let (storage_pda, _bump) = find_storage_pda(&user);
    let initial_value: u64 = 42;

    // Init first
    let init_ix = Instruction {
        program_id: program_id(),
        accounts: vec![
            AccountMeta::new(payer, true),
            AccountMeta::new(storage_pda, false),
            AccountMeta::new(user, true),
            AccountMeta::new_readonly(SYSTEM_PROGRAM_ID, false),
        ],
        data: {
            let mut data = vec![0u8];
            data.extend_from_slice(&initial_value.to_le_bytes());
            data
        },
    };

    let payer_acc = Account {
        lamports: 2_000_000_000,
        ..Account::default()
    };
    let storage_acc = Account {
        lamports: 0,
        data: vec![],
        owner: SYSTEM_PROGRAM_ID,
        executable: false,
        rent_epoch: 0,
    };
    let user_acc = Account {
        lamports: 1_000_000,
        ..Account::default()
    };

    let result = mollusk.process_instruction(
        &init_ix,
        &[
            (payer, payer_acc),
            (storage_pda, storage_acc),
            (user, user_acc.clone()),
            keyed_account_for_system_program(),
        ],
    );
    assert!(!result.program_result.is_err());

    // Attempt update with attacker as signer
    let update_ix = Instruction {
        program_id: program_id(),
        accounts: vec![
            AccountMeta::new(storage_pda, false),
            AccountMeta::new(attacker, true),
        ],
        data: {
            let mut data = vec![1u8];
            data.extend_from_slice(&100u64.to_le_bytes());
            data
        },
    };

    mollusk.process_and_validate_instruction(
        &update_ix,
        &[
            (storage_pda, result.resulting_accounts[1].1.clone()),
            (attacker, Account::default()),
        ],
        &[Check::err(solana_program_error::ProgramError::Custom(3))],
    );
}
