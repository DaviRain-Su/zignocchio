//! SVM-level integration test for the Zignocchio Hello program.
//!
//! Prerequisites: `zig build -Dexample=hello` must be run before these tests.
//! The test loads `zig-out/lib/hello.so` at runtime.

use mollusk_svm::Mollusk;
use solana_instruction::Instruction;
use solana_pubkey::Pubkey;

const PROGRAM_ID_BYTES: [u8; 32] = [1u8; 32];

fn program_id() -> Pubkey {
    Pubkey::new_from_array(PROGRAM_ID_BYTES)
}

fn setup_mollusk() -> Mollusk {
    let elf_path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .unwrap()
        .join("zig-out")
        .join("lib")
        .join("hello.so");
    let elf = std::fs::read(&elf_path).unwrap_or_else(|error| {
        panic!(
            "failed to read sBPF artifact at {}: {}. Run `zig build -Dexample=hello` first.",
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
fn test_hello_executes_successfully() {
    let mollusk = setup_mollusk();

    let ix = Instruction {
        program_id: program_id(),
        accounts: vec![],
        data: vec![],
    };

    let result = mollusk.process_instruction(&ix, &[]);
    assert!(
        !result.program_result.is_err(),
        "hello should succeed: {:?}",
        result.program_result
    );
}
