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

describe('hello litesvm integration', () => {
  it('executes hello successfully', async () => {
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
});
