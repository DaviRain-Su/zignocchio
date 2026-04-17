/**
 * Token-Vault program litesvm integration test.
 *
 * Tests SPL Token interactions in litesvm: initialize a PDA token account,
 * deposit tokens, withdraw tokens, and security checks. Because litesvm
 * does not provide `createMint` / `createAccount` helpers, this test manually
 * constructs mint (82 bytes) and token account (165 bytes) data using
 * `@solana/buffer-layout` and injects them via `setAccount`.
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
import { TOKEN_PROGRAM_ID } from '@solana/spl-token';
import * as bufferLayout from '@solana/buffer-layout';
const struct = (bufferLayout as any).struct;
const u8 = (bufferLayout as any).u8;
const u32 = (bufferLayout as any).u32;
const blob = (bufferLayout as any).blob;

describe('token-vault litesvm integration', () => {
  const DEPOSIT = 0;
  const WITHDRAW = 1;
  const INITIALIZE = 2;
  const TOKEN_PROGRAM_ID_PK = new PublicKey('TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA');
  const RENT_SYSVAR = new PublicKey('SysvarRent111111111111111111111111111111111');

  function createMintData(mintAuthority: PublicKey, supply: bigint, decimals: number): Buffer {
    const mintLayout = struct([
      u32('mintAuthorityOption'),
      blob(32, 'mintAuthority'),
      blob(8, 'supply'),
      u8('decimals'),
      u8('isInitialized'),
      u32('freezeAuthorityOption'),
      blob(32, 'freezeAuthority'),
    ]);
    const data = Buffer.alloc(82);
    mintLayout.encode(
      {
        mintAuthorityOption: 1,
        mintAuthority: mintAuthority.toBuffer(),
        supply: Buffer.from(new BigUint64Array([supply]).buffer),
        decimals,
        isInitialized: 1,
        freezeAuthorityOption: 0,
        freezeAuthority: Buffer.alloc(32),
      },
      data
    );
    return data;
  }

  function createTokenAccountData(mint: PublicKey, owner: PublicKey, amount: bigint): Buffer {
    const accountLayout = struct([
      blob(32, 'mint'),
      blob(32, 'owner'),
      blob(8, 'amount'),
      u32('delegateOption'),
      blob(32, 'delegate'),
      u8('state'),
      u32('isNativeOption'),
      blob(8, 'isNative'),
      blob(8, 'delegatedAmount'),
      u32('closeAuthorityOption'),
      blob(32, 'closeAuthority'),
    ]);
    const data = Buffer.alloc(165);
    accountLayout.encode(
      {
        mint: mint.toBuffer(),
        owner: owner.toBuffer(),
        amount: Buffer.from(new BigUint64Array([amount]).buffer),
        delegateOption: 0,
        delegate: Buffer.alloc(32),
        state: 1,
        isNativeOption: 0,
        isNative: Buffer.from(new BigUint64Array([BigInt(0)]).buffer),
        delegatedAmount: Buffer.from(new BigUint64Array([BigInt(0)]).buffer),
        closeAuthorityOption: 0,
        closeAuthority: Buffer.alloc(32),
      },
      data
    );
    return data;
  }

  function findVaultPDA(ownerPubkey: PublicKey, programId: PublicKey): [PublicKey, number] {
    return PublicKey.findProgramAddressSync(
      [Buffer.from('vault'), ownerPubkey.toBuffer()],
      programId
    );
  }

  function createInitializeInstruction(
    vaultPDA: PublicKey,
    mint: PublicKey,
    owner: PublicKey,
    programId: PublicKey
  ): TransactionInstruction {
    return new TransactionInstruction({
      keys: [
        { pubkey: vaultPDA, isSigner: false, isWritable: true },
        { pubkey: mint, isSigner: false, isWritable: false },
        { pubkey: owner, isSigner: true, isWritable: true },
        { pubkey: SystemProgram.programId, isSigner: false, isWritable: false },
        { pubkey: TOKEN_PROGRAM_ID_PK, isSigner: false, isWritable: false },
        { pubkey: RENT_SYSVAR, isSigner: false, isWritable: false },
      ],
      programId,
      data: Buffer.from([INITIALIZE]),
    });
  }

  function createDepositInstruction(
    userTokenAccount: PublicKey,
    vaultTokenAccount: PublicKey,
    owner: PublicKey,
    programId: PublicKey,
    amount: bigint
  ): TransactionInstruction {
    const data = Buffer.alloc(9);
    data[0] = DEPOSIT;
    data.writeBigUInt64LE(amount, 1);
    return new TransactionInstruction({
      keys: [
        { pubkey: userTokenAccount, isSigner: false, isWritable: true },
        { pubkey: vaultTokenAccount, isSigner: false, isWritable: true },
        { pubkey: owner, isSigner: true, isWritable: false },
        { pubkey: TOKEN_PROGRAM_ID_PK, isSigner: false, isWritable: false },
      ],
      programId,
      data,
    });
  }

  function createWithdrawInstruction(
    vaultTokenAccount: PublicKey,
    userTokenAccount: PublicKey,
    owner: PublicKey,
    programId: PublicKey
  ): TransactionInstruction {
    return new TransactionInstruction({
      keys: [
        { pubkey: vaultTokenAccount, isSigner: false, isWritable: true },
        { pubkey: userTokenAccount, isSigner: false, isWritable: true },
        { pubkey: owner, isSigner: true, isWritable: false },
        { pubkey: TOKEN_PROGRAM_ID_PK, isSigner: false, isWritable: false },
      ],
      programId,
      data: Buffer.from([WITHDRAW]),
    });
  }

  function getTokenBalance(svm: ReturnType<typeof startLitesvm>['svm'], account: PublicKey): bigint {
    const acc = getAccount(svm, account);
    if (!acc) return 0n;
    // amount is at offset 64 in the token account data (32 mint + 32 owner)
    return Buffer.from(acc.data).readBigUInt64LE(64);
  }

  describe('Initialize', () => {
    it('should initialize vault token account', async () => {
      const ctx = startLitesvm();
      const svm = ctx.svm.withDefaultPrograms();
      const payer = ctx.payer;
      const programId = deployProgramToLitesvm(svm, { exampleName: 'token-vault' });
      const owner = Keypair.generate();
      airdrop(svm, owner.publicKey, 1_000_000_000n);

      const mint = Keypair.generate().publicKey;
      const [vaultPDA] = findVaultPDA(owner.publicKey, programId);

      // Pre-create mint
      setAccount(svm, mint, {
        data: createMintData(owner.publicKey, BigInt(1_000_000_000), 9),
        executable: false,
        lamports: 1461600n,
        owner: TOKEN_PROGRAM_ID_PK,
        space: 82n,
      });

      const ix = createInitializeInstruction(vaultPDA, mint, owner.publicKey, programId);
      const result = await sendTransaction(svm, payer, [ix], [owner]);
      expect(result.constructor.name).toBe('TransactionMetadata');

      const vaultAccount = getAccount(svm, vaultPDA);
      expect(vaultAccount).toBeDefined();
      expect(vaultAccount!.owner).toBe(TOKEN_PROGRAM_ID.toBase58());
    });
  });

  describe('Deposit', () => {
    it('should deposit tokens into vault', async () => {
      const ctx = startLitesvm();
      const svm = ctx.svm.withDefaultPrograms();
      const payer = ctx.payer;
      const programId = deployProgramToLitesvm(svm, { exampleName: 'token-vault' });
      const owner = Keypair.generate();
      airdrop(svm, owner.publicKey, 1_000_000_000n);

      const mint = Keypair.generate().publicKey;
      const userTokenAccount = Keypair.generate().publicKey;
      const [vaultPDA] = findVaultPDA(owner.publicKey, programId);
      const depositAmount = BigInt(500_000_000);

      // Setup mint
      setAccount(svm, mint, {
        data: createMintData(owner.publicKey, BigInt(1_000_000_000), 9),
        executable: false,
        lamports: 1461600n,
        owner: TOKEN_PROGRAM_ID_PK,
        space: 82n,
      });

      // Setup user token account with initial balance
      setAccount(svm, userTokenAccount, {
        data: createTokenAccountData(mint, owner.publicKey, BigInt(1_000_000_000)),
        executable: false,
        lamports: 2039280n,
        owner: TOKEN_PROGRAM_ID_PK,
        space: 165n,
      });

      // Initialize vault
      const initIx = createInitializeInstruction(vaultPDA, mint, owner.publicKey, programId);
      await sendTransaction(svm, payer, [initIx], [owner]);

      // Deposit
      const depositIx = createDepositInstruction(userTokenAccount, vaultPDA, owner.publicKey, programId, depositAmount);
      const result = await sendTransaction(svm, payer, [depositIx], [owner]);
      expect(result.constructor.name).toBe('TransactionMetadata');

      expect(getTokenBalance(svm, userTokenAccount)).toBe(BigInt(500_000_000));
      expect(getTokenBalance(svm, vaultPDA)).toBe(depositAmount);
    });

    it('should fail to deposit zero amount', async () => {
      const ctx = startLitesvm();
      const svm = ctx.svm.withDefaultPrograms();
      const payer = ctx.payer;
      const programId = deployProgramToLitesvm(svm, { exampleName: 'token-vault' });
      const owner = Keypair.generate();
      airdrop(svm, owner.publicKey, 1_000_000_000n);

      const mint = Keypair.generate().publicKey;
      const userTokenAccount = Keypair.generate().publicKey;
      const [vaultPDA] = findVaultPDA(owner.publicKey, programId);

      setAccount(svm, mint, {
        data: createMintData(owner.publicKey, BigInt(1_000_000_000), 9),
        executable: false,
        lamports: 1461600n,
        owner: TOKEN_PROGRAM_ID_PK,
        space: 82n,
      });

      setAccount(svm, userTokenAccount, {
        data: createTokenAccountData(mint, owner.publicKey, BigInt(1_000_000_000)),
        executable: false,
        lamports: 2039280n,
        owner: TOKEN_PROGRAM_ID_PK,
        space: 165n,
      });

      const initIx = createInitializeInstruction(vaultPDA, mint, owner.publicKey, programId);
      await sendTransaction(svm, payer, [initIx], [owner]);

      const depositIx = createDepositInstruction(userTokenAccount, vaultPDA, owner.publicKey, programId, BigInt(0));
      await expect(sendTransaction(svm, payer, [depositIx], [owner])).rejects.toThrow();
    });
  });

  describe('Withdraw', () => {
    it('should withdraw all tokens from vault', async () => {
      const ctx = startLitesvm();
      const svm = ctx.svm.withDefaultPrograms();
      const payer = ctx.payer;
      const programId = deployProgramToLitesvm(svm, { exampleName: 'token-vault' });
      const owner = Keypair.generate();
      airdrop(svm, owner.publicKey, 1_000_000_000n);

      const mint = Keypair.generate().publicKey;
      const userTokenAccount = Keypair.generate().publicKey;
      const [vaultPDA] = findVaultPDA(owner.publicKey, programId);
      const depositAmount = BigInt(500_000_000);

      setAccount(svm, mint, {
        data: createMintData(owner.publicKey, BigInt(1_000_000_000), 9),
        executable: false,
        lamports: 1461600n,
        owner: TOKEN_PROGRAM_ID_PK,
        space: 82n,
      });

      setAccount(svm, userTokenAccount, {
        data: createTokenAccountData(mint, owner.publicKey, BigInt(1_000_000_000)),
        executable: false,
        lamports: 2039280n,
        owner: TOKEN_PROGRAM_ID_PK,
        space: 165n,
      });

      const initIx = createInitializeInstruction(vaultPDA, mint, owner.publicKey, programId);
      await sendTransaction(svm, payer, [initIx], [owner]);

      const depositIx = createDepositInstruction(userTokenAccount, vaultPDA, owner.publicKey, programId, depositAmount);
      await sendTransaction(svm, payer, [depositIx], [owner]);

      const withdrawIx = createWithdrawInstruction(vaultPDA, userTokenAccount, owner.publicKey, programId);
      const result = await sendTransaction(svm, payer, [withdrawIx], [owner]);
      expect(result.constructor.name).toBe('TransactionMetadata');

      expect(getTokenBalance(svm, vaultPDA)).toBe(BigInt(0));
      expect(getTokenBalance(svm, userTokenAccount)).toBe(BigInt(1_000_000_000));
    });

    it('should fail to withdraw from empty vault', async () => {
      const ctx = startLitesvm();
      const svm = ctx.svm.withDefaultPrograms();
      const payer = ctx.payer;
      const programId = deployProgramToLitesvm(svm, { exampleName: 'token-vault' });
      const owner = Keypair.generate();
      airdrop(svm, owner.publicKey, 1_000_000_000n);

      const mint = Keypair.generate().publicKey;
      const userTokenAccount = Keypair.generate().publicKey;
      const [vaultPDA] = findVaultPDA(owner.publicKey, programId);

      setAccount(svm, mint, {
        data: createMintData(owner.publicKey, BigInt(1_000_000_000), 9),
        executable: false,
        lamports: 1461600n,
        owner: TOKEN_PROGRAM_ID_PK,
        space: 82n,
      });

      setAccount(svm, userTokenAccount, {
        data: createTokenAccountData(mint, owner.publicKey, BigInt(1_000_000_000)),
        executable: false,
        lamports: 2039280n,
        owner: TOKEN_PROGRAM_ID_PK,
        space: 165n,
      });

      const initIx = createInitializeInstruction(vaultPDA, mint, owner.publicKey, programId);
      await sendTransaction(svm, payer, [initIx], [owner]);

      const withdrawIx = createWithdrawInstruction(vaultPDA, userTokenAccount, owner.publicKey, programId);
      await expect(sendTransaction(svm, payer, [withdrawIx], [owner])).rejects.toThrow();
    });
  });

  describe('Full Cycle', () => {
    it('should complete a full deposit-withdraw cycle', async () => {
      const ctx = startLitesvm();
      const svm = ctx.svm.withDefaultPrograms();
      const payer = ctx.payer;
      const programId = deployProgramToLitesvm(svm, { exampleName: 'token-vault' });
      const newUser = Keypair.generate();
      airdrop(svm, newUser.publicKey, 1_000_000_000n);

      const mint = Keypair.generate().publicKey;
      const userTokenAccount = Keypair.generate().publicKey;
      const [vaultPDA] = findVaultPDA(newUser.publicKey, programId);
      const depositAmount = BigInt(600_000_000);

      setAccount(svm, mint, {
        data: createMintData(newUser.publicKey, BigInt(1_000_000_000), 9),
        executable: false,
        lamports: 1461600n,
        owner: TOKEN_PROGRAM_ID_PK,
        space: 82n,
      });

      setAccount(svm, userTokenAccount, {
        data: createTokenAccountData(mint, newUser.publicKey, BigInt(1_000_000_000)),
        executable: false,
        lamports: 2039280n,
        owner: TOKEN_PROGRAM_ID_PK,
        space: 165n,
      });

      const initIx = createInitializeInstruction(vaultPDA, mint, newUser.publicKey, programId);
      await sendTransaction(svm, payer, [initIx], [newUser]);

      const depositIx = createDepositInstruction(userTokenAccount, vaultPDA, newUser.publicKey, programId, depositAmount);
      await sendTransaction(svm, payer, [depositIx], [newUser]);
      expect(getTokenBalance(svm, vaultPDA)).toBe(depositAmount);

      const withdrawIx = createWithdrawInstruction(vaultPDA, userTokenAccount, newUser.publicKey, programId);
      await sendTransaction(svm, payer, [withdrawIx], [newUser]);
      expect(getTokenBalance(svm, vaultPDA)).toBe(BigInt(0));
      expect(getTokenBalance(svm, userTokenAccount)).toBe(BigInt(1_000_000_000));
    });
  });

  describe('Security', () => {
    it('should fail with wrong signer', async () => {
      const ctx = startLitesvm();
      const svm = ctx.svm.withDefaultPrograms();
      const payer = ctx.payer;
      const programId = deployProgramToLitesvm(svm, { exampleName: 'token-vault' });
      const owner = Keypair.generate();
      const wrongUser = Keypair.generate();
      airdrop(svm, owner.publicKey, 1_000_000_000n);
      airdrop(svm, wrongUser.publicKey, 1_000_000_000n);

      const mint = Keypair.generate().publicKey;
      const userTokenAccount = Keypair.generate().publicKey;
      const [vaultPDA] = findVaultPDA(owner.publicKey, programId);

      setAccount(svm, mint, {
        data: createMintData(owner.publicKey, BigInt(1_000_000_000), 9),
        executable: false,
        lamports: 1461600n,
        owner: TOKEN_PROGRAM_ID_PK,
        space: 82n,
      });

      setAccount(svm, userTokenAccount, {
        data: createTokenAccountData(mint, owner.publicKey, BigInt(1_000_000_000)),
        executable: false,
        lamports: 2039280n,
        owner: TOKEN_PROGRAM_ID_PK,
        space: 165n,
      });

      const initIx = createInitializeInstruction(vaultPDA, mint, owner.publicKey, programId);
      await sendTransaction(svm, payer, [initIx], [owner]);

      const depositIx = createDepositInstruction(userTokenAccount, vaultPDA, owner.publicKey, programId, BigInt(100_000_000));
      await expect(sendTransaction(svm, payer, [depositIx], [wrongUser])).rejects.toThrow();
    });

    it('should fail with invalid vault PDA', async () => {
      const ctx = startLitesvm();
      const svm = ctx.svm.withDefaultPrograms();
      const payer = ctx.payer;
      const programId = deployProgramToLitesvm(svm, { exampleName: 'token-vault' });
      const owner = Keypair.generate();
      airdrop(svm, owner.publicKey, 1_000_000_000n);

      const mint = Keypair.generate().publicKey;
      const userTokenAccount = Keypair.generate().publicKey;
      const randomVault = Keypair.generate().publicKey;

      setAccount(svm, mint, {
        data: createMintData(owner.publicKey, BigInt(1_000_000_000), 9),
        executable: false,
        lamports: 1461600n,
        owner: TOKEN_PROGRAM_ID_PK,
        space: 82n,
      });

      setAccount(svm, userTokenAccount, {
        data: createTokenAccountData(mint, owner.publicKey, BigInt(1_000_000_000)),
        executable: false,
        lamports: 2039280n,
        owner: TOKEN_PROGRAM_ID_PK,
        space: 165n,
      });

      const depositIx = createDepositInstruction(userTokenAccount, randomVault, owner.publicKey, programId, BigInt(100_000_000));
      await expect(sendTransaction(svm, payer, [depositIx], [owner])).rejects.toThrow();
    });
  });
});
