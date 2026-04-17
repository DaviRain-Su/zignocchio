/**
 * Counter program litesvm integration test.
 *
 * Tests a stateful program that reads and writes a u64 counter value
 * to a pre-initialized account.
 */

import {
  startLitesvm,
  deployProgramToLitesvm,
  sendTransaction,
  setAccount,
  getAccount,
} from '../../../client/src/litesvm';
import { TransactionInstruction, Keypair } from '@solana/web3.js';

describe('counter litesvm integration', () => {
  it('increments counter account', async () => {
    const { svm, payer } = startLitesvm();
    const programId = deployProgramToLitesvm(svm, { exampleName: 'counter' });

    // Create a counter account (8 bytes for u64)
    const counterKeypair = Keypair.generate();
    setAccount(svm, counterKeypair.publicKey, {
      data: new Uint8Array(8),
      executable: false,
      lamports: 1_000_000n,
      owner: programId,
      space: 8n,
    });

    // Verify initial counter value is 0
    const accountBefore = getAccount(svm, counterKeypair.publicKey);
    expect(accountBefore).toBeDefined();
    const dataBefore = Buffer.from(accountBefore!.data);
    expect(dataBefore.readBigUInt64LE(0)).toBe(BigInt(0));

    // Instruction 0 = increment counter
    // counter program expects accounts[0] to be the counter account
    const ix = new TransactionInstruction({
      keys: [
        { pubkey: counterKeypair.publicKey, isSigner: false, isWritable: true },
      ],
      programId,
      data: Buffer.from([0]),
    });

    const result = await sendTransaction(svm, payer, [ix]);

    expect(result).toBeDefined();
    expect(result.constructor.name).toBe('TransactionMetadata');

    // Verify counter value is now 1
    const accountAfter = getAccount(svm, counterKeypair.publicKey);
    expect(accountAfter).toBeDefined();
    const dataAfter = Buffer.from(accountAfter!.data);
    expect(dataAfter.readBigUInt64LE(0)).toBe(BigInt(1));
  });
});
