/**
 * Escrow program litesvm integration test.
 *
 * Tests a multi-instruction escrow flow: make (create escrow + deposit),
 * accept (taker receives funds, escrow closed), refund (maker gets funds back),
 * plus security checks for unauthorized access.
 */

import {
  startLitesvm,
  deployProgramToLitesvm,
  sendTransaction,
  getAccount,
  airdrop,
} from '../../../client/src/litesvm';
import { TransactionInstruction, Keypair, PublicKey, SystemProgram } from '@solana/web3.js';

describe('escrow litesvm integration', () => {
  const MAKE = 0;
  const ACCEPT = 1;
  const REFUND = 2;

  function findEscrowPDA(makerPubkey: PublicKey, programId: PublicKey): [PublicKey, number] {
    return PublicKey.findProgramAddressSync(
      [Buffer.from('escrow'), makerPubkey.toBuffer()],
      programId
    );
  }

  function createMakeInstruction(
    makerPubkey: PublicKey,
    escrow: PublicKey,
    takerPubkey: PublicKey,
    programId: PublicKey,
    amount: number
  ): TransactionInstruction {
    const data = Buffer.alloc(41);
    data.writeUInt8(MAKE, 0);
    data.set(takerPubkey.toBuffer(), 1);
    data.writeBigUInt64LE(BigInt(amount), 33);

    return new TransactionInstruction({
      keys: [
        { pubkey: makerPubkey, isSigner: true, isWritable: true },
        { pubkey: escrow, isSigner: false, isWritable: true },
        { pubkey: SystemProgram.programId, isSigner: false, isWritable: false },
      ],
      programId,
      data,
    });
  }

  function createAcceptInstruction(
    takerPubkey: PublicKey,
    escrow: PublicKey,
    makerPubkey: PublicKey,
    programId: PublicKey
  ): TransactionInstruction {
    const data = Buffer.from([ACCEPT]);
    return new TransactionInstruction({
      keys: [
        { pubkey: takerPubkey, isSigner: true, isWritable: true },
        { pubkey: escrow, isSigner: false, isWritable: true },
        { pubkey: makerPubkey, isSigner: false, isWritable: false },
      ],
      programId,
      data,
    });
  }

  function createRefundInstruction(
    makerPubkey: PublicKey,
    escrow: PublicKey,
    programId: PublicKey
  ): TransactionInstruction {
    const data = Buffer.from([REFUND]);
    return new TransactionInstruction({
      keys: [
        { pubkey: makerPubkey, isSigner: true, isWritable: true },
        { pubkey: escrow, isSigner: false, isWritable: true },
      ],
      programId,
      data,
    });
  }

  describe('Make', () => {
    it('should create escrow and deposit lamports', async () => {
      const ctx = startLitesvm();
      const svm = ctx.svm;
      const payer = ctx.payer;
      const programId = deployProgramToLitesvm(svm, { exampleName: 'escrow' });
      const maker = Keypair.generate();
      airdrop(svm, maker.publicKey, 1_000_000_000n);

      const taker = Keypair.generate();
      const [escrow] = findEscrowPDA(maker.publicKey, programId);
      const amount = 100_000_000;

      const makerBalanceBefore = Number(getAccount(svm, maker.publicKey)!.lamports);

      const ix = createMakeInstruction(maker.publicKey, escrow, taker.publicKey, programId, amount);
      const result = await sendTransaction(svm, payer, [ix], [maker]);
      expect(result.constructor.name).toBe('TransactionMetadata');

      const escrowBalance = Number(getAccount(svm, escrow)!.lamports);
      expect(escrowBalance).toBeGreaterThanOrEqual(amount);

      const makerBalanceAfter = Number(getAccount(svm, maker.publicKey)!.lamports);
      expect(makerBalanceAfter).toBeLessThan(makerBalanceBefore - amount);
    });

    it('should fail to make with zero amount', async () => {
      const ctx = startLitesvm();
      const svm = ctx.svm;
      const payer = ctx.payer;
      const programId = deployProgramToLitesvm(svm, { exampleName: 'escrow' });
      const maker = Keypair.generate();
      airdrop(svm, maker.publicKey, 1_000_000_000n);

      const taker = Keypair.generate();
      const [escrow] = findEscrowPDA(maker.publicKey, programId);

      const ix = createMakeInstruction(maker.publicKey, escrow, taker.publicKey, programId, 0);
      await expect(sendTransaction(svm, payer, [ix], [maker])).rejects.toThrow();
    });
  });

  describe('Accept', () => {
    it('should allow taker to accept escrow', async () => {
      const ctx = startLitesvm();
      const svm = ctx.svm;
      const payer = ctx.payer;
      const programId = deployProgramToLitesvm(svm, { exampleName: 'escrow' });
      const freshMaker = Keypair.generate();
      const freshTaker = Keypair.generate();
      airdrop(svm, freshMaker.publicKey, 1_000_000_000n);
      airdrop(svm, freshTaker.publicKey, 1_000_000_000n);

      const [escrow] = findEscrowPDA(freshMaker.publicKey, programId);
      const amount = 100_000_000;

      const makeIx = createMakeInstruction(freshMaker.publicKey, escrow, freshTaker.publicKey, programId, amount);
      await sendTransaction(svm, payer, [makeIx], [freshMaker]);

      const escrowBalanceBefore = Number(getAccount(svm, escrow)!.lamports);
      expect(escrowBalanceBefore).toBeGreaterThan(0);

      const takerBalanceBefore = Number(getAccount(svm, freshTaker.publicKey)!.lamports);

      const acceptIx = createAcceptInstruction(freshTaker.publicKey, escrow, freshMaker.publicKey, programId);
      const result = await sendTransaction(svm, payer, [acceptIx], [freshTaker]);
      expect(result.constructor.name).toBe('TransactionMetadata');

      const escrowBalanceAfter = Number(getAccount(svm, escrow)?.lamports ?? 0n);
      expect(escrowBalanceAfter).toBe(0);

      const takerBalanceAfter = Number(getAccount(svm, freshTaker.publicKey)!.lamports);
      expect(takerBalanceAfter).toBeGreaterThan(takerBalanceBefore);
    });

    it('should fail accept by unauthorized taker', async () => {
      const ctx = startLitesvm();
      const svm = ctx.svm;
      const payer = ctx.payer;
      const programId = deployProgramToLitesvm(svm, { exampleName: 'escrow' });
      const freshMaker = Keypair.generate();
      const freshTaker = Keypair.generate();
      const wrongTaker = Keypair.generate();
      airdrop(svm, freshMaker.publicKey, 1_000_000_000n);
      airdrop(svm, freshTaker.publicKey, 1_000_000_000n);
      airdrop(svm, wrongTaker.publicKey, 1_000_000_000n);

      const [escrow] = findEscrowPDA(freshMaker.publicKey, programId);
      const makeIx = createMakeInstruction(freshMaker.publicKey, escrow, freshTaker.publicKey, programId, 100_000_000);
      await sendTransaction(svm, payer, [makeIx], [freshMaker]);

      const acceptIx = createAcceptInstruction(wrongTaker.publicKey, escrow, freshMaker.publicKey, programId);
      await expect(sendTransaction(svm, payer, [acceptIx], [wrongTaker])).rejects.toThrow();
    });
  });

  describe('Refund', () => {
    it('should allow maker to refund escrow', async () => {
      const ctx = startLitesvm();
      const svm = ctx.svm;
      const payer = ctx.payer;
      const programId = deployProgramToLitesvm(svm, { exampleName: 'escrow' });
      const freshMaker = Keypair.generate();
      const freshTaker = Keypair.generate();
      airdrop(svm, freshMaker.publicKey, 1_000_000_000n);
      airdrop(svm, freshTaker.publicKey, 1_000_000_000n);

      const [escrow] = findEscrowPDA(freshMaker.publicKey, programId);
      const amount = 100_000_000;

      const makeIx = createMakeInstruction(freshMaker.publicKey, escrow, freshTaker.publicKey, programId, amount);
      await sendTransaction(svm, payer, [makeIx], [freshMaker]);

      const escrowBalanceBefore = Number(getAccount(svm, escrow)!.lamports);
      expect(escrowBalanceBefore).toBeGreaterThan(0);

      const makerBalanceBefore = Number(getAccount(svm, freshMaker.publicKey)!.lamports);

      const refundIx = createRefundInstruction(freshMaker.publicKey, escrow, programId);
      const result = await sendTransaction(svm, payer, [refundIx], [freshMaker]);
      expect(result.constructor.name).toBe('TransactionMetadata');

      const escrowBalanceAfter = Number(getAccount(svm, escrow)?.lamports ?? 0n);
      expect(escrowBalanceAfter).toBe(0);

      const makerBalanceAfter = Number(getAccount(svm, freshMaker.publicKey)!.lamports);
      expect(makerBalanceAfter).toBeGreaterThan(makerBalanceBefore);
    });
  });

  describe('Security', () => {
    it('should fail make with wrong signer', async () => {
      const ctx = startLitesvm();
      const svm = ctx.svm;
      const payer = ctx.payer;
      const programId = deployProgramToLitesvm(svm, { exampleName: 'escrow' });
      const maker = Keypair.generate();
      const wrongMaker = Keypair.generate();
      airdrop(svm, maker.publicKey, 1_000_000_000n);
      airdrop(svm, wrongMaker.publicKey, 1_000_000_000n);

      const taker = Keypair.generate();
      const [escrow] = findEscrowPDA(maker.publicKey, programId);

      const ix = createMakeInstruction(maker.publicKey, escrow, taker.publicKey, programId, 100_000_000);
      await expect(sendTransaction(svm, payer, [ix], [wrongMaker])).rejects.toThrow();
    });

    it('should fail refund by non-maker', async () => {
      const ctx = startLitesvm();
      const svm = ctx.svm;
      const payer = ctx.payer;
      const programId = deployProgramToLitesvm(svm, { exampleName: 'escrow' });
      const freshMaker = Keypair.generate();
      const freshTaker = Keypair.generate();
      airdrop(svm, freshMaker.publicKey, 1_000_000_000n);
      airdrop(svm, freshTaker.publicKey, 1_000_000_000n);

      const [escrow] = findEscrowPDA(freshMaker.publicKey, programId);
      const makeIx = createMakeInstruction(freshMaker.publicKey, escrow, freshTaker.publicKey, programId, 100_000_000);
      await sendTransaction(svm, payer, [makeIx], [freshMaker]);

      const refundIx = createRefundInstruction(freshMaker.publicKey, escrow, programId);
      await expect(sendTransaction(svm, payer, [refundIx], [freshTaker])).rejects.toThrow();
    });
  });
});
