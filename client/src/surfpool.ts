import { Connection, Keypair, PublicKey } from '@solana/web3.js';
import { spawn, execSync, ChildProcess } from 'child_process';
import * as fs from 'fs';
import * as path from 'path';
import { SurfpoolContext, DeployOptions } from './types';

const SURFPOOL_PORT = 8899;
const SURFPOOL_RPC_URL = `http://127.0.0.1:${SURFPOOL_PORT}`;

function sleep(ms: number): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, ms));
}

function surfpoolListenerPids(): number[] {
  try {
    const output = execSync(`lsof -tiTCP:${SURFPOOL_PORT} -sTCP:LISTEN -P -n`, {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    });
    return output
      .trim()
      .split(/\s+/)
      .filter(Boolean)
      .map((pid) => Number(pid))
      .filter((pid) => Number.isInteger(pid) && pid > 0);
  } catch (_error) {
    return [];
  }
}

function assertSurfpoolPortFree(): void {
  const listeners = surfpoolListenerPids();
  if (listeners.length > 0) {
    throw new Error(
      `port ${SURFPOOL_PORT} already has listener PID(s): ${listeners.join(', ')}`
    );
  }
}

/**
 * Start a surfpool test validator in CI mode.
 *
 * Requires the mission-owned surfpool port to be free, starts a new tracked
 * process group, then waits for the RPC endpoint to become available.
 *
 * @returns A context object with connection, validator process, and funded payer keypair
 */
export async function startSurfpool(): Promise<SurfpoolContext> {
  assertSurfpoolPortFree();

  const validator = spawn('surfpool', [
    'start',
    '--ci',
    '--no-tui',
    '--offline',
  ], {
    detached: true,
    stdio: ['ignore', 'pipe', 'pipe'],
  });

  validator.stderr?.on('data', () => {
    // Suppress validator stderr
  });

  validator.on('error', (err) => {
    throw new Error(`Failed to start validator: ${err}`);
  });

  validator.unref();

  // Wait for validator to be ready.
  await sleep(5000);

  const connection = new Connection(SURFPOOL_RPC_URL, 'confirmed');

  // Create and fund a payer account
  const payer = Keypair.generate();
  const airdropSig = await connection.requestAirdrop(payer.publicKey, 2_000_000_000);
  await connection.confirmTransaction(airdropSig);

  return { connection, validator, payer };
}

/**
 * Deploy a compiled sBPF program to surfpool using the `surfnet_setAccount` cheatcode.
 *
 * This bypasses the loader and writes the program bytes directly to an executable account.
 *
 * @param connection - An active Connection to the surfpool RPC
 * @param opts - Deployment options
 * @returns The program's PublicKey
 */
export async function deployProgram(
  connection: Connection,
  opts: DeployOptions
): Promise<PublicKey> {
  if (!fs.existsSync(opts.programPath)) {
    throw new Error(`Program not found at ${opts.programPath}`);
  }

  const programKeypair = opts.programId ?? Keypair.generate();
  const programId = programKeypair.publicKey;
  const programData = fs.readFileSync(opts.programPath);

  // Write keypair to temporary file for external tools that may need it
  const programKeypairPath = path.join(process.cwd(), 'test-program-keypair.json');
  fs.writeFileSync(
    programKeypairPath,
    JSON.stringify(Array.from(programKeypair.secretKey))
  );

  const deployRes = await fetch(SURFPOOL_RPC_URL, {
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

  const deployJson = (await deployRes.json()) as any;
  if (deployJson.error) {
    throw new Error(`surfnet_setAccount failed: ${deployJson.error.message}`);
  }

  // Poll until the account is marked executable
  for (let i = 0; i < 20; i++) {
    const account = await connection.getAccountInfo(programId);
    if (account && account.executable) {
      return programId;
    }
    await new Promise(resolve => setTimeout(resolve, 500));
  }

  throw new Error('Program deployment timed out: account not executable');
}

/**
 * Stop a running surfpool validator and clean up temporary files.
 *
 * @param ctx - The surfpool context returned by `startSurfpool`
 */
export async function stopSurfpool(ctx: SurfpoolContext): Promise<void> {
  if (ctx.validator?.pid) {
    try {
      process.kill(-ctx.validator.pid, 'SIGTERM');
    } catch (_groupError) {
      try {
        ctx.validator.kill('SIGTERM');
      } catch (_childError) {
        // Ignore if the process has already exited.
      }
    }

    await sleep(1000);

    for (const pid of surfpoolListenerPids()) {
      try {
        process.kill(pid, 'SIGKILL');
      } catch (_error) {
        // Ignore if the listener exited between lsof and kill.
      }
    }
  }

  try {
    fs.unlinkSync(path.join(process.cwd(), 'test-program-keypair.json'));
  } catch (e) {
    // Ignore
  }

  // Give the OS a moment to release the port
  await sleep(500);

  const leakedListeners = surfpoolListenerPids();
  if (leakedListeners.length > 0) {
    throw new Error(
      `port ${SURFPOOL_PORT} still has listener PID(s): ${leakedListeners.join(', ')}`
    );
  }
}
