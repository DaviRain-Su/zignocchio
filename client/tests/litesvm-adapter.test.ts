import {
  startLitesvm,
  deployProgramToLitesvm,
  sendTransaction,
  getAccount,
  setAccount,
  airdrop,
} from '../src/litesvm';
import { TransactionInstruction, Keypair } from '@solana/web3.js';

describe('litesvm adapter integration', () => {
  it('deploys hello program and sends a transaction', async () => {
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

  it('deploys counter program, creates account, and increments', async () => {
    const { svm, payer } = startLitesvm();
    const programId = deployProgramToLitesvm(svm, { exampleName: 'counter' });

    // Create counter account
    const counter = Keypair.generate();
    setAccount(svm, counter.publicKey, {
      data: new Uint8Array(8),
      executable: false,
      lamports: 1_000_000n,
      owner: programId,
      space: 8n,
    });

    // Increment counter
    const ix = new TransactionInstruction({
      keys: [
        { pubkey: counter.publicKey, isSigner: false, isWritable: true },
      ],
      programId,
      data: Buffer.from([0]),
    });

    const result = await sendTransaction(svm, payer, [ix]);
    expect(result).toBeDefined();
    expect(result.constructor.name).toBe('TransactionMetadata');

    // Verify counter value
    const account = getAccount(svm, counter.publicKey);
    expect(account).toBeDefined();
    const value = Buffer.from(account!.data).readBigUInt64LE(0);
    expect(Number(value)).toBe(1);
  });

  it('airdrops and reads account balance', () => {
    const { svm, payer } = startLitesvm();
    const recipient = Keypair.generate();

    airdrop(svm, recipient.publicKey, 500_000_000n);

    const account = getAccount(svm, recipient.publicKey);
    expect(account).toBeDefined();
    expect(account!.lamports).toBe(500_000_000n);
  });
});
