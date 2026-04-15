/**
 * LogOnly program litesvm isolation test.
 *
 * Executes a program that only calls `sol_log_` to verify syscall
 * compatibility in the litesvm environment.
 */

import { LiteSVM } from 'litesvm';
import {
  appendTransactionMessageInstruction,
  createTransactionMessage,
  generateKeyPairSigner,
  pipe,
  setTransactionMessageFeePayerSigner,
  signTransactionMessageWithSigners,
  lamports,
} from '@solana/kit';
import * as path from 'path';
import { execSync } from 'child_process';

const projectRoot = path.join(__dirname, '..', '..', '..');

describe('litesvm logonly isolation test', () => {
  const programPath = path.join(projectRoot, 'zig-out', 'lib', 'logonly.so');

  beforeAll(() => {
    execSync('zig build -Dexample=logonly', { stdio: 'inherit', cwd: projectRoot });
  });

  it('executes a program that only calls sol_log_', async () => {
    const svm = new LiteSVM();
    const payer = await generateKeyPairSigner();
    svm.airdrop(payer.address, lamports(BigInt(2_000_000_000)));

    const programId = await generateKeyPairSigner();
    svm.addProgramFromFile(programId.address, programPath);

    const instruction = {
      accounts: [],
      programAddress: programId.address,
      data: new Uint8Array(0),
    };

    const transaction = await pipe(
      createTransactionMessage({ version: 0 }),
      (tx) => setTransactionMessageFeePayerSigner(payer, tx),
      (tx) => svm.setTransactionMessageLifetimeUsingLatestBlockhash(tx),
      (tx) => appendTransactionMessageInstruction(instruction, tx),
      (tx) => signTransactionMessageWithSigners(tx),
    );

    const result = svm.sendTransaction(transaction);
    expect(result).toBeDefined();
    expect(result.constructor.name).toBe('TransactionMetadata');
  });
});
