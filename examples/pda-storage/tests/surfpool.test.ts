import {
  Connection,
  Keypair,
  PublicKey,
  Transaction,
  TransactionInstruction,
  sendAndConfirmTransaction,
  SystemProgram,
} from '@solana/web3.js';
import { execSync, spawn, ChildProcess } from 'child_process';
import * as fs from 'fs';
import * as path from 'path';

describe('PDA Storage Program', () => {
  let validator: ChildProcess;
  let connection: Connection;
  let programId: PublicKey;
  let payer: Keypair;

  const DISCRIMINATOR_INIT = 0;
  const DISCRIMINATOR_UPDATE = 1;
  const STORAGE_SEED = 'storage';

  beforeAll(async () => {
    try {
      execSync('pkill -f surfpool', { stdio: 'ignore' });
    } catch (e) {}
    await new Promise(resolve => setTimeout(resolve, 2000));

    console.log('Building pda-storage program...');
    execSync('zig build -Dexample=pda-storage', { stdio: 'inherit' });

    const programKeypair = Keypair.generate();
    programId = programKeypair.publicKey;
    console.log('Program ID:', programId.toBase58());

    const programKeypairPath = path.join(__dirname, '..', '..', 'test-program-keypair.json');
    fs.writeFileSync(programKeypairPath, JSON.stringify(Array.from(programKeypair.secretKey)));

    const programPath = path.join(__dirname, '..', '..', '..', 'zig-out', 'lib', 'pda-storage.so');
    if (!fs.existsSync(programPath)) {
      throw new Error(`Program not found at ${programPath}`);
    }

    console.log('Starting surfpool...');
    validator = spawn('surfpool', ['start', '--ci', '--no-tui', '--offline'], {
      detached: true,
      stdio: ['ignore', 'pipe', 'pipe'],
    });

    validator.stderr?.on('data', () => {});
    validator.on('error', (err) => {
      throw new Error(`Failed to start validator: ${err}`);
    });
    validator.unref();

    await new Promise(resolve => setTimeout(resolve, 5000));
    connection = new Connection('http://localhost:8899', 'confirmed');

    payer = Keypair.generate();
    const airdropSig = await connection.requestAirdrop(payer.publicKey, 2_000_000_000);
    await connection.confirmTransaction(airdropSig);
    console.log('Payer funded:', payer.publicKey.toBase58());

    const programData = fs.readFileSync(programPath);
    const deployRes = await fetch('http://127.0.0.1:8899', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        jsonrpc: '2.0',
        id: 1,
        method: 'surfnet_setAccount',
        params: [
          programId.toBase58(),
          {
            lamports: 1000000000,
            data: programData.toString('hex'),
            owner: 'BPFLoader2111111111111111111111111111111111',
            executable: true,
          },
        ],
      }),
    });
    const deployJson = await deployRes.json() as any;
    if (deployJson.error) {
      throw new Error(`surfnet_setAccount failed: ${deployJson.error.message}`);
    }
    console.log('Deploying program...');

    let programReady = false;
    for (let i = 0; i < 10; i++) {
      const programAccount = await connection.getAccountInfo(programId);
      if (programAccount && programAccount.executable) {
        programReady = true;
        console.log('Program deployed successfully!');
        break;
      }
      await new Promise(resolve => setTimeout(resolve, 500));
    }
    if (!programReady) {
      throw new Error('Program not executable');
    }
  }, 60000);

  afterAll(async () => {
    try {
      execSync('pkill -f surfpool');
    } catch (e) {}
    try {
      fs.unlinkSync(path.join(__dirname, '..', '..', 'test-program-keypair.json'));
    } catch (e) {}
  });

  function findStoragePDA(userPubkey: PublicKey): [PublicKey, number] {
    return PublicKey.findProgramAddressSync(
      [Buffer.from(STORAGE_SEED), userPubkey.toBuffer()],
      programId
    );
  }

  async function getStorageValue(storagePubkey: PublicKey): Promise<bigint> {
    const accountInfo = await connection.getAccountInfo(storagePubkey);
    if (!accountInfo) throw new Error('Storage account not found');
    return accountInfo.data.readBigUInt64LE(32);
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

    const instruction = createInitInstruction(payer.publicKey, storagePDA, user.publicKey, initialValue);
    const transaction = new Transaction().add(instruction);
    const signature = await sendAndConfirmTransaction(connection, transaction, [payer, user]);

    console.log('Init signature:', signature);

    const value = await getStorageValue(storagePDA);
    expect(value).toBe(BigInt(initialValue));

    const txDetails = await connection.getTransaction(signature, {
      commitment: 'confirmed',
      maxSupportedTransactionVersion: 0,
    });
    const logs = txDetails?.meta?.logMessages || [];
    console.log('Init logs:', logs);

    const hasInitLog = logs.some(log => log.includes('PDA Storage: initialized with value'));
    expect(hasInitLog).toBe(true);
  });

  it('should update storage value', async () => {
    const user = Keypair.generate();
    const [storagePDA] = findStoragePDA(user.publicKey);

    // Init
    const initIx = createInitInstruction(payer.publicKey, storagePDA, user.publicKey, 100);
    await sendAndConfirmTransaction(connection, new Transaction().add(initIx), [payer, user]);

    // Update
    const newValue = 999;
    const updateIx = createUpdateInstruction(storagePDA, user.publicKey, newValue);
    const signature = await sendAndConfirmTransaction(connection, new Transaction().add(updateIx), [payer, user]);

    console.log('Update signature:', signature);

    const value = await getStorageValue(storagePDA);
    expect(value).toBe(BigInt(newValue));

    const txDetails = await connection.getTransaction(signature, {
      commitment: 'confirmed',
      maxSupportedTransactionVersion: 0,
    });
    const logs = txDetails?.meta?.logMessages || [];
    const hasUpdateLog = logs.some(log => log.includes('PDA Storage: updated to value'));
    expect(hasUpdateLog).toBe(true);
  });

  it('should fail update by unauthorized user', async () => {
    const user = Keypair.generate();
    const attacker = Keypair.generate();
    const [storagePDA] = findStoragePDA(user.publicKey);

    // Init
    const initIx = createInitInstruction(payer.publicKey, storagePDA, user.publicKey, 100);
    await sendAndConfirmTransaction(connection, new Transaction().add(initIx), [payer, user]);

    // Attempt update with attacker
    const updateIx = createUpdateInstruction(storagePDA, attacker.publicKey, 999);
    const transaction = new Transaction().add(updateIx);

    await expect(
      sendAndConfirmTransaction(connection, transaction, [payer, attacker])
    ).rejects.toThrow();
  });

  it('should fail init with wrong PDA', async () => {
    const user = Keypair.generate();
    const wrongPDA = Keypair.generate().publicKey;
    const initialValue = 42;

    const instruction = createInitInstruction(payer.publicKey, wrongPDA, user.publicKey, initialValue);
    const transaction = new Transaction().add(instruction);

    await expect(
      sendAndConfirmTransaction(connection, transaction, [payer, user])
    ).rejects.toThrow();
  });
});
