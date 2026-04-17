import { PublicKey } from '@solana/web3.js';
import { serializeLayout, deserializeLayout, layoutSize, LayoutSchema } from '../src/layout';

describe('layout', () => {
  describe('layoutSize', () => {
    it('counts discriminator byte when present', () => {
      const schema: LayoutSchema = {
        discriminator: 0x01,
        fields: [],
      };
      expect(layoutSize(schema)).toBe(1);
    });

    it('sums field sizes', () => {
      const schema: LayoutSchema = {
        discriminator: 0x01,
        fields: [
          { name: 'flag', type: 'u8' },
          { name: 'amount', type: 'u64' },
          { name: 'owner', type: 'pubkey' },
        ],
      };
      expect(layoutSize(schema)).toBe(1 + 1 + 8 + 32);
    });

    it('works without discriminator', () => {
      const schema: LayoutSchema = {
        fields: [{ name: 'amount', type: 'u64' }],
      };
      expect(layoutSize(schema)).toBe(8);
    });
  });

  describe('serializeLayout', () => {
    it('serializes u8, u64, and pubkey fields', () => {
      const owner = PublicKey.unique();
      const schema: LayoutSchema = {
        discriminator: 0xAB,
        fields: [
          { name: 'discriminator', type: 'u8' },
          { name: 'owner', type: 'pubkey' },
          { name: 'amount', type: 'u64' },
        ],
      };

      const buf = serializeLayout(schema, {
        discriminator: 0xAB,
        owner,
        amount: 100_000_000n,
      });

      expect(buf.length).toBe(layoutSize(schema));
      expect(buf.readUInt8(0)).toBe(0xAB); // schema discriminator
      expect(buf.readUInt8(1)).toBe(0xAB); // field discriminator
      expect(new PublicKey(buf.slice(2, 34)).equals(owner)).toBe(true);
      expect(buf.readBigUInt64LE(34)).toBe(100_000_000n);
    });

    it('accepts number for u64', () => {
      const schema: LayoutSchema = {
        fields: [{ name: 'amount', type: 'u64' }],
      };
      const buf = serializeLayout(schema, { amount: 42 });
      expect(buf.readBigUInt64LE(0)).toBe(42n);
    });

    it('accepts string for u64', () => {
      const schema: LayoutSchema = {
        fields: [{ name: 'amount', type: 'u64' }],
      };
      const buf = serializeLayout(schema, { amount: '123456789' });
      expect(buf.readBigUInt64LE(0)).toBe(123456789n);
    });
  });

  describe('deserializeLayout', () => {
    it('deserializes u8, u64, and pubkey fields', () => {
      const owner = PublicKey.unique();
      const schema: LayoutSchema = {
        discriminator: 0xAB,
        fields: [
          { name: 'discriminator', type: 'u8' },
          { name: 'owner', type: 'pubkey' },
          { name: 'amount', type: 'u64' },
        ],
      };

      const original = serializeLayout(schema, {
        discriminator: 0xAB,
        owner,
        amount: 100_000_000n,
      });

      const result = deserializeLayout(schema, original);
      expect(result.discriminator).toBe(0xAB);
      expect(result.owner.equals(owner)).toBe(true);
      expect(result.amount).toBe(100_000_000n);
    });

    it('round-trips without discriminator', () => {
      const schema: LayoutSchema = {
        fields: [
          { name: 'flag', type: 'u8' },
          { name: 'count', type: 'u64' },
        ],
      };
      const buf = serializeLayout(schema, { flag: 7, count: 999n });
      const result = deserializeLayout(schema, buf);
      expect(result.flag).toBe(7);
      expect(result.count).toBe(999n);
    });
  });

  describe('alignment with Zig extern struct', () => {
    it('produces the same byte layout as a tightly packed struct', () => {
      // In Zig:
      // const MyState = extern struct {
      //     discriminator: u8,
      //     value: u64,
      // };
      // Size = 9, offset(value) = 1
      const schema: LayoutSchema = {
        fields: [
          { name: 'discriminator', type: 'u8' },
          { name: 'value', type: 'u64' },
        ],
      };
      const buf = serializeLayout(schema, { discriminator: 0x01, value: 0x0102030405060708n });
      expect(buf.length).toBe(9);
      expect(buf.readUInt8(0)).toBe(0x01);
      // Little-endian byte order
      expect(buf.readBigUInt64LE(1)).toBe(0x0102030405060708n);
    });
  });
});
