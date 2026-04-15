//! SVM-level integration test for the Zignocchio Escrow program.
//!
//! Prerequisites: `zig build -Dexample=escrow` must be run before these tests.
//! The test loads `zig-out/lib/escrow.so` at runtime.

use mollusk_svm::{program::keyed_account_for_system_program, result::Check, Mollusk};
use solana_account::Account;
use solana_instruction::{AccountMeta, Instruction};
use solana_pubkey::Pubkey;

const PROGRAM_ID_BYTES: [u8; 32] = [6u8; 32];
const SYSTEM_PROGRAM_ID: Pubkey = solana_pubkey::pubkey!("11111111111111111111111111111111");
const ESCROW_SEED: &[u8] = b"escrow";
const ESCROW_DISCRIMINATOR: u8 = 0xE5;

fn program_id() -> Pubkey {
    Pubkey::new_from_array(PROGRAM_ID_BYTES)
}

fn setup_mollusk() -> Mollusk {
    let elf_path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .unwrap()
        .join("zig-out")
        .join("lib")
        .join("escrow.so");
    let elf = std::fs::read(&elf_path).unwrap_or_else(|error| {
        panic!(
            "failed to read sBPF artifact at {}: {}. Run `zig build -Dexample=escrow` first.",
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

fn find_escrow_pda(maker: &Pubkey) -> (Pubkey, u8) {
    Pubkey::find_program_address(&[ESCROW_SEED, maker.as_ref()], &program_id())
}

fn make_instruction_data(taker: &Pubkey, amount: u64) -> Vec<u8> {
    let mut data = vec![0u8]; // discriminator = make
    data.extend_from_slice(taker.as_ref());
    data.extend_from_slice(&amount.to_le_bytes());
    data
}

#[test]
fn test_escrow_make_and_accept() {
    let mollusk = setup_mollusk();
    let maker = Pubkey::new_unique();
    let taker = Pubkey::new_unique();
    let (escrow_pda, _bump) = find_escrow_pda(&maker);
    let amount: u64 = 100_000_000;

    // --- Make ---
    let make_ix = Instruction {
        program_id: program_id(),
        accounts: vec![
            AccountMeta::new(maker, true),
            AccountMeta::new(escrow_pda, false),
            AccountMeta::new_readonly(SYSTEM_PROGRAM_ID, false),
        ],
        data: make_instruction_data(&taker, amount),
    };

    let maker_acc = Account {
        lamports: 1_000_000_000,
        ..Account::default()
    };
    let escrow_acc = Account {
        lamports: 0,
        data: vec![],
        owner: SYSTEM_PROGRAM_ID,
        executable: false,
        rent_epoch: 0,
    };

    let result = mollusk.process_instruction(
        &make_ix,
        &[
            (maker, maker_acc),
            (escrow_pda, escrow_acc),
            keyed_account_for_system_program(),
        ],
    );

    assert!(
        !result.program_result.is_err(),
        "make should succeed: {:?}",
        result.program_result
    );

    let escrow_post = &result.resulting_accounts[1].1;
    assert_eq!(escrow_post.owner, program_id());
    assert_eq!(escrow_post.data[0], ESCROW_DISCRIMINATOR);
    assert_eq!(&escrow_post.data[1..33], maker.as_ref());
    assert_eq!(&escrow_post.data[33..65], taker.as_ref());
    // EscrowState is an extern struct; u64 `amount` has 8-byte alignment,
    // so it sits at offset 72 after 7 bytes of padding.
    let stored_amount = u64::from_le_bytes(escrow_post.data[72..80].try_into().unwrap());
    assert_eq!(stored_amount, amount);

    // --- Accept ---
    let accept_ix = Instruction {
        program_id: program_id(),
        accounts: vec![
            AccountMeta::new(taker, true),
            AccountMeta::new(escrow_pda, false),
            AccountMeta::new(maker, false),
        ],
        data: vec![1u8], // discriminator = accept
    };

    let taker_acc = Account {
        lamports: 1_000_000,
        ..Account::default()
    };

    let result2 = mollusk.process_instruction(
        &accept_ix,
        &[
            (taker, taker_acc),
            (escrow_pda, escrow_post.clone()),
            (maker, result.resulting_accounts[0].1.clone()),
        ],
    );

    assert!(
        !result2.program_result.is_err(),
        "accept should succeed: {:?}",
        result2.program_result
    );

    let escrow_post2 = &result2.resulting_accounts[1].1;
    assert_eq!(escrow_post2.lamports, 0);

    let taker_post = &result2.resulting_accounts[0].1;
    assert!(taker_post.lamports > 1_000_000); // received escrow lamports
}

#[test]
fn test_escrow_make_and_refund() {
    let mollusk = setup_mollusk();
    let maker = Pubkey::new_unique();
    let taker = Pubkey::new_unique();
    let (escrow_pda, _bump) = find_escrow_pda(&maker);
    let amount: u64 = 100_000_000;

    // --- Make ---
    let make_ix = Instruction {
        program_id: program_id(),
        accounts: vec![
            AccountMeta::new(maker, true),
            AccountMeta::new(escrow_pda, false),
            AccountMeta::new_readonly(SYSTEM_PROGRAM_ID, false),
        ],
        data: make_instruction_data(&taker, amount),
    };

    let maker_acc = Account {
        lamports: 1_000_000_000,
        ..Account::default()
    };
    let escrow_acc = Account {
        lamports: 0,
        data: vec![],
        owner: SYSTEM_PROGRAM_ID,
        executable: false,
        rent_epoch: 0,
    };

    let result = mollusk.process_instruction(
        &make_ix,
        &[
            (maker, maker_acc.clone()),
            (escrow_pda, escrow_acc),
            keyed_account_for_system_program(),
        ],
    );
    assert!(!result.program_result.is_err());

    let escrow_post = &result.resulting_accounts[1].1;
    let maker_post = &result.resulting_accounts[0].1;

    // --- Refund ---
    let refund_ix = Instruction {
        program_id: program_id(),
        accounts: vec![
            AccountMeta::new(maker, true),
            AccountMeta::new(escrow_pda, false),
        ],
        data: vec![2u8], // discriminator = refund
    };

    let result2 = mollusk.process_instruction(
        &refund_ix,
        &[
            (maker, maker_post.clone()),
            (escrow_pda, escrow_post.clone()),
        ],
    );

    assert!(
        !result2.program_result.is_err(),
        "refund should succeed: {:?}",
        result2.program_result
    );

    let escrow_post2 = &result2.resulting_accounts[1].1;
    assert_eq!(escrow_post2.lamports, 0);

    let maker_post2 = &result2.resulting_accounts[0].1;
    assert_eq!(maker_post2.lamports, maker_acc.lamports);
}

#[test]
fn test_escrow_accept_by_unauthorized_taker_fails() {
    let mollusk = setup_mollusk();
    let maker = Pubkey::new_unique();
    let taker = Pubkey::new_unique();
    let attacker = Pubkey::new_unique();
    let (escrow_pda, _bump) = find_escrow_pda(&maker);
    let amount: u64 = 100_000_000;

    // --- Make ---
    let make_ix = Instruction {
        program_id: program_id(),
        accounts: vec![
            AccountMeta::new(maker, true),
            AccountMeta::new(escrow_pda, false),
            AccountMeta::new_readonly(SYSTEM_PROGRAM_ID, false),
        ],
        data: make_instruction_data(&taker, amount),
    };

    let maker_acc = Account {
        lamports: 1_000_000_000,
        ..Account::default()
    };
    let escrow_acc = Account {
        lamports: 0,
        data: vec![],
        owner: SYSTEM_PROGRAM_ID,
        executable: false,
        rent_epoch: 0,
    };

    let result = mollusk.process_instruction(
        &make_ix,
        &[
            (maker, maker_acc),
            (escrow_pda, escrow_acc),
            keyed_account_for_system_program(),
        ],
    );
    assert!(!result.program_result.is_err());

    let escrow_post = &result.resulting_accounts[1].1;

    // --- Accept by attacker ---
    let accept_ix = Instruction {
        program_id: program_id(),
        accounts: vec![
            AccountMeta::new(attacker, true),
            AccountMeta::new(escrow_pda, false),
            AccountMeta::new(maker, false),
        ],
        data: vec![1u8],
    };

    mollusk.process_and_validate_instruction(
        &accept_ix,
        &[
            (attacker, Account::default()),
            (escrow_pda, escrow_post.clone()),
            (maker, result.resulting_accounts[0].1.clone()),
        ],
        &[Check::err(solana_program_error::ProgramError::Custom(18))], // IncorrectAuthority
    );
}
