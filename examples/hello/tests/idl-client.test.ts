/**
 * IDL-driven hello client integration test.
 *
 * Loads the generated hello IDL, derives instruction data and account metas
 * from the IDL metadata, and invokes the framework discriminator path in
 * litesvm.
 */

import {
  startLitesvm,
  deployProgramToLitesvm,
  sendTransaction,
} from '../../../client/src/litesvm';
import { AccountMeta, PublicKey, TransactionInstruction } from '@solana/web3.js';
import { execFileSync } from 'child_process';
import * as fs from 'fs';
import * as path from 'path';

const repoRoot = path.join(__dirname, '..', '..', '..');
const idlPath = path.join(repoRoot, 'zig-out', 'idl', 'hello.json');

type IdlAccount = {
  name: string;
  isSigner: boolean;
  isWritable: boolean;
};

type IdlInstruction = {
  name: string;
  discriminator: number[];
  accounts: IdlAccount[];
  args: unknown[];
};

type ZignocchioIdl = {
  version: string;
  name: string;
  metadata: {
    origin: string;
    schema: string;
  };
  instructions: IdlInstruction[];
};

function loadHelloIdl(): ZignocchioIdl {
  return JSON.parse(fs.readFileSync(idlPath, 'utf8')) as ZignocchioIdl;
}

function instructionDataFromIdl(instruction: IdlInstruction): Buffer {
  if (instruction.discriminator.length !== 8) {
    throw new Error(
      `IDL instruction ${instruction.name} has ${instruction.discriminator.length} discriminator bytes`
    );
  }
  return Buffer.from(instruction.discriminator);
}

function accountMetasFromIdl(
  accounts: IdlAccount[],
  addressesByName: Record<string, PublicKey>
): AccountMeta[] {
  return accounts.map((account) => {
    const pubkey = addressesByName[account.name];
    if (!pubkey) {
      throw new Error(`missing client address for IDL account ${account.name}`);
    }
    return {
      pubkey,
      isSigner: account.isSigner,
      isWritable: account.isWritable,
    };
  });
}

describe('hello IDL-driven litesvm client', () => {
  beforeAll(() => {
    execFileSync('zig', ['build', '-Dexample=hello', 'idl'], {
      cwd: repoRoot,
      stdio: 'inherit',
    });
  });

  it('loads generated IDL and invokes hello with IDL-derived discriminator data', async () => {
    const idl = loadHelloIdl();
    expect(idl.name).toBe('hello');
    expect(idl.metadata.schema).toBe('zignocchio-idl-v0');

    const hello = idl.instructions.find((instruction) => instruction.name === 'hello');
    expect(hello).toBeDefined();
    if (!hello) {
      throw new Error('hello instruction missing from generated IDL');
    }
    expect(hello.args).toEqual([]);

    const { svm, payer } = startLitesvm();
    const programId = deployProgramToLitesvm(svm, { exampleName: idl.name });

    const ix = new TransactionInstruction({
      keys: accountMetasFromIdl(hello.accounts, {}),
      programId,
      data: instructionDataFromIdl(hello),
    });

    const result = await sendTransaction(svm, payer, [ix]);

    expect(result).toBeDefined();
    expect(result.constructor.name).toBe('TransactionMetadata');
  });
});
