import { LiteSVM } from 'litesvm';
import {
  appendTransactionMessageInstruction,
  createTransactionMessage,
  createKeyPairSignerFromBytes,
  pipe,
  setTransactionMessageFeePayerSigner,
  signTransactionMessageWithSigners,
  addSignersToTransactionMessage,
  lamports,
  address,
  type Address,
} from '@solana/kit';
import {
  Keypair,
  PublicKey,
  TransactionInstruction,
} from '@solana/web3.js';
import { execSync } from 'child_process';
import * as path from 'path';
import * as fs from 'fs';

/**
 * Context object returned when starting a litesvm test environment.
 */
export interface LitesvmContext {
  svm: LiteSVM;
  payer: Keypair;
}

/**
 * Options for deploying a Zignocchio program to litesvm.
 */
export interface LitesvmDeployOptions {
  /** Name of the example to build and deploy (e.g. 'hello', 'counter') */
  exampleName: string;
  /** Optional explicit program ID; if omitted, a new keypair is generated */
  programId?: Keypair;
  /** Optional base path for the compiled .so file; defaults to zig-out/lib */
  soBasePath?: string;
  /** If true, skips running `zig build` and assumes the .so already exists */
  skipBuild?: boolean;
}

/**
 * Start an in-process litesvm instance and create a funded payer account.
 *
 * @returns A context object with the svm instance and a v1 Keypair payer
 */
export function startLitesvm(): LitesvmContext {
  const svm = new LiteSVM();
  const payer = Keypair.generate();
  const payerAddress = address(payer.publicKey.toBase58());
  svm.airdrop(payerAddress, lamports(BigInt(2_000_000_000)));
  return { svm, payer };
}

/**
 * Find the Zignocchio project root by looking for build.zig.
 */
function findProjectRoot(): string {
  let dir = __dirname;
  while (dir !== path.parse(dir).root) {
    if (fs.existsSync(path.join(dir, 'build.zig'))) {
      return dir;
    }
    dir = path.dirname(dir);
  }
  throw new Error('Could not find Zignocchio project root (no build.zig found)');
}

/**
 * Build and deploy a compiled Zignocchio sBPF program to litesvm.
 *
 * @param svm - An active LiteSVM instance
 * @param opts - Deployment options
 * @returns The program's v1 PublicKey
 */
export function deployProgramToLitesvm(
  svm: LiteSVM,
  opts: LitesvmDeployOptions
): PublicKey {
  const projectRoot = findProjectRoot();

  if (!opts.skipBuild) {
    execSync(`zig build -Dexample=${opts.exampleName}`, {
      stdio: 'inherit',
      cwd: projectRoot,
    });
  }

  const basePath = opts.soBasePath ?? path.join(projectRoot, 'zig-out', 'lib');
  const programPath = path.join(basePath, `${opts.exampleName}.so`);

  if (!fs.existsSync(programPath)) {
    throw new Error(`Program not found at ${programPath}`);
  }

  const programKeypair = opts.programId ?? Keypair.generate();
  const programAddress = address(programKeypair.publicKey.toBase58());
  svm.addProgramFromFile(programAddress, programPath);

  return programKeypair.publicKey;
}

/**
 * Convert a v1 TransactionInstruction into a litesvm-compatible instruction.
 *
 * Account role mapping:
 * - readonly, not signer  → 0
 * - writable, not signer  → 1
 * - readonly, signer      → 2
 * - writable, signer      → 3
 */
function toLitesvmInstruction(ix: TransactionInstruction) {
  const accounts = ix.keys.map((meta) => {
    const role = (meta.isSigner ? 2 : 0) + (meta.isWritable ? 1 : 0);
    return {
      address: address(meta.pubkey.toBase58()),
      role,
    };
  });

  return {
    programAddress: address(ix.programId.toBase58()),
    accounts,
    data: new Uint8Array(ix.data),
  };
}

/**
 * Convert a v1 Keypair into a kit KeyPairSigner for transaction signing.
 */
async function toKitSigner(keypair: Keypair) {
  return createKeyPairSignerFromBytes(keypair.secretKey);
}

