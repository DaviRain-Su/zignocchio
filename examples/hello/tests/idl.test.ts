/**
 * Hello IDL generation test.
 *
 * Verifies the host-side `zig build -Dexample=hello idl` artifact is parseable
 * and stable enough for client-facing schema checks.
 */

import { execFileSync } from 'child_process';
import { createHash } from 'crypto';
import * as fs from 'fs';
import * as path from 'path';

const repoRoot = path.join(__dirname, '..', '..', '..');
const idlPath = path.join(repoRoot, 'zig-out', 'idl', 'hello.json');

type JsonObject = Record<string, unknown>;

type ZignocchioIdlAccount = {
  name: string;
  isSigner: boolean;
  isWritable: boolean;
  isProgram: boolean;
};

type ZignocchioIdlInstruction = {
  name: string;
  discriminator: number[];
  accounts: ZignocchioIdlAccount[];
  args: never[];
};

type ZignocchioIdl = {
  version: string;
  name: string;
  metadata: {
    origin: string;
    schema: string;
  };
  instructions: ZignocchioIdlInstruction[];
};

const IDL_TOP_LEVEL_KEYS = ['version', 'name', 'metadata', 'instructions'] as const;
const IDL_METADATA_KEYS = ['origin', 'schema'] as const;
const IDL_INSTRUCTION_KEYS = ['name', 'discriminator', 'accounts', 'args'] as const;
const IDL_ACCOUNT_KEYS = ['name', 'isSigner', 'isWritable', 'isProgram'] as const;

function instructionDiscriminator(name: string): number[] {
  return Array.from(
    createHash('sha256').update(`global:${name}`).digest().subarray(0, 8)
  );
}

function assertPlainObject(value: unknown, pathName: string): asserts value is JsonObject {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) {
    throw new Error(`${pathName} must be an object`);
  }
}

function assertExactKeys(
  value: JsonObject,
  requiredKeys: readonly string[],
  pathName: string
): void {
  const actualKeys = Object.keys(value);

  for (const key of requiredKeys) {
    if (!Object.prototype.hasOwnProperty.call(value, key)) {
      throw new Error(`${pathName} missing required field "${key}"`);
    }
  }

  for (const key of actualKeys) {
    if (!requiredKeys.includes(key)) {
      throw new Error(`${pathName} has unexpected field "${key}"`);
    }
  }

  if (actualKeys.join('\0') !== requiredKeys.join('\0')) {
    throw new Error(`${pathName} fields must be ordered as ${requiredKeys.join(', ')}`);
  }
}

function assertString(value: unknown, pathName: string): asserts value is string {
  if (typeof value !== 'string') {
    throw new Error(`${pathName} must be a string`);
  }
}

function assertBoolean(value: unknown, pathName: string): asserts value is boolean {
  if (typeof value !== 'boolean') {
    throw new Error(`${pathName} must be a boolean`);
  }
}

function assertDiscriminator(value: unknown, pathName: string): asserts value is number[] {
  if (!Array.isArray(value)) {
    throw new Error(`${pathName} must be an array`);
  }
  if (value.length !== 8) {
    throw new Error(`${pathName} must contain exactly 8 bytes`);
  }
  value.forEach((byte, index) => {
    if (!Number.isInteger(byte) || byte < 0 || byte > 255) {
      throw new Error(`${pathName}[${index}] must be an integer byte`);
    }
  });
}

function validateZignocchioIdlSchema(value: unknown): asserts value is ZignocchioIdl {
  assertPlainObject(value, 'IDL');
  assertExactKeys(value, IDL_TOP_LEVEL_KEYS, 'IDL');
  assertString(value.version, 'IDL.version');
  assertString(value.name, 'IDL.name');

  assertPlainObject(value.metadata, 'IDL.metadata');
  assertExactKeys(value.metadata, IDL_METADATA_KEYS, 'IDL.metadata');
  assertString(value.metadata.origin, 'IDL.metadata.origin');
  assertString(value.metadata.schema, 'IDL.metadata.schema');
  if (value.metadata.origin !== 'zignocchio') {
    throw new Error('IDL.metadata.origin must be "zignocchio"');
  }
  if (value.metadata.schema !== 'zignocchio-idl-v0') {
    throw new Error('IDL.metadata.schema must be "zignocchio-idl-v0"');
  }

  if (!Array.isArray(value.instructions)) {
    throw new Error('IDL.instructions must be an array');
  }

  value.instructions.forEach((instruction, instructionIndex) => {
    const instructionPath = `IDL.instructions[${instructionIndex}]`;
    assertPlainObject(instruction, instructionPath);
    assertExactKeys(instruction, IDL_INSTRUCTION_KEYS, instructionPath);
    assertString(instruction.name, `${instructionPath}.name`);
    assertDiscriminator(instruction.discriminator, `${instructionPath}.discriminator`);

    if (!Array.isArray(instruction.accounts)) {
      throw new Error(`${instructionPath}.accounts must be an array`);
    }
    instruction.accounts.forEach((account, accountIndex) => {
      const accountPath = `${instructionPath}.accounts[${accountIndex}]`;
      assertPlainObject(account, accountPath);
      assertExactKeys(account, IDL_ACCOUNT_KEYS, accountPath);
      assertString(account.name, `${accountPath}.name`);
      assertBoolean(account.isSigner, `${accountPath}.isSigner`);
      assertBoolean(account.isWritable, `${accountPath}.isWritable`);
      assertBoolean(account.isProgram, `${accountPath}.isProgram`);
    });

    if (!Array.isArray(instruction.args)) {
      throw new Error(`${instructionPath}.args must be an array`);
    }
    if (instruction.args.length !== 0) {
      throw new Error(`${instructionPath}.args must be an explicit empty array`);
    }
  });
}

