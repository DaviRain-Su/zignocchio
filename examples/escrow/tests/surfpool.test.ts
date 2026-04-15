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

describe('Escrow Program', () => {
  let validator: ChildProcess;
  let connection: Connection;
  let programId: PublicKey;
  let payer: Keypair;
  let maker: Keypair;
  let taker: Keypair;

  const MAKE = 0;
  const ACCEPT = 1;
  const REFUND = 2;

  beforeAll(async () => {
    try {
      execSync('pkill -f surfpool', { stdio: 'ignore' });
    } catch (e) {}
    await new Promise(resolve => setTimeout(resolve, 2000));

    console.log('Building escrow program...');
    execSync('zig build -Dexample=escrow', { stdio: 'inherit' });

    const programKeypair = Keypair.generate();
    programId = programKeypair.publicKey;
    console.log('Program ID:', programId.toBase58());

    const programKeypairPath = path.join(__dirname, '..', 'test-program-keypair.json');
    fs.writeFileSync(programKeypairPath, JSON.stringify(Array.from(programKeypair.secretKey)));

    const programPath = path.join(__dirname, '..', '..', '..', 'zig-out', 'lib', 'escrow.so');
    if (!fs.existsSync(programPath)) {
      throw new Error(`Program not found at ${programPath}`);
    }

    console.log('Starting surfpool...');
    validator = spawn('surfpool', [
      'start',
      '--ci',
      '--no-tui',
      '--offline',
    ], {
      detached: true,
      stdio: ['ignore', 'pipe', 'pipe'],
    });

    validator.stderr?.on('data', (_data) => {});
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

    maker = Keypair.generate();
    taker = Keypair.generate();
    for (const kp of [maker, taker]) {
      const sig = await connection.requestAirdrop(kp.publicKey, 1_000_000_000);
      await connection.confirmTransaction(sig);
    }
    console.log('Maker funded:', maker.publicKey.toBase58());
    console.log('Taker funded:', taker.publicKey.toBase58());
  }, 60000);

  afterAll(async () => {
    if (connection) {
      try {
        const conn = connection as any;
        if (conn._rpcWebSocket) {
          conn._rpcWebSocket.close();
        }
      } catch (e) {}
    }
    try {
      execSync('pkill -f surfpool');
    } catch (e) {}
    try {
      fs.unlinkSync(path.join(__dirname, '..', 'test-program-keypair.json'));
    } catch (e) {}
    await new Promise(resolve => setTimeout(resolve, 100));
  });

  function findEscrowPDA(makerPubkey: PublicKey): PublicKey {
    const [pda] = PublicKey.findProgramAddressSync(
      [Buffer.from('escrow'), makerPubkey.toBuffer()],
      programId
    );
    return pda;
  }

  async function getEscrowBalance(escrowPubkey: PublicKey): Promise<number> {
    const accountInfo = await connection.getAccountInfo(escrowPubkey);
    return accountInfo ? accountInfo.lamports : 0;
  }

  function createMakeInstruction(
    makerPubkey: PublicKey,
    escrow: PublicKey,
    takerPubkey: PublicKey,
    amount: number
  ): TransactionInstruction {
    const data = Buffer.alloc(41);
    data.writeUInt8(MAKE, 0);
    data.set(takerPubkey.toBuffer(), 1);
    data.writeBigUInt64LE(BigInt(amount), 33);

    return new TransactionInstruction({
      keys: [
        { pubkey: makerPubkey, isSigner: true, isWritable: true },
        { pubkey: escrow, isSigner: false, isWritable: true },
        { pubkey: SystemProgram.programId, isSigner: false, isWritable: false },
      ],
      programId,
      data,
    });
  }

  function createAcceptInstruction(
    takerPubkey: PublicKey,
    escrow: PublicKey,
    makerPubkey: PublicKey
  ): TransactionInstruction {
    const data = Buffer.from([ACCEPT]);
    return new TransactionInstruction({
      keys: [
        { pubkey: takerPubkey, isSigner: true, isWritable: true },
        { pubkey: escrow, isSigner: false, isWritable: true },
        { pubkey: makerPubkey, isSigner: false, isWritable: false },
      ],
      programId,
      data,
    });
  }

  function createRefundInstruction(
    makerPubkey: PublicKey,
    escrow: PublicKey
  ): TransactionInstruction {
    const data = Buffer.from([REFUND]);
    return new TransactionInstruction({
      keys: [
        { pubkey: makerPubkey, isSigner: true, isWritable: true },
        { pubkey: escrow, isSigner: false, isWritable: true },
      ],
      programId,
      data,
    });
  }

  describe('Make', () => {
    it('should create escrow and deposit lamports', async () => {
      const escrow = findEscrowPDA(maker.publicKey);
      const amount = 100_000_000; // 0.1 SOL

      const instruction = createMakeInstruction(
        maker.publicKey,
        escrow,
        taker.publicKey,
        amount
      );
      const transaction = new Transaction().add(instruction);

      const signature = await sendAndConfirmTransaction(connection, transaction, [maker]);
      console.log('Make signature:', signature);

      const escrowBalance = await getEscrowBalance(escrow);
      // Escrow should hold amount + rent exempt minimum
      expect(escrowBalance).toBeGreaterThanOrEqual(amount);

      const txDetails = await connection.getTransaction(signature, {
        commitment: 'confirmed',
        maxSupportedTransactionVersion: 0,
      });
      const logs = txDetails?.meta?.logMessages || [];
      console.log('Make logs:', logs);

      const hasMakeLog = logs.some(log =>
        log.includes('Make: Escrow initialized successfully')
      );
      expect(hasMakeLog).toBe(true);
    });

    it('should fail to make with zero amount', async () => {
      const escrow = findEscrowPDA(maker.publicKey);
      const instruction = createMakeInstruction(
        maker.publicKey,
        escrow,
        taker.publicKey,
        0
      );
      const transaction = new Transaction().add(instruction);
      await expect(
        sendAndConfirmTransaction(connection, transaction, [maker])
      ).rejects.toThrow();
    });
  });

  describe('Accept', () => {
    it('should allow taker to accept escrow', async () => {
      // Create fresh escrow for accept test
      const freshMaker = Keypair.generate();
      const freshTaker = Keypair.generate();
      for (const kp of [freshMaker, freshTaker]) {
        const sig = await connection.requestAirdrop(kp.publicKey, 1_000_000_000);
        await connection.confirmTransaction(sig);
      }

      const escrow = findEscrowPDA(freshMaker.publicKey);
      const amount = 100_000_000;

      // Make
      const makeIx = createMakeInstruction(
        freshMaker.publicKey,
        escrow,
        freshTaker.publicKey,
        amount
      );
      await sendAndConfirmTransaction(connection, new Transaction().add(makeIx), [freshMaker]);

      const escrowBalanceBefore = await getEscrowBalance(escrow);
      expect(escrowBalanceBefore).toBeGreaterThan(0);

      const takerBalanceBefore = await connection.getBalance(freshTaker.publicKey);

      // Accept
      const acceptIx = createAcceptInstruction(
        freshTaker.publicKey,
        escrow,
        freshMaker.publicKey
      );
      const signature = await sendAndConfirmTransaction(
        connection,
        new Transaction().add(acceptIx),
        [freshTaker]
      );
      console.log('Accept signature:', signature);

      const escrowBalanceAfter = await getEscrowBalance(escrow);
      expect(escrowBalanceAfter).toBe(0);

      const takerBalanceAfter = await connection.getBalance(freshTaker.publicKey);
      expect(takerBalanceAfter).toBeGreaterThan(takerBalanceBefore);

      const txDetails = await connection.getTransaction(signature, {
        commitment: 'confirmed',
        maxSupportedTransactionVersion: 0,
      });
      const logs = txDetails?.meta?.logMessages || [];
      console.log('Accept logs:', logs);

      const hasAcceptLog = logs.some(log =>
        log.includes('Accept: Lamports transferred successfully')
      );
      expect(hasAcceptLog).toBe(true);
    });

    it('should fail accept by unauthorized taker', async () => {
      const freshMaker = Keypair.generate();
      const freshTaker = Keypair.generate();
      const wrongTaker = Keypair.generate();
      for (const kp of [freshMaker, freshTaker, wrongTaker]) {
        const sig = await connection.requestAirdrop(kp.publicKey, 1_000_000_000);
        await connection.confirmTransaction(sig);
      }

      const escrow = findEscrowPDA(freshMaker.publicKey);
      const makeIx = createMakeInstruction(
        freshMaker.publicKey,
        escrow,
        freshTaker.publicKey,
        100_000_000
      );
      await sendAndConfirmTransaction(connection, new Transaction().add(makeIx), [freshMaker]);

      const acceptIx = createAcceptInstruction(
        wrongTaker.publicKey,
        escrow,
        freshMaker.publicKey
      );
      await expect(
        sendAndConfirmTransaction(connection, new Transaction().add(acceptIx), [wrongTaker])
      ).rejects.toThrow();
    });
  });

  describe('Refund', () => {
    it('should allow maker to refund escrow', async () => {
      const freshMaker = Keypair.generate();
      const freshTaker = Keypair.generate();
      for (const kp of [freshMaker, freshTaker]) {
        const sig = await connection.requestAirdrop(kp.publicKey, 1_000_000_000);
        await connection.confirmTransaction(sig);
      }

      const escrow = findEscrowPDA(freshMaker.publicKey);
      const amount = 100_000_000;

      // Make
      const makeIx = createMakeInstruction(
        freshMaker.publicKey,
        escrow,
        freshTaker.publicKey,
        amount
      );
      await sendAndConfirmTransaction(connection, new Transaction().add(makeIx), [freshMaker]);

      const escrowBalanceBefore = await getEscrowBalance(escrow);
      expect(escrowBalanceBefore).toBeGreaterThan(0);

      const makerBalanceBefore = await connection.getBalance(freshMaker.publicKey);

      // Refund
      const refundIx = createRefundInstruction(freshMaker.publicKey, escrow);
      const signature = await sendAndConfirmTransaction(
        connection,
        new Transaction().add(refundIx),
        [freshMaker]
      );
      console.log('Refund signature:', signature);

      const escrowBalanceAfter = await getEscrowBalance(escrow);
      expect(escrowBalanceAfter).toBe(0);

      const makerBalanceAfter = await connection.getBalance(freshMaker.publicKey);
      expect(makerBalanceAfter).toBeGreaterThan(makerBalanceBefore);

      const txDetails = await connection.getTransaction(signature, {
        commitment: 'confirmed',
        maxSupportedTransactionVersion: 0,
      });
      const logs = txDetails?.meta?.logMessages || [];
      console.log('Refund logs:', logs);

      const hasRefundLog = logs.some(log =>
        log.includes('Refund: Lamports refunded successfully')
      );
      expect(hasRefundLog).toBe(true);
    });
  });

  describe('Security', () => {
    it('should fail make with wrong signer', async () => {
      const wrongMaker = Keypair.generate();
      const sig = await connection.requestAirdrop(wrongMaker.publicKey, 1_000_000_000);
      await connection.confirmTransaction(sig);

      const escrow = findEscrowPDA(maker.publicKey);
      const instruction = createMakeInstruction(
        maker.publicKey,
        escrow,
        taker.publicKey,
        100_000_000
      );
      const transaction = new Transaction().add(instruction);
      await expect(
        sendAndConfirmTransaction(connection, transaction, [wrongMaker])
      ).rejects.toThrow();
    });

    it('should fail refund by non-maker', async () => {
      const freshMaker = Keypair.generate();
      const freshTaker = Keypair.generate();
      for (const kp of [freshMaker, freshTaker]) {
        const sig = await connection.requestAirdrop(kp.publicKey, 1_000_000_000);
        await connection.confirmTransaction(sig);
      }

      const escrow = findEscrowPDA(freshMaker.publicKey);
      const makeIx = createMakeInstruction(
        freshMaker.publicKey,
        escrow,
        freshTaker.publicKey,
        100_000_000
      );
      await sendAndConfirmTransaction(connection, new Transaction().add(makeIx), [freshMaker]);

      const refundIx = createRefundInstruction(freshMaker.publicKey, escrow);
      await expect(
        sendAndConfirmTransaction(connection, new Transaction().add(refundIx), [freshTaker])
      ).rejects.toThrow();
    });
  });
});
