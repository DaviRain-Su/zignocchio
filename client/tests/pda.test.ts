import { PublicKey } from '@solana/web3.js';
import { findProgramAddress, createProgramAddress, toSeedBuffers } from '../src/pda';

describe('pda', () => {
  const programId = new PublicKey('11111111111111111111111111111111');

  describe('toSeedBuffers', () => {
    it('converts strings to UTF-8 buffers', () => {
      const seeds = toSeedBuffers(['escrow']);
      expect(seeds).toHaveLength(1);
      expect(seeds[0].toString('utf8')).toBe('escrow');
    });

    it('converts numbers to single-byte buffers', () => {
      const seeds = toSeedBuffers([255]);
      expect(seeds[0]).toEqual(Buffer.from([255]));
    });

    it('converts PublicKeys to 32-byte buffers', () => {
      const pubkey = PublicKey.unique();
      const seeds = toSeedBuffers([pubkey]);
      expect(seeds[0]).toEqual(pubkey.toBuffer());
      expect(seeds[0].length).toBe(32);
    });

    it('passes Buffers through unchanged', () => {
      const buf = Buffer.from([1, 2, 3]);
      const seeds = toSeedBuffers([buf]);
      expect(seeds[0]).toEqual(buf);
    });

    it('passes Uint8Arrays through unchanged', () => {
      const arr = new Uint8Array([4, 5, 6]);
      const seeds = toSeedBuffers([arr]);
      expect(seeds[0]).toEqual(Buffer.from(arr));
    });

    it('handles mixed seed types', () => {
      const pubkey = PublicKey.unique();
      const seeds = toSeedBuffers(['vault', pubkey, 42, Buffer.from([1])]);
      expect(seeds).toHaveLength(4);
      expect(seeds[0].toString('utf8')).toBe('vault');
      expect(seeds[1]).toEqual(pubkey.toBuffer());
      expect(seeds[2]).toEqual(Buffer.from([42]));
      expect(seeds[3]).toEqual(Buffer.from([1]));
    });
  });

  describe('findProgramAddress', () => {
    it('derives a PDA from string and pubkey seeds', () => {
      const maker = PublicKey.unique();
      const [pda, bump] = findProgramAddress(['escrow', maker], programId);

      expect(pda).toBeInstanceOf(PublicKey);
      expect(bump).toBeGreaterThanOrEqual(0);
      expect(bump).toBeLessThanOrEqual(255);

      // Verify consistency with raw web3.js
      const [expectedPda, expectedBump] = PublicKey.findProgramAddressSync(
        [Buffer.from('escrow'), maker.toBuffer()],
        programId
      );
      expect(pda.equals(expectedPda)).toBe(true);
      expect(bump).toBe(expectedBump);
    });

    it('derives a PDA with a bump seed', () => {
      const [pda, bump] = findProgramAddress(['counter'], programId);
      const verifiedPda = createProgramAddress(['counter', bump], programId);
      expect(pda.equals(verifiedPda)).toBe(true);
    });
  });

  describe('createProgramAddress', () => {
    it('creates a PDA from known seeds including bump', () => {
      const seed = 'vault';
      const owner = PublicKey.unique();
      const [pda, bump] = findProgramAddress([seed, owner], programId);

      const createdPda = createProgramAddress([seed, owner, bump], programId);
      expect(createdPda.equals(pda)).toBe(true);
    });
  });
});
