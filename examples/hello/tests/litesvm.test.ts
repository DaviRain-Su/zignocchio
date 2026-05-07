/**
 * Hello program litesvm integration test.
 *
 * Verifies the simplest Zignocchio program executes successfully in litesvm.
 */

import {
  startLitesvm,
  deployProgramToLitesvm,
  sendTransaction,
} from '../../../client/src/litesvm';
import { TransactionInstruction } from '@solana/web3.js';
import { createHash } from 'crypto';

function instructionDiscriminator(name: string): Buffer {
  return createHash('sha256').update(`global:${name}`).digest().subarray(0, 8);
}

describe('hello litesvm integration', () => {
  it('executes hello successfully with legacy empty data', async () => {
    const { svm, payer } = startLitesvm();
    const programId = deployProgramToLitesvm(svm, { exampleName: 'hello' });

    const ix = new TransactionInstruction({
      keys: [],
      programId,
      data: Buffer.alloc(0),
    });

    const result = await sendTransaction(svm, payer, [ix]);

    expect(result).toBeDefined();
    expect(result.constructor.name).toBe('TransactionMetadata');
  });

  it('executes hello successfully with the framework discriminator', async () => {
    const { svm, payer } = startLitesvm();
    const programId = deployProgramToLitesvm(svm, { exampleName: 'hello' });

    const ix = new TransactionInstruction({
      keys: [],
      programId,
      data: instructionDiscriminator('hello'),
    });

    const result = await sendTransaction(svm, payer, [ix]);

    expect(result).toBeDefined();
    expect(result.constructor.name).toBe('TransactionMetadata');
  });
});
