/**
 * IDL metadata fixture tests.
 *
 * Verifies multi-instruction ordering, account metadata flags, explicit args
 * policy, and raw AccountInfo IDL metadata for a framework fixture.
 */

import { execFileSync } from 'child_process';
import { createHash } from 'crypto';
import * as fs from 'fs';
import * as path from 'path';

const repoRoot = path.join(__dirname, '..', '..', '..');
const idlPath = path.join(repoRoot, 'zig-out', 'idl', 'idl-metadata.json');

function instructionDiscriminator(name: string): number[] {
  return Array.from(
    createHash('sha256').update(`global:${name}`).digest().subarray(0, 8)
  );
}

describe('IDL metadata fixture generation', () => {
  beforeAll(() => {
    execFileSync('zig', ['build', '-Dexample=idl-metadata', 'idl'], {
      cwd: repoRoot,
      stdio: 'inherit',
    });
  });

  it('emits public instructions exactly once in deterministic order', () => {
    const idl = JSON.parse(fs.readFileSync(idlPath, 'utf8'));

    expect(idl.name).toBe('idl-metadata');
    expect(idl.instructions.map((ix: { name: string }) => ix.name)).toEqual([
      'initialize_metadata',
      'refresh_metadata',
      'close_metadata',
    ]);
    expect(new Set(idl.instructions.map((ix: { name: string }) => ix.name)).size).toBe(3);

    for (const ix of idl.instructions) {
      expect(Object.keys(ix)).toEqual([
        'name',
        'discriminator',
        'accounts',
        'args',
      ]);
      expect(ix.discriminator).toEqual(instructionDiscriminator(ix.name));
      expect(ix.args).toEqual([]);
    }
  });

  it('preserves account declaration order and wrapper/raw flags', () => {
    const idl = JSON.parse(fs.readFileSync(idlPath, 'utf8'));
    const [initialize, refresh, close] = idl.instructions;

    expect(initialize.accounts.map((account: { name: string }) => account.name)).toEqual([
      'authority',
      'writable_vault',
      'readonly_config',
      'token_program',
      'raw_escape',
    ]);
    expect(initialize.accounts).toEqual([
      {
        name: 'authority',
        isSigner: true,
        isWritable: false,
        isProgram: false,
      },
      {
        name: 'writable_vault',
        isSigner: false,
        isWritable: true,
        isProgram: false,
      },
      {
        name: 'readonly_config',
        isSigner: false,
        isWritable: false,
        isProgram: false,
      },
      {
        name: 'token_program',
        isSigner: false,
        isWritable: false,
        isProgram: true,
      },
      {
        name: 'raw_escape',
        isSigner: false,
        isWritable: false,
        isProgram: false,
      },
    ]);

    expect(refresh.accounts).toEqual([]);
    expect(close.accounts).toEqual([]);
  });
});
