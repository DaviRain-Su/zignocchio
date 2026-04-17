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

describe('Transfer SOL Program', () => {
  let validator: ChildProcess;
  let connection: Connection;
  let programId: PublicKey;
  let payer: Keypair;

  beforeAll(async () => {
    try {
      execSync('pkill -f surfpool', { stdio: 'ignore' });
    } catch (e) {}
    await new Promise(resolve => setTimeout(resolve, 2000));

    console.log('Building transfer-sol program...');
    execSync('zig build -Dexample=transfer-sol', { stdio: 'inherit' });

    const programKeypair = Keypair.generate();
    programId = programKeypair.publicKey;
    console.log('Program ID:', programId.toBase58());

    const programKeypairPath = path.join(__dirname, '..', '..', 'test-program-keypair.json');
    fs.writeFileSync(programKeypairPath, JSON.stringify(Array.from(programKeypair.secretKey)));

    const programPath = path.join(__dirname, '..', '..', '..', 'zig-out', 'lib', 'transfer-sol.so');
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

  function createTransferInstruction(
    fromPubkey: PublicKey,
    toPubkey: PublicKey,
    amount: number
  ): TransactionInstruction {
    const data = Buffer.alloc(8);
    data.writeBigUInt64LE(BigInt(amount), 0);
    return new TransactionInstruction({
      keys: [
        { pubkey: fromPubkey, isSigner: true, isWritable: true },
        { pubkey: toPubkey, isSigner: false, isWritable: true },
        { pubkey: SystemProgram.programId, isSigner: false, isWritable: false },
      ],
      programId,
      data,
    });
  }

  it('should transfer lamports from signer to recipient', async () => {
    const recipient = Keypair.generate();
    const amount = 100_000_000; // 0.1 SOL

    const fromBalanceBefore = await connection.getBalance(payer.publicKey);
    const toBalanceBefore = await connection.getBalance(recipient.publicKey);

    const instruction = createTransferInstruction(payer.publicKey, recipient.publicKey, amount);
    const transaction = new Transaction().add(instruction);
    const signature = await sendAndConfirmTransaction(connection, transaction, [payer]);

    console.log('Transfer signature:', signature);

    const fromBalanceAfter = await connection.getBalance(payer.publicKey);
    const toBalanceAfter = await connection.getBalance(recipient.publicKey);

    expect(toBalanceAfter - toBalanceBefore).toBe(amount);
    expect(fromBalanceAfter).toBeLessThan(fromBalanceBefore - amount); // account for fees

    const txDetails = await connection.getTransaction(signature, {
      commitment: 'confirmed',
      maxSupportedTransactionVersion: 0,
    });
    const logs = txDetails?.meta?.logMessages || [];
    console.log('Transfer logs:', logs);

    const hasSuccessLog = logs.some(log => log.includes('transfer-sol: success'));
    expect(hasSuccessLog).toBe(true);
  });

  it('should fail transfer with non-signer', async () => {
    const fakeSigner = Keypair.generate();
    const recipient = Keypair.generate();
    const amount = 100_000_000;

    // Airdrop to fakeSigner so it has lamports (but won't sign)
    const sig = await connection.requestAirdrop(fakeSigner.publicKey, 1_000_000_000);
    await connection.confirmTransaction(sig);

    const instruction = createTransferInstruction(fakeSigner.publicKey, recipient.publicKey, amount);
    const transaction = new Transaction().add(instruction);

    // Sign with payer instead of fakeSigner
    await expect(
      sendAndConfirmTransaction(connection, transaction, [payer])
    ).rejects.toThrow();
  });

  it('should fail transfer with zero amount', async () => {
    const recipient = Keypair.generate();
    const data = Buffer.alloc(8);
    data.writeBigUInt64LE(0n, 0);

    const instruction = new TransactionInstruction({
      keys: [
        { pubkey: payer.publicKey, isSigner: true, isWritable: true },
        { pubkey: recipient.publicKey, isSigner: false, isWritable: true },
        { pubkey: SystemProgram.programId, isSigner: false, isWritable: false },
      ],
      programId,
      data,
    });
    const transaction = new Transaction().add(instruction);

    await expect(
      sendAndConfirmTransaction(connection, transaction, [payer])
    ).rejects.toThrow();
  });
});
