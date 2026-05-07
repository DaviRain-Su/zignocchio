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

function instructionDiscriminator(name: string): number[] {
  return Array.from(
    createHash('sha256').update(`global:${name}`).digest().subarray(0, 8)
  );
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
    const idl = JSON.parse(raw);

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
