import { describe, expect, it } from "vitest";
import { decodeCompositeKey, encodeCompositeKey } from "pkg/encoding";
import { decrypt, encrypt, generateKey } from "pkg/encryption";
import { generateId } from "pkg/id";
import { toBase58 } from "util/base58";

// The template's own tests (pkg/encoding.test.ts and pkg/encryption.test.ts,
// on jest), unchanged in what they assert: the browser's half of the site.
describe("composite key encoding", () => {
  it("encodes and decodes composite keys", async () => {
    for (let i = 0; i < 10000; i++) {
      const id = generateId();
      const key = new Uint8Array(await crypto.subtle.exportKey("raw", await generateKey()));

      const encoded = encodeCompositeKey(1, id, key);

      const decoded = decodeCompositeKey(encoded);
      expect(decoded.id).toEqual(id);
      expect(decoded.encryptionKey).toEqual(key);
    }
  }, 60_000);
});

describe("aes", () => {
  it("encrypts and decrypts correctly", async () => {
    for (let i = 0; i < 500; i++) {
      const buf = new Uint8Array(Math.ceil(Math.random() * 10 * i));
      crypto.getRandomValues(buf);

      const text = toBase58(buf);

      const { encrypted, key, iv } = await encrypt(text);

      const decrypted = await decrypt(toBase58(encrypted), key, toBase58(iv), 2);

      expect(decrypted).toEqual(text);
    }
  }, 30_000);
});

describe("the share link", () => {
  // The key travels in the link's fragment, which a browser never sends: the
  // server sees the id alone (app/unseal/page.tsx fetches /api/v1/load?id=).
  it("carries the id and the key together, and the id alone names the stored document", async () => {
    const { key } = await encrypt("DATABASE_URL=postgres://x");
    const id = generateId();
    const composite = encodeCompositeKey(2, id, key);
    const decoded = decodeCompositeKey(composite);
    expect(decoded).toEqual({ id, encryptionKey: key, version: 2 });
  });
});
