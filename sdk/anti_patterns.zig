//! # Common Anti-Patterns in Solana + Zig
//!
//! This module lists common mistakes that AI code agents make when writing
//! Solana programs in Zig, and how to fix them using Zignocchio.
//!
//! ## 1. Taking the address of a module-scope constant
//!
//! **Anti-pattern**
//! ```zig
//! pub const SYSTEM_PROGRAM_ID: sdk.Pubkey = .{0} ** 32;
//! if (!sdk.pubkeyEq(account.owner(), &SYSTEM_PROGRAM_ID)) {
//!     return error.IncorrectProgramId;
//! }
//! ```
//!
//! **Why it's wrong**
//! Zig 0.16's BPF backend may place module-scope constants at invalid low
//! addresses (e.g. `0x0`). Passing their address to syscalls or CPI causes an
//! `Access violation in unknown section` at runtime.
//!
//! **Fix**
//! ```zig
//! var system_program_id: sdk.Pubkey = .{0} ** 32;
//! if (!sdk.pubkeyEq(account.owner(), &system_program_id)) {
//!     return error.IncorrectProgramId;
//! }
//! ```
//!
//! **Zignocchio helper**
//! `sdk.system.getSystemProgramId(&out)` already follows this pattern.
//!
//! ## 2. Forgetting the signer check
//!
//! **Anti-pattern**
//! ```zig
//! fn withdraw(accounts: []sdk.AccountInfo) sdk.ProgramResult {
//!     const user = accounts[0];
//!     // No signer check!
//!     user.lamports -= amount;
//! }
//! ```
//!
//! **Why it's wrong**
//! Anyone can pass any account in the `accounts` array. Without `assert_signer`,
//! an attacker can execute privileged instructions on behalf of another user.
//!
//! **Fix**
//! ```zig
//! try sdk.guard.assert_signer(user);
//! ```
//!
//! ## 3. Forgetting the owner check
//!
//! **Anti-pattern**
//! ```zig
//! const data = try account.tryBorrowMutData();
//! // No owner check!
//! data.value[0] = 1;
//! ```
//!
//! **Why it's wrong**
//! An attacker can create an account with the same data layout but owned by a
//! different program. Your program would then mutate someone else's state.
//!
//! **Fix**
//! ```zig
//! try sdk.guard.assert_owner(account, program_id);
//! const data = try account.tryBorrowMutData();
//! defer data.release();
//! data.value[0] = 1;
//! ```
//!
//! ## 4. Using the wrong PDA seeds
//!
//! **Anti-pattern**
//! ```zig
//! const seeds = &[_][]const u8{ "vault" };
//! var vault_key: sdk.Pubkey = undefined;
//! var bump: u8 = undefined;
//! try sdk.findProgramAddress(seeds, program_id, &vault_key, &bump);
//! // Later, verify using different seeds
//! ```
//!
//! **Why it's wrong**
//! If the seeds used to derive the PDA don't match the seeds used to verify it,
//! funds can be sent to or controlled by the wrong address.
//!
//! **Fix**
//! ```zig
//! const seeds = &[_][]const u8{ "vault", &owner_key };
//! try sdk.guard.assert_pda(vault_account, seeds, program_id, bump);
//! ```
//!
//! ## 5. Skipping the discriminator check
//!
//! **Anti-pattern**
//! ```zig
//! const MyAccount = extern struct { value: u64 };
//! const data = try account.tryBorrowMutData();
//! var typed = @as(*MyAccount, @ptrCast(@alignCast(data.value.ptr)));
//! ```
//!
//! **Why it's wrong**
//! Without a discriminator, you might deserialize an `OwnerAccount` as a
//! `UserAccount`, leading to type confusion and arbitrary state mutations.
//!
//! **Fix**
//! ```zig
//! const MyAccount = extern struct {
//!     pub const DISCRIMINATOR: u8 = 0xAB;
//!     discriminator: u8,
//!     value: u64,
//! };
//! const Schema = sdk.schema.AccountSchema(MyAccount);
//! try Schema.validate(account);
//! var ref: sdk.RefMut([]u8) = undefined;
//! try Schema.from_bytes(account, &ref);
//! defer ref.release();
//! var typed = Schema.from_bytes_unchecked(ref.value);
//! ```
//!
//! ## 6. Double mutable borrow
//!
//! **Anti-pattern**
//! ```zig
//! var data1 = try account.tryBorrowMutData();
//! var data2 = try account.tryBorrowMutData(); // Panic!
//! ```
//!
//! **Why it's wrong**
//! Solana's borrow state machine only allows one mutable borrow at a time.
//! The second `tryBorrowMutData` will return `error.AccountBorrowFailed`.
//!
//! **Fix**
//! ```zig
//! var data = try account.tryBorrowMutData();
//! defer data.release();
//! data.value[0] = 1;
//! // All mutations done before release
//! ```
//!
//! ## 7. Calling CPI while holding an active borrow
//!
//! **Anti-pattern**
//! ```zig
//! var data = try account.tryBorrowMutData();
//! // borrow is still active
//! try sdk.invoke(&instruction, accounts); // CPI may fail!
//! data.release();
//! ```
//!
//! **Why it's wrong**
//! The CPI target may also try to borrow the same account, causing
//! `AccountBorrowFailed`.
//!
//! **Fix**
//! ```zig
//! var data = try account.tryBorrowMutData();
//! data.value[0] = 1;
//! data.release(); // release before CPI
//! try sdk.invoke(&instruction, accounts);
//! ```
//!
//! ## 8. Creating a non-rent-exempt account
//!
//! **Anti-pattern**
//! ```zig
//! // Creating an account with 0 lamports
//! ```
//!
//! **Why it's wrong**
//! On Solana, all new accounts must be rent exempt. A rent-paying account can
//! be drained by the rent collector and effectively deleted.
//!
//! **Fix**
//! ```zig
//! const rent_exempt_min = sdk.system.getRentExemptMinimum(data_len);
//! try sdk.guard.assert_rent_exempt(lamports, data_len);
//! ```
//!
//! **Note**: `sdk.guard.assert_rent_exempt` uses a conservative approximation.
//! For production programs, verify against the current rent epoch.
//!
//! ## 9. Overwriting an already initialized account
//!
//! **Anti-pattern**
//! ```zig
//! const data = account.borrowMutDataUnchecked();
//! data[0] = 1; // No check if account already has state!
//! ```
//!
//! **Why it's wrong**
//! Re-initializing an account that already holds state destroys existing data
//! and can lead to double-initialization bugs or fund loss.
//!
//! **Fix**
//! ```zig
//! try sdk.guard.assert_uninitialized(try account.borrowDataUnchecked());
//! // Safe to initialize now
//! ```
//!
//! ## 10. Using an uninitialized account
//!
//! **Anti-pattern**
//! ```zig
//! const data = try account.tryBorrowMutData();
//! // data is all zeros, but we treat it as a valid struct
//! var state = @as(*MyAccount, @ptrCast(@alignCast(data.value.ptr)));
//! ```
//!
//! **Why it's wrong**
//! An uninitialized account contains all zeros. Treating it as a valid typed
//! account leads to zero-value assumptions and potential exploits.
//!
//! **Fix**
//! ```zig
//! try sdk.guard.assert_initialized(data.value);
//! ```
//!
//! ## 11. Passing the same account twice
//!
//! **Anti-pattern**
//! ```zig
//! // source and destination are the same account index
//! try sdk.system.transfer(from, to, amount);
//! ```
//!
//! **Why it's wrong**
//! Many instructions require distinct accounts. Passing the same account can
//! create self-referential state mutations or bypass intended invariants.
//!
//! **Fix**
//! ```zig
//! try sdk.guard.assert_keys_not_equal(from, to);
//! try sdk.system.transfer(from, to, amount);
//! ```
//!
//! ## 12. Trusting an unverified program ID
//!
//! **Anti-pattern**
//! ```zig
//! // Calling CPI to an account that might not be the expected program
//! try sdk.invoke(&instruction, accounts);
//! ```
//!
//! **Why it's wrong**
//! An attacker can substitute any program account in the accounts array. Your
//! program may invoke malicious code.
//!
//! **Fix**
//! ```zig
//! try sdk.guard.assert_program_id(target_program.key(), &EXPECTED_PROGRAM_ID);
//! try sdk.guard.assert_executable(target_program);
//! try sdk.invoke(&instruction, accounts);
//! ```
//!
//! ## 13. Assuming an account is immutable when it is writable
//!
//! **Anti-pattern**
//! ```zig
//! const config = accounts[1];
//! // No immutability check — but config is passed as writable
//! ```
//!
//! **Why it's wrong**
//! If an account that should remain unchanged is passed as writable, a
//! compromised signer or buggy client can mutate it unexpectedly.
//!
//! **Fix**
//! ```zig
//! try sdk.guard.assert_immutable(config);
//! ```
//!
//! ## 14. Deserializing account data without checking length
//!
//! **Anti-pattern**
//! ```zig
//! const data = try account.tryBorrowMutData();
//! var state = @as(*MyAccount, @ptrCast(@alignCast(data.value.ptr)));
//! // MyAccount might be larger than data.value.len
//! ```
//!
//! **Why it's wrong**
//! If the account data is smaller than the expected struct, the pointer cast
//! reads past the buffer boundary, causing undefined behavior.
//!
//! **Fix**
//! ```zig
//! try sdk.guard.assert_min_data_len(account, @sizeOf(MyAccount));
//! const data = try account.tryBorrowMutData();
//! var state = @as(*MyAccount, @ptrCast(@alignCast(data.value.ptr)));
//! ```
//!
//! ## 15. Trusting a token account without verifying its owner
//!
//! **Anti-pattern**
//! ```zig
//! // Assuming any account passed as 'token_account' is a valid SPL token account
//! const token_account = accounts[0];
//! try sdk.token.transfer.transfer(token_account, destination, authority, amount);
//! ```
//!
//! **Why it's wrong**
//! An attacker can pass a fake account that isn't owned by the Token Program.
//! The CPI will fail, but any pre-transfer validations on that account will
//! operate on attacker-controlled data.
//!
//! **Fix**
//! ```zig
//! var token_program_id: sdk.Pubkey = undefined;
//! sdk.token.getTokenProgramId(&token_program_id);
//! try sdk.guard.assert_owner(token_account, &token_program_id);
//! try sdk.token.transfer.transfer(token_account, destination, authority, amount);
//! ```
//!
//! ## 16. Using regular transfer when the authority is a PDA
//!
//! **Anti-pattern**
//! ```zig
//! // vault_token_account is a PDA and should sign, but we use regular transfer
//! try sdk.token.transfer.transfer(
//!     vault_token_account,
//!     user_token_account,
//!     vault_token_account,
//!     amount,
//! );
//! ```
//!
//! **Why it's wrong**
//! Regular `transfer` requires the authority to be a transaction signer. If the
//! authority is a PDA owned by your program, it cannot sign transactions
//! directly. The CPI will fail with `MissingRequiredSignature`.
//!
//! **Fix**
//! ```zig
//! const signer_seeds = &[_][]const u8{ "vault", &owner_key, &[_]u8{bump} };
//! try sdk.token.transfer.transferSigned(
//!     vault_token_account,
//!     user_token_account,
//!     vault_token_account,
//!     amount,
//!     signer_seeds,
//! );
//! ```
//!
//! ## 17. Creating an ATA without verifying the address
//!
//! **Anti-pattern**
//! ```zig
//! const ata = accounts[1];
//! try sdk.token.ata.createAssociatedTokenAccount(
//!     payer, ata, owner, mint, system_program, token_program,
//! );
//! ```
//!
//! **Why it's wrong**
//! A malicious client could pass any account as the ATA. If you don't verify
//! it's the correct PDA derived from the owner and mint, you might create or
//! fund the wrong account.
//!
//! **Fix**
//! ```zig
//! var expected_ata: sdk.Pubkey = undefined;
//! try sdk.token.ata.getAssociatedTokenAddress(
//!     mint.key(), owner.key(), &expected_ata,
//! );
//! if (!sdk.pubkeyEq(ata.key(), &expected_ata)) {
//!     return error.InvalidAccountData;
//! }
//! try sdk.token.ata.createAssociatedTokenAccount(
//!     payer, ata, owner, mint, system_program, token_program,
//! );
//! ```
//!
//! ## Checklist
//!
//! Before considering any instruction handler complete, verify:
//!
//! - [ ] All privileged accounts checked with `assert_signer`
//! - [ ] All mutable accounts checked with `assert_writable`
//! - [ ] All immutable accounts checked with `assert_immutable`
//! - [ ] All program-owned accounts checked with `assert_owner`
//! - [ ] All PDAs checked with `assert_pda`
//! - [ ] All typed accounts validated with `AccountSchema`
//! - [ ] Account data length checked with `assert_min_data_len`
//! - [ ] Initialized accounts verified with `assert_initialized`
//! - [ ] Uninitialized accounts verified with `assert_uninitialized`
//! - [ ] Distinct accounts verified with `assert_keys_not_equal`
//! - [ ] Target programs verified with `assert_program_id` and `assert_executable`
//! - [ ] All borrows released before CPI
//! - [ ] No module-scope constant addresses passed to syscalls/CPI
//! - [ ] New accounts are rent exempt
