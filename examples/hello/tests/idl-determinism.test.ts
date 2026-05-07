/**
 * IDL determinism and stale-artifact safety tests.
 */

import { execFileSync } from 'child_process';
import { createHash } from 'crypto';
import * as fs from 'fs';
import * as path from 'path';

const repoRoot = path.join(__dirname, '..', '..', '..');
const helloIdlPath = path.join(repoRoot, 'zig-out', 'idl', 'hello.json');
const metadataIdlPath = path.join(repoRoot, 'zig-out', 'idl', 'idl-metadata.json');
const unsupportedIdlPath = path.join(repoRoot, 'zig-out', 'idl', 'idl-unsupported-args.json');
const helloSoPath = path.join(repoRoot, 'zig-out', 'lib', 'hello.so');
const entrypointBcPath = path.join(repoRoot, 'entrypoint.bc');

function zigBuild(args: string[]): void {
  execFileSync('zig', ['build', ...args], {
    cwd: repoRoot,
    stdio: ['ignore', 'pipe', 'pipe'],
  });
}

function sha256(filePath: string): string {
  return createHash('sha256').update(fs.readFileSync(filePath)).digest('hex');
}

function artifactState(filePath: string): { hash: string; mtimeMs: number; size: number } {
  const stat = fs.statSync(filePath);
  return {
    hash: sha256(filePath),
    mtimeMs: stat.mtimeMs,
    size: stat.size,
  };
}

describe('IDL determinism and stale artifact behavior', () => {
  it('generates byte-identical hello IDL across repeated runs', () => {
    zigBuild(['-Dexample=hello', 'idl']);
    const first = fs.readFileSync(helloIdlPath);
    const firstHash = createHash('sha256').update(first).digest('hex');

    zigBuild(['-Dexample=hello', 'idl']);
    const second = fs.readFileSync(helloIdlPath);
    const secondHash = createHash('sha256').update(second).digest('hex');

    expect(second.equals(first)).toBe(true);
    expect(secondHash).toBe(firstHash);
  });

  it('removes stale artifacts when unsupported IDL declarations fail', () => {
    fs.mkdirSync(path.dirname(unsupportedIdlPath), { recursive: true });
    fs.writeFileSync(
      unsupportedIdlPath,
      '{"name":"stale-success","instructions":[]}\n',
      'utf8'
    );

    expect(() => zigBuild(['-Dexample=idl-unsupported-args', 'idl'])).toThrow(
      /framework IDL generation does not support instruction args yet/
    );

    expect(fs.existsSync(unsupportedIdlPath)).toBe(false);
  });

  it('keeps selected-example metadata isolated across sequential generation', () => {
    zigBuild(['-Dexample=hello', 'idl']);
    const hello = JSON.parse(fs.readFileSync(helloIdlPath, 'utf8'));
    expect(hello.name).toBe('hello');
    expect(hello.instructions.map((ix: { name: string }) => ix.name)).toEqual(['hello']);

    zigBuild(['-Dexample=idl-metadata', 'idl']);
    const metadata = JSON.parse(fs.readFileSync(metadataIdlPath, 'utf8'));
    expect(metadata.name).toBe('idl-metadata');
    expect(metadata.instructions.map((ix: { name: string }) => ix.name)).toEqual([
      'initialize_metadata',
      'refresh_metadata',
      'close_metadata',
    ]);
    expect(metadata.instructions.some((ix: { name: string }) => ix.name === 'hello')).toBe(false);

    const helloAfterMetadata = JSON.parse(fs.readFileSync(helloIdlPath, 'utf8'));
    expect(helloAfterMetadata.name).toBe('hello');
    expect(helloAfterMetadata.instructions.map((ix: { name: string }) => ix.name)).toEqual([
      'hello',
    ]);
  });

  it('does not rewrite BPF artifacts during IDL-only generation', () => {
    zigBuild(['-Dexample=hello']);
    const beforeSo = artifactState(helloSoPath);
    const beforeBitcode = artifactState(entrypointBcPath);

    zigBuild(['-Dexample=hello', 'idl']);

    expect(artifactState(helloSoPath)).toEqual(beforeSo);
    expect(artifactState(entrypointBcPath)).toEqual(beforeBitcode);
  });
});
