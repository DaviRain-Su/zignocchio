import { PublicKey, Connection, Keypair } from '@solana/web3.js';
import { ChildProcess } from 'child_process';

/**
 * Re-export commonly used Solana web3.js types for convenience.
 */
export { PublicKey, Connection, Keypair, Transaction, TransactionInstruction } from '@solana/web3.js';
export { ChildProcess };

/**
 * Context object returned when starting a surfpool test validator.
 */
export interface SurfpoolContext {
  connection: Connection;
  validator: ChildProcess;
  payer: Keypair;
}

/**
 * Options for deploying a program to surfpool.
 */
export interface DeployOptions {
  programPath: string;
  programId?: Keypair;
}
