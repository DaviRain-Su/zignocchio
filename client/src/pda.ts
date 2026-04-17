import { PublicKey } from '@solana/web3.js';

/**
 * A seed value for PDA derivation.
 *
 * Mirrors the Zig contract-side `[]const []const u8` seeds:
 * - `string` → encoded as UTF-8 bytes
 * - `Buffer` / `Uint8Array` → used directly
 * - `PublicKey` → 32-byte buffer (convenience wrapper)
 * - `number` (0-255) → single byte bump seed
 */
export type PdaSeed = string | Buffer | Uint8Array | PublicKey | number;

function seedToBuffer(seed: PdaSeed): Buffer {
  if (typeof seed === 'string') {
    return Buffer.from(seed, 'utf8');
  }
  if (typeof seed === 'number') {
    return Buffer.from([seed]);
  }
  if (seed instanceof PublicKey) {
    return seed.toBuffer();
  }
  return Buffer.from(seed);
}

/**
 * Convert an array of PdaSeed values into Buffer seeds.
 */
export function toSeedBuffers(seeds: PdaSeed[]): Buffer[] {
  return seeds.map(seedToBuffer);
}

/**
 * Find a valid Program Derived Address and its bump seed.
 *
 * Aligns with the Zig SDK's `findProgramAddress(seeds, program_id, &out_address, &out_bump)`.
 *
 * @param seeds - Array of seeds
 * @param programId - The program ID to derive the PDA under
 * @returns A tuple of `[pda, bump]`
 */
export function findProgramAddress(
  seeds: PdaSeed[],
  programId: PublicKey
): [PublicKey, number] {
  return PublicKey.findProgramAddressSync(toSeedBuffers(seeds), programId);
}

/**
 * Create a Program Derived Address from known seeds (no bump search).
 *
 * Aligns with the Zig SDK's `createProgramAddress(seeds, program_id, &out_address)`.
 *
 * @param seeds - Array of seeds (must include the bump seed if required)
 * @param programId - The program ID to derive the PDA under
 * @returns The derived PublicKey
 */
export function createProgramAddress(
  seeds: PdaSeed[],
  programId: PublicKey
): PublicKey {
  return PublicKey.createProgramAddressSync(toSeedBuffers(seeds), programId);
}
