/**
 * PDA-Storage program litesvm integration test.
 *
 * Tests PDA derivation, initialization via System Program CPI, and
 * authorized updates to a user-owned storage account.
 */

import {
  startLitesvm,
  deployProgramToLitesvm,
  sendTransaction,
  getAccount,
} from '../../../client/src/litesvm';
import {
  Keypair,
  PublicKey,
  TransactionInstruction,
  SystemProgram,
} from '@solana/web3.js';

describe('litesvm pda-storage', () => {
  let programId: PublicKey;
  let payer: Keypair;
  let svm: ReturnType<typeof startLitesvm>['svm'];

  const DISCRIMINATOR_INIT = 0;
  const DISCRIMINATOR_UPDATE = 1;
  const STORAGE_SEED = 'storage';

  beforeAll(() => {
    const ctx = startLitesvm();
    svm = ctx.svm;
    payer = ctx.payer;
    programId = deployProgramToLitesvm(svm, { exampleName: 'pda-storage' });
  });

  function findStoragePDA(userPubkey: PublicKey): [PublicKey, number] {
    return PublicKey.findProgramAddressSync(
      [Buffer.from(STORAGE_SEED), userPubkey.toBuffer()],
      programId
    );
  }

  function getStorageValue(storagePubkey: PublicKey): bigint {
    const account = getAccount(svm, storagePubkey);
    if (!account) throw new Error('Storage account not found');
    return Buffer.from(account.data).readBigUInt64LE(32);
  }

  function createInitInstruction(
    payerPubkey: PublicKey,
    storagePDA: PublicKey,
    userPubkey: PublicKey,
    initialValue: number
  ): TransactionInstruction {
    const data = Buffer.alloc(9);
    data.writeUInt8(DISCRIMINATOR_INIT, 0);
    data.writeBigUInt64LE(BigInt(initialValue), 1);

    return new TransactionInstruction({
      keys: [
        { pubkey: payerPubkey, isSigner: true, isWritable: true },
        { pubkey: storagePDA, isSigner: false, isWritable: true },
        { pubkey: userPubkey, isSigner: true, isWritable: false },
        { pubkey: SystemProgram.programId, isSigner: false, isWritable: false },
      ],
      programId,
      data,
    });
  }

  function createUpdateInstruction(
    storagePDA: PublicKey,
    userPubkey: PublicKey,
    newValue: number
  ): TransactionInstruction {
    const data = Buffer.alloc(9);
    data.writeUInt8(DISCRIMINATOR_UPDATE, 0);
    data.writeBigUInt64LE(BigInt(newValue), 1);

    return new TransactionInstruction({
      keys: [
        { pubkey: storagePDA, isSigner: false, isWritable: true },
        { pubkey: userPubkey, isSigner: true, isWritable: false },
      ],
      programId,
      data,
    });
  }

  it('should initialize storage PDA with initial value', async () => {
    const user = Keypair.generate();
    const [storagePDA] = findStoragePDA(user.publicKey);
    const initialValue = 42;

    const ix = createInitInstruction(payer.publicKey, storagePDA, user.publicKey, initialValue);
    const result = await sendTransaction(svm, payer, [ix], [user]);

    expect(result.constructor.name).toBe('TransactionMetadata');
    expect(Number(getStorageValue(storagePDA))).toBe(initialValue);
  });

  it('should update storage value', async () => {
    const user = Keypair.generate();
    const [storagePDA] = findStoragePDA(user.publicKey);

    // Init
    const initIx = createInitInstruction(payer.publicKey, storagePDA, user.publicKey, 100);
    await sendTransaction(svm, payer, [initIx], [user]);

    // Update
    const newValue = 999;
    const updateIx = createUpdateInstruction(storagePDA, user.publicKey, newValue);
    const result = await sendTransaction(svm, payer, [updateIx], [user]);

    expect(result.constructor.name).toBe('TransactionMetadata');
    expect(Number(getStorageValue(storagePDA))).toBe(newValue);
  });

  it('should fail update by unauthorized user', async () => {
    const user = Keypair.generate();
    const attacker = Keypair.generate();
    const [storagePDA] = findStoragePDA(user.publicKey);

    // Init
    const initIx = createInitInstruction(payer.publicKey, storagePDA, user.publicKey, 100);
    await sendTransaction(svm, payer, [initIx], [user]);

    // Attempt update with attacker
    const updateIx = createUpdateInstruction(storagePDA, attacker.publicKey, 999);
    await expect(sendTransaction(svm, payer, [updateIx], [attacker])).rejects.toThrow();
  });

  it('should fail init with wrong PDA', async () => {
    const user = Keypair.generate();
    const wrongPDA = Keypair.generate().publicKey;
    const initialValue = 42;

    const ix = createInitInstruction(payer.publicKey, wrongPDA, user.publicKey, initialValue);
    await expect(sendTransaction(svm, payer, [ix], [user])).rejects.toThrow();
  });
});
