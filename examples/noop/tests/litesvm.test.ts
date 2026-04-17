/**
 * NOOP program litesvm isolation test.
 *
 * Executes a program with zero syscalls to isolate whether execution errors
 * come from entrypoint parsing or syscall ABI mismatches.
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

describe('litesvm noop isolation test', () => {
  const programPath = path.join(projectRoot, 'zig-out', 'lib', 'noop.so');

  beforeAll(() => {
    execSync('zig build -Dexample=noop', { stdio: 'inherit', cwd: projectRoot });
  });

  it('executes a noop program with zero syscalls', async () => {
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

    // If this passes without error, the issue is syscall-related.
    // If it still fails with error code 4, the issue is entrypoint/input-buffer related.
    expect(result).toBeDefined();
    expect(result.constructor.name).toBe('TransactionMetadata');
  });
});