/**
 * Send a v1-style transaction through litesvm.
 *
 * This adapter converts @solana/web3.js v1 TransactionInstructions into
 * @solana/kit transaction messages, signs them with the provided v1 Keypairs,
 * and submits them to litesvm.
 *
 * @param svm - An active LiteSVM instance
 * @param payer - The fee-paying account (v1 Keypair)
 * @param instructions - Array of v1 TransactionInstructions
 * @param signers - Additional signers beyond the payer
 * @returns The transaction result from litesvm
 */
export async function sendTransaction(
  svm: LiteSVM,
  payer: Keypair,
  instructions: TransactionInstruction[],
  signers: Keypair[] = []
): Promise<any> {
  const payerSigner = await toKitSigner(payer);
  const extraSigners: any[] = [];

  for (const signer of signers) {
    extraSigners.push(await toKitSigner(signer));
  }

  const litesvmInstructions = instructions.map(toLitesvmInstruction);

  // Build the transaction using pipe. Because @solana/kit tracks transaction
  // metadata through complex types, we use a mutable any-typed accumulator
  // to avoid type gymnastics when appending a dynamic number of instructions.
  let tx: any = pipe(
    createTransactionMessage({ version: 0 }),
    (t) => setTransactionMessageFeePayerSigner(payerSigner, t),
    (t) => svm.setTransactionMessageLifetimeUsingLatestBlockhash(t),
  );

  for (const ix of litesvmInstructions) {
    tx = appendTransactionMessageInstruction(ix, tx);
  }

  if (extraSigners.length > 0) {
    tx = addSignersToTransactionMessage(extraSigners, tx);
  }

  const transaction = await signTransactionMessageWithSigners(tx);

  const result = svm.sendTransaction(transaction);

  // litesvm returns FailedTransactionMetadata when the transaction fails on-chain.
  // Detect execution errors and throw so callers can use `rejects.toThrow()`.
  if (result.constructor.name === 'FailedTransactionMetadata') {
    const failed = result as any;
    const err = typeof failed.err === 'function' ? failed.err() : failed.err;
    throw new Error(`Transaction failed: ${String(err)}`);
  }

  return result;
}

/**
 * Get account info from litesvm using a v1 PublicKey.
 *
 * @param svm - An active LiteSVM instance
 * @param pubkey - The account to query
 * @returns The raw account data, or undefined if the account does not exist
 */
export function getAccount(
  svm: LiteSVM,
  pubkey: PublicKey
): { data: Uint8Array; executable: boolean; lamports: bigint; owner: Address } | undefined {
  const addr = address(pubkey.toBase58());
  const account = svm.getAccount(addr);
  if (!account || !account.exists) return undefined;

  return {
    data: account.data,
    executable: account.executable,
    lamports: account.lamports,
    owner: account.programAddress,
  };
}

/**
 * Set account data in litesvm using a v1 PublicKey.
 *
 * @param svm - An active LiteSVM instance
 * @param pubkey - The account address
 * @param account - Partial account data to set
 */
export function setAccount(
  svm: LiteSVM,
  pubkey: PublicKey,
  account: {
    data?: Uint8Array;
    executable?: boolean;
    lamports?: bigint;
    owner?: PublicKey;
    space?: bigint;
  }
): void {
  const addr = address(pubkey.toBase58());
  svm.setAccount({
    address: addr,
    data: account.data ?? new Uint8Array(0),
    executable: account.executable ?? false,
    lamports: account.lamports != null ? lamports(account.lamports) : lamports(0n),
    programAddress: account.owner ? address(account.owner.toBase58()) : address('11111111111111111111111111111111'),
    space: account.space ?? BigInt(account.data?.length ?? 0),
  });
}

/**
 * Airdrop lamports to an account.
 *
 * @param svm - An active LiteSVM instance
 * @param pubkey - The account to fund
 * @param amount - Amount in lamports
 */
export function airdrop(svm: LiteSVM, pubkey: PublicKey, amount: bigint): void {
  const addr = address(pubkey.toBase58());
  svm.airdrop(addr, lamports(amount));
}