function readHelloIdl(): ZignocchioIdl {
  const raw = fs.readFileSync(idlPath, 'utf8');
  const idl: unknown = JSON.parse(raw);
  validateZignocchioIdlSchema(idl);
  return idl;
}

function helloIdlCopy(): JsonObject {
  return JSON.parse(JSON.stringify(readHelloIdl())) as JsonObject;
}

describe('hello IDL generation', () => {
  beforeAll(() => {
    execFileSync('zig', ['build', '-Dexample=hello', 'idl'], {
      cwd: repoRoot,
      stdio: 'inherit',
    });
  });

  it('writes parseable schema-shaped hello IDL', () => {
    expect(fs.existsSync(idlPath)).toBe(true);

    const raw = fs.readFileSync(idlPath, 'utf8');
    const idl: unknown = JSON.parse(raw);
    validateZignocchioIdlSchema(idl);

    expect(Object.keys(idl)).toEqual([
      'version',
      'name',
      'metadata',
      'instructions',
    ]);
    expect(idl.version).toBe('0.1.0');
    expect(idl.name).toBe('hello');
    expect(Object.keys(idl.metadata)).toEqual(['origin', 'schema']);
    expect(idl.metadata).toEqual({
      origin: 'zignocchio',
      schema: 'zignocchio-idl-v0',
    });
    expect(Array.isArray(idl.instructions)).toBe(true);
    expect(idl.instructions).toHaveLength(1);

    const [hello] = idl.instructions;
    expect(Object.keys(hello)).toEqual([
      'name',
      'discriminator',
      'accounts',
      'args',
    ]);
    expect(hello.name).toBe('hello');
    expect(hello.discriminator).toEqual(instructionDiscriminator('hello'));
    expect(hello.accounts).toEqual([]);
    expect(hello.args).toEqual([]);
  });

  it.each(IDL_TOP_LEVEL_KEYS)('rejects IDL copies missing top-level field "%s"', (field) => {
    const malformed = helloIdlCopy();
    delete malformed[field];

    expect(() => validateZignocchioIdlSchema(malformed)).toThrow(
      new RegExp(`IDL missing required field "${field}"`)
    );
  });

  it.each(IDL_INSTRUCTION_KEYS)(
    'rejects IDL copies missing instruction field "%s"',
    (field) => {
      const malformed = helloIdlCopy();
      const instructions = malformed.instructions as JsonObject[];
      delete instructions[0][field];

      expect(() => validateZignocchioIdlSchema(malformed)).toThrow(
        new RegExp(`IDL\\.instructions\\[0\\] missing required field "${field}"`)
      );
    }
  );

  it.each(IDL_ACCOUNT_KEYS)('rejects account metadata missing field "%s"', (field) => {
    const malformed = helloIdlCopy();
    const instructions = malformed.instructions as JsonObject[];
    instructions[0].accounts = [
      {
        name: 'authority',
        isSigner: true,
        isWritable: false,
        isProgram: false,
      },
    ];
    const accounts = instructions[0].accounts as JsonObject[];
    delete accounts[0][field];

    expect(() => validateZignocchioIdlSchema(malformed)).toThrow(
      new RegExp(
        `IDL\\.instructions\\[0\\]\\.accounts\\[0\\] missing required field "${field}"`
      )
    );
  });

  it('rejects malformed discriminator and args fields', () => {
    const malformedDiscriminator = helloIdlCopy();
    const discriminatorInstructions = malformedDiscriminator.instructions as JsonObject[];
    discriminatorInstructions[0].discriminator = [149, 118, 59];
    expect(() => validateZignocchioIdlSchema(malformedDiscriminator)).toThrow(
      /IDL\.instructions\[0\]\.discriminator must contain exactly 8 bytes/
    );

    const malformedArgs = helloIdlCopy();
    const argsInstructions = malformedArgs.instructions as JsonObject[];
    argsInstructions[0].args = [{ name: 'unexpected', type: 'u64' }];
    expect(() => validateZignocchioIdlSchema(malformedArgs)).toThrow(
      /IDL\.instructions\[0\]\.args must be an explicit empty array/
    );
  });

  it('uses frozen deterministic formatting for client snapshots', () => {
    const raw = fs.readFileSync(idlPath, 'utf8');

    expect(raw).toBe(`{
  "version": "0.1.0",
  "name": "hello",
  "metadata": {
    "origin": "zignocchio",
    "schema": "zignocchio-idl-v0"
  },
  "instructions": [
    {
      "name": "hello",
      "discriminator": [149, 118, 59, 220, 196, 127, 161, 179],
      "accounts": [],
      "args": []
    }
  ]
}
`);
  });
});
