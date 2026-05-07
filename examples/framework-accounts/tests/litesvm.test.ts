/**
 * Framework account reflection litesvm integration test.
 *
 * Exercises Context(Accounts), first-version account wrappers, and raw
 * AccountInfo binding through an SVM runtime surface.
 */

import {
  startLitesvm,
  deployProgramToLitesvm,
  sendTransaction,
  setAccount,
  getAccount,
} from '../../../client/src/litesvm';
import { TransactionInstruction, Keypair } from '@solana/web3.js';
import { createHash } from 'crypto';

function instructionDiscriminator(name: string): Buffer {
  return createHash('sha256').update(`global:${name}`).digest().subarray(0, 8);
}

describe('framework account reflection litesvm integration', () => {
  it('invokes a wrapper-backed instruction with reflected accounts', async () => {
    const { svm, payer } = startLitesvm();
    const programId = deployProgramToLitesvm(svm, {
      exampleName: 'framework-accounts',
    });

    const signer = Keypair.generate();
    const writable = Keypair.generate();
    const readonly = Keypair.generate();
    const raw = Keypair.generate();

    setAccount(svm, signer.publicKey, {
      lamports: 1_000_000n,
    });
    setAccount(svm, writable.publicKey, {
      data: new Uint8Array(8),
      lamports: 1_000_000n,
      owner: programId,
      space: 8n,
    });
    setAccount(svm, readonly.publicKey, {
      data: Uint8Array.from([0x42]),
      lamports: 1_000_000n,
      space: 1n,
    });
    setAccount(svm, raw.publicKey, {
      data: Uint8Array.from([0x24]),
      lamports: 1_000_000n,
      space: 1n,
    });

    const ix = new TransactionInstruction({
      keys: [
        { pubkey: signer.publicKey, isSigner: true, isWritable: false },
        { pubkey: writable.publicKey, isSigner: false, isWritable: true },
        { pubkey: readonly.publicKey, isSigner: false, isWritable: false },
        { pubkey: programId, isSigner: false, isWritable: false },
        { pubkey: raw.publicKey, isSigner: false, isWritable: false },
      ],
      programId,
      data: instructionDiscriminator('touch_accounts'),
    });

    const result = await sendTransaction(svm, payer, [ix], [signer]);

    expect(result).toBeDefined();
    expect(result.constructor.name).toBe('TransactionMetadata');

    const writableAfter = getAccount(svm, writable.publicKey);
    expect(writableAfter).toBeDefined();
    expect(Array.from(writableAfter!.data.slice(0, 5))).toEqual([
      0xa5,
      0x11,
      0x24,
      1,
      1,
    ]);

    const rawAfter = getAccount(svm, raw.publicKey);
    expect(rawAfter).toBeDefined();
    expect(Array.from(rawAfter!.data)).toEqual([0x24]);
  });
});
