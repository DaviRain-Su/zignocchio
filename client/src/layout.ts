import { PublicKey } from '@solana/web3.js';

/**
 * Supported field types for account data layout.
 *
 * Maps to Zig `extern struct` primitives:
 * - `u8`  → 1 byte
 * - `u64` → 8 bytes, little-endian
 * - `pubkey` → 32 bytes
 */
export type FieldType = 'u8' | 'u64' | 'pubkey';

/**
 * Definition of a single field in a layout schema.
 */
export interface FieldDef {
  name: string;
  type: FieldType;
}

/**
 * Layout schema describing the serialization format of an account.
 *
 * Fields are processed in declaration order, matching Zig `extern struct`
 * layout on little-endian targets.
 */
export interface LayoutSchema {
  /** Optional discriminator byte written at offset 0 */
  discriminator?: number;
  /** Ordered field definitions */
  fields: FieldDef[];
}

function fieldSize(type: FieldType): number {
  switch (type) {
    case 'u8':
      return 1;
    case 'u64':
      return 8;
    case 'pubkey':
      return 32;
  }
}

/**
 * Compute the total byte size of a layout schema.
 */
export function layoutSize(schema: LayoutSchema): number {
  let size = 0;
  if (schema.discriminator !== undefined) {
    size += 1;
  }
  for (const field of schema.fields) {
    size += fieldSize(field.type);
  }
  return size;
}

/**
 * Serialize a record of values into a Buffer according to the layout schema.
 *
 * @param schema - Layout schema defining field order and types
 * @param values - Record of field names to values
 * @returns Serialized Buffer
 */
export function serializeLayout(
  schema: LayoutSchema,
  values: Record<string, any>
): Buffer {
  const size = layoutSize(schema);
  const buf = Buffer.alloc(size);
  let offset = 0;

  if (schema.discriminator !== undefined) {
    buf.writeUInt8(schema.discriminator, offset);
    offset += 1;
  }

  for (const field of schema.fields) {
    const value = values[field.name];
    switch (field.type) {
      case 'u8':
        buf.writeUInt8(value as number, offset);
        offset += 1;
        break;
      case 'u64':
        buf.writeBigUInt64LE(BigInt(value as bigint | number | string), offset);
        offset += 8;
        break;
      case 'pubkey':
        (value as PublicKey).toBuffer().copy(buf, offset);
        offset += 32;
        break;
    }
  }

  return buf;
}

/**
 * Deserialize a Buffer into a record of values according to the layout schema.
 *
 * @param schema - Layout schema defining field order and types
 * @param data - Buffer to deserialize
 * @returns Deserialized record
 */
export function deserializeLayout(
  schema: LayoutSchema,
  data: Buffer
): Record<string, any> {
  const result: Record<string, any> = {};
  let offset = 0;

  if (schema.discriminator !== undefined) {
    result['discriminator'] = data.readUInt8(offset);
    offset += 1;
  }

  for (const field of schema.fields) {
    switch (field.type) {
      case 'u8':
        result[field.name] = data.readUInt8(offset);
        offset += 1;
        break;
      case 'u64':
        result[field.name] = data.readBigUInt64LE(offset);
        offset += 8;
        break;
      case 'pubkey':
        result[field.name] = new PublicKey(data.slice(offset, offset + 32));
        offset += 32;
        break;
    }
  }

  return result;
}
