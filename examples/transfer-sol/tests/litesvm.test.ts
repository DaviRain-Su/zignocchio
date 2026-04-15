/**
 * Transfer-SOL program litesvm integration test.
 *
 * Tests System Program CPI for lamport transfers, including success cases
 * and security rejections (non-signer, zero amount).
 */

import {
  startLitesvm,
  deployProgramToLitesvm,
  sendTransaction,
  getAccount,
  airdrop,
} from '../../../client/src/litesvm';
import {
  Keypair,
  PublicKey,
  TransactionInstruction,
  SystemProgram,
} from '@solana/web3.js';

describe('litesvm transfer-sol', () => {
  let programId: PublicKey;
  let payer: Keypair;
  let svm: ReturnType<typeof startLitesvm>['svm'];

  beforeAll(() => {
    const ctx = startLitesvm();
    svm = ctx.svm;
    payer = ctx.payer;
    programId = deployProgramToLitesvm(svm, { exampleName: 'transfer-sol' });
  });

  function createTransferInstruction(
    fromPubkey: PublicKey,
    toPubkey: PublicKey,
    amount: number
  ): TransactionInstruction {
    const data = Buffer.alloc(8);
    data.writeBigUInt64LE(BigInt(amount), 0);
    return new TransactionInstruction({
      keys: [
        { pubkey: fromPubkey, isSigner: true, isWritable: true },
        { pubkey: toPubkey, isSigner: false, isWritable: true },
        { pubkey: SystemProgram.programId, isSigner: false, isWritable: false },
      ],
      programId,
      data,
    });
  }

  it('should transfer lamports from signer to recipient', async () => {
    const recipient = Keypair.generate();
    const amount = 100_000_000;

    const fromBefore = getAccount(svm, payer.publicKey)!.lamports;
    const toBefore = getAccount(svm, recipient.publicKey)?.lamports ?? 0n;

    const ix = createTransferInstruction(payer.publicKey, recipient.publicKey, amount);
    const result = await sendTransaction(svm, payer, [ix]);

    expect(result.constructor.name).toBe('TransactionMetadata');

    const fromAfter = getAccount(svm, payer.publicKey)!.lamports;
    const toAfter = getAccount(svm, recipient.publicKey)!.lamports;

    expect(Number(toAfter - toBefore)).toBe(amount);
    expect(Number(fromAfter)).toBeLessThan(Number(fromBefore) - amount);
  });

  it('should fail transfer with non-signer', async () => {
    const fakeSigner = Keypair.generate();
    const recipient = Keypair.generate();
    const amount = 100_000_000;

    // Fund fakeSigner so it has lamports (but won't sign)
    airdrop(svm, fakeSigner.publicKey, 1_000_000_000n);

    const ix = createTransferInstruction(fakeSigner.publicKey, recipient.publicKey, amount);

    await expect(sendTransaction(svm, payer, [ix])).rejects.toThrow();
  });

  it('should fail transfer with zero amount', async () => {
    const recipient = Keypair.generate();
    const data = Buffer.alloc(8);
    data.writeBigUInt64LE(0n, 0);

    const ix = new TransactionInstruction({
      keys: [
        { pubkey: payer.publicKey, isSigner: true, isWritable: true },
        { pubkey: recipient.publicKey, isSigner: false, isWritable: true },
        { pubkey: SystemProgram.programId, isSigner: false, isWritable: false },
      ],
      programId,
      data,
    });

    await expect(sendTransaction(svm, payer, [ix])).rejects.toThrow();
  });
});
