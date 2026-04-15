/**
 * Vault program litesvm integration test.
 *
 * Tests a lamport vault with PDA-based accounts: deposit SOL into a vault,
 * withdraw all SOL back, and security checks for invalid signers / PDAs.
 */

import {
  startLitesvm,
  deployProgramToLitesvm,
  sendTransaction,
  getAccount,
  setAccount,
  airdrop,
} from '../../../client/src/litesvm';
import { TransactionInstruction, Keypair, PublicKey, SystemProgram } from '@solana/web3.js';

describe('vault litesvm integration', () => {
  const DEPOSIT = 0;
  const WITHDRAW = 1;

  function findVaultPDA(userPubkey: PublicKey, programId: PublicKey): PublicKey {
    const [pda] = PublicKey.findProgramAddressSync(
      [Buffer.from('vault'), userPubkey.toBuffer()],
      programId
    );
    return pda;
  }

  function createDepositInstruction(
    owner: PublicKey,
    vault: PublicKey,
    programId: PublicKey,
    amount: number
  ): TransactionInstruction {
    const data = Buffer.alloc(9);
    data.writeUInt8(DEPOSIT, 0);
    data.writeBigUInt64LE(BigInt(amount), 1);

    return new TransactionInstruction({
      keys: [
        { pubkey: owner, isSigner: true, isWritable: true },
        { pubkey: vault, isSigner: false, isWritable: true },
        { pubkey: SystemProgram.programId, isSigner: false, isWritable: false },
      ],
      programId,
      data,
    });
  }

  function createWithdrawInstruction(
    owner: PublicKey,
    vault: PublicKey,
    programId: PublicKey
  ): TransactionInstruction {
    const data = Buffer.from([WITHDRAW]);

    return new TransactionInstruction({
      keys: [
        { pubkey: owner, isSigner: true, isWritable: true },
        { pubkey: vault, isSigner: false, isWritable: true },
        { pubkey: SystemProgram.programId, isSigner: false, isWritable: false },
      ],
      programId,
      data,
    });
  }

  describe('Deposit', () => {
    it('should deposit lamports into vault', async () => {
      const { svm, payer } = startLitesvm();
      const programId = deployProgramToLitesvm(svm, { exampleName: 'vault' });
      const user = Keypair.generate();
      airdrop(svm, user.publicKey, 1_000_000_000n);

      const vault = findVaultPDA(user.publicKey, programId);
      const depositAmount = 100_000_000;

      // Pre-create vault PDA as a system-owned account with 0 lamports
      setAccount(svm, vault, {
        data: new Uint8Array(0),
        executable: false,
        lamports: 0n,
        owner: SystemProgram.programId,
        space: 0n,
      });

      const userBalanceBefore = getAccount(svm, user.publicKey)!.lamports;

      const ix = createDepositInstruction(user.publicKey, vault, programId, depositAmount);
      const result = await sendTransaction(svm, payer, [ix], [user]);

      expect(result).toBeDefined();
      expect(result.constructor.name).toBe('TransactionMetadata');

      const vaultBalance = getAccount(svm, vault)!.lamports;
      expect(Number(vaultBalance)).toBe(depositAmount);

      const userBalanceAfter = getAccount(svm, user.publicKey)!.lamports;
      expect(Number(userBalanceAfter)).toBeLessThanOrEqual(Number(userBalanceBefore) - depositAmount);
    });

    it('should fail to deposit zero amount', async () => {
      const { svm, payer } = startLitesvm();
      const programId = deployProgramToLitesvm(svm, { exampleName: 'vault' });
      const user = Keypair.generate();
      airdrop(svm, user.publicKey, 1_000_000_000n);

      const vault = findVaultPDA(user.publicKey, programId);

      setAccount(svm, vault, {
        data: new Uint8Array(0),
        executable: false,
        lamports: 0n,
        owner: SystemProgram.programId,
        space: 0n,
      });

      const ix = createDepositInstruction(user.publicKey, vault, programId, 0);
      await expect(sendTransaction(svm, payer, [ix], [user])).rejects.toThrow();
    });

    it('should fail to deposit into already-filled vault', async () => {
      const { svm, payer } = startLitesvm();
      const programId = deployProgramToLitesvm(svm, { exampleName: 'vault' });
      const user = Keypair.generate();
      airdrop(svm, user.publicKey, 1_000_000_000n);

      const vault = findVaultPDA(user.publicKey, programId);

      setAccount(svm, vault, {
        data: new Uint8Array(0),
        executable: false,
        lamports: 50_000_000n,
        owner: SystemProgram.programId,
        space: 0n,
      });

      const ix = createDepositInstruction(user.publicKey, vault, programId, 50_000_000);
      await expect(sendTransaction(svm, payer, [ix], [user])).rejects.toThrow();
    });
  });

  describe('Withdraw', () => {
    it('should withdraw all lamports from vault', async () => {
      const { svm, payer } = startLitesvm();
      const programId = deployProgramToLitesvm(svm, { exampleName: 'vault' });
      const user = Keypair.generate();
      airdrop(svm, user.publicKey, 1_000_000_000n);

      const vault = findVaultPDA(user.publicKey, programId);
      const depositAmount = 100_000_000;

      // Setup: deposit first
      setAccount(svm, vault, {
        data: new Uint8Array(0),
        executable: false,
        lamports: 0n,
        owner: SystemProgram.programId,
        space: 0n,
      });

      const depositIx = createDepositInstruction(user.publicKey, vault, programId, depositAmount);
      const depositResult = await sendTransaction(svm, payer, [depositIx], [user]);
      expect(depositResult.constructor.name).toBe('TransactionMetadata');

      const vaultBalanceBefore = Number(getAccount(svm, vault)!.lamports);
      expect(vaultBalanceBefore).toBe(depositAmount);

      const userBalanceBefore = Number(getAccount(svm, user.publicKey)!.lamports);

      const withdrawIx = createWithdrawInstruction(user.publicKey, vault, programId);
      const withdrawResult = await sendTransaction(svm, payer, [withdrawIx], [user]);

      expect(withdrawResult).toBeDefined();
      expect(withdrawResult.constructor.name).toBe('TransactionMetadata');

      const vaultAccountAfter = getAccount(svm, vault);
      expect(vaultAccountAfter?.lamports ?? 0n).toBe(0n);

      const userBalanceAfter = Number(getAccount(svm, user.publicKey)!.lamports);
      expect(userBalanceAfter).toBeGreaterThan(userBalanceBefore);
    });

    it('should fail to withdraw from empty vault', async () => {
      const { svm, payer } = startLitesvm();
      const programId = deployProgramToLitesvm(svm, { exampleName: 'vault' });
      const user = Keypair.generate();
      airdrop(svm, user.publicKey, 1_000_000_000n);

      const vault = findVaultPDA(user.publicKey, programId);

      setAccount(svm, vault, {
        data: new Uint8Array(0),
        executable: false,
        lamports: 0n,
        owner: SystemProgram.programId,
        space: 0n,
      });

      const ix = createWithdrawInstruction(user.publicKey, vault, programId);
      await expect(sendTransaction(svm, payer, [ix], [user])).rejects.toThrow();
    });
  });

  describe('Full Cycle', () => {
    it('should complete a full deposit-withdraw cycle', async () => {
      const { svm, payer } = startLitesvm();
      const programId = deployProgramToLitesvm(svm, { exampleName: 'vault' });
      const newUser = Keypair.generate();
      airdrop(svm, newUser.publicKey, 1_000_000_000n);

      const vault = findVaultPDA(newUser.publicKey, programId);
      const depositAmount = 200_000_000;

      setAccount(svm, vault, {
        data: new Uint8Array(0),
        executable: false,
        lamports: 0n,
        owner: SystemProgram.programId,
        space: 0n,
      });

      const initialBalance = Number(getAccount(svm, newUser.publicKey)!.lamports);

      const depositIx = createDepositInstruction(newUser.publicKey, vault, programId, depositAmount);
      const depositResult = await sendTransaction(svm, payer, [depositIx], [newUser]);
      expect(depositResult.constructor.name).toBe('TransactionMetadata');

      const vaultBalance = Number(getAccount(svm, vault)!.lamports);
      expect(vaultBalance).toBe(depositAmount);

      const withdrawIx = createWithdrawInstruction(newUser.publicKey, vault, programId);
      const withdrawResult = await sendTransaction(svm, payer, [withdrawIx], [newUser]);
      expect(withdrawResult.constructor.name).toBe('TransactionMetadata');

      const vaultAccountAfter = getAccount(svm, vault);
      expect(vaultAccountAfter?.lamports ?? 0n).toBe(0n);

      const finalBalance = Number(getAccount(svm, newUser.publicKey)!.lamports);
      const netLoss = initialBalance - finalBalance;
      expect(netLoss).toBeLessThanOrEqual(10_000);
    });
  });

  describe('Security', () => {
    it('should fail with wrong signer', async () => {
      const { svm, payer } = startLitesvm();
      const programId = deployProgramToLitesvm(svm, { exampleName: 'vault' });
      const user = Keypair.generate();
      const wrongUser = Keypair.generate();
      airdrop(svm, user.publicKey, 1_000_000_000n);
      airdrop(svm, wrongUser.publicKey, 1_000_000_000n);

      const vault = findVaultPDA(user.publicKey, programId);

      setAccount(svm, vault, {
        data: new Uint8Array(0),
        executable: false,
        lamports: 0n,
        owner: SystemProgram.programId,
        space: 0n,
      });

      const ix = createDepositInstruction(user.publicKey, vault, programId, 100_000_000);

      // With @solana/kit, signing fails client-side when a required signer is missing
      await expect(sendTransaction(svm, payer, [ix], [wrongUser])).rejects.toThrow();
    });

    it('should fail with invalid vault PDA', async () => {
      const { svm, payer } = startLitesvm();
      const programId = deployProgramToLitesvm(svm, { exampleName: 'vault' });
      const user = Keypair.generate();
      airdrop(svm, user.publicKey, 1_000_000_000n);

      const randomVault = Keypair.generate().publicKey;
      const depositAmount = 100_000_000;

      const ix = createDepositInstruction(user.publicKey, randomVault, programId, depositAmount);
      await expect(sendTransaction(svm, payer, [ix], [user])).rejects.toThrow();
    });
  });
});
