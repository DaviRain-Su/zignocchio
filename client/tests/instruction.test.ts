import { PublicKey, Transaction } from '@solana/web3.js';
import { buildInstruction, buildTransaction } from '../src/instruction';

describe('instruction', () => {
  const programId = PublicKey.unique();

  it('should build instruction with defaults', () => {
    const ix = buildInstruction(programId, [
      { pubkey: PublicKey.unique() },
    ]);

    expect(ix.programId.equals(programId)).toBe(true);
    expect(ix.keys[0].isSigner).toBe(false);
    expect(ix.keys[0].isWritable).toBe(false);
    expect(ix.data.length).toBe(0);
  });

  it('should build instruction with explicit flags', () => {
    const ix = buildInstruction(
      programId,
      [
        { pubkey: PublicKey.unique(), isSigner: true, isWritable: true },
      ],
      Buffer.from([1, 2, 3])
    );

    expect(ix.keys[0].isSigner).toBe(true);
    expect(ix.keys[0].isWritable).toBe(true);
    expect(ix.data).toEqual(Buffer.from([1, 2, 3]));
  });

  it('should build transaction', () => {
    const ix1 = buildInstruction(programId, []);
    const ix2 = buildInstruction(programId, []);
    const tx = buildTransaction(ix1, ix2);

    expect(tx).toBeInstanceOf(Transaction);
    expect(tx.instructions.length).toBe(2);
  });
});
