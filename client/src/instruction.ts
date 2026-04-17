import { PublicKey, Transaction, TransactionInstruction, AccountMeta } from '@solana/web3.js';

/**
 * Lightweight representation of an account meta for instruction building.
 */
export interface AccountMetaLike {
  pubkey: PublicKey;
  isSigner?: boolean;
  isWritable?: boolean;
}

/**
 * Build a `TransactionInstruction` from a program ID, account list, and optional data buffer.
 *
 * @param programId - The program to invoke
 * @param accounts - Ordered list of accounts with optional signer/writable flags
 * @param data - Instruction data buffer (optional)
 * @returns A configured TransactionInstruction
 */
export function buildInstruction(
  programId: PublicKey,
  accounts: AccountMetaLike[],
  data?: Buffer
): TransactionInstruction {
  const keys: AccountMeta[] = accounts.map(acc => ({
    pubkey: acc.pubkey,
    isSigner: acc.isSigner ?? false,
    isWritable: acc.isWritable ?? false,
  }));

  return new TransactionInstruction({
    keys,
    programId,
    data: data ?? Buffer.alloc(0),
  });
}

/**
 * Build a `Transaction` from one or more instructions.
 *
 * @param instructions - Instructions to add to the transaction
 * @returns A new Transaction
 */
export function buildTransaction(
  ...instructions: TransactionInstruction[]
): Transaction {
  const tx = new Transaction();
  for (const ix of instructions) {
    tx.add(ix);
  }
  return tx;
}
