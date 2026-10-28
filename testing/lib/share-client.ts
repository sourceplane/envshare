// The site's browser side, run outside a browser, for the e2e.
//
//   node share-client.mjs share <origin> <text> <ttl> <reads>
//   node share-client.mjs unseal <link>
//
// It is bundled (by the e2e, with esbuild) from the PRODUCT's own modules —
// apps/web/pkg/encryption.ts, encoding.ts, constants.ts and util/base58.ts,
// imported through the WEB alias — so what it sends is what the product's
// share and unseal pages send, step for step (app/share/page.tsx,
// app/unseal/page.tsx):
//
//   share:  encrypt(text) → POST /api/v1/store {ttl, reads, encrypted, iv}
//           → {id} → the link <origin>/unseal#<encodeCompositeKey(id, key)>
//   unseal: the link's fragment → decodeCompositeKey → GET /api/v1/load?id=
//           → decrypt(encrypted, key, iv)
//
// Each prints one JSON line. `share` also prints the key in the forms a leak
// would take (base58, hex, base64), so the e2e can look for them in
// everything the Worker was sent and everything it stored.
import { encrypt, decrypt } from "WEB/pkg/encryption"
import { encodeCompositeKey, decodeCompositeKey } from "WEB/pkg/encoding"
import { LATEST_KEY_VERSION } from "WEB/pkg/constants"
import { toBase58 } from "WEB/util/base58"

const [cmd, ...args] = process.argv.slice(2)
const hex = (b: Uint8Array) => Buffer.from(b).toString("hex")
const b64 = (b: Uint8Array) => Buffer.from(b).toString("base64")
const out = (o: unknown) => console.log(JSON.stringify(o))

async function share(origin: string, text: string, ttl: number, reads: number) {
  const { encrypted, iv, key } = await encrypt(text)
  const body = JSON.stringify({ ttl, reads, encrypted: toBase58(encrypted), iv: toBase58(iv) })
  const res = await fetch(new URL("/api/v1/store", origin), { method: "POST", body })
  if (!res.ok) return out({ status: res.status, body: await res.text() })
  const { id } = (await res.json()) as { id: string }
  const compositeKey = encodeCompositeKey(LATEST_KEY_VERSION, id, key)
  const link = new URL("/unseal", origin)
  link.hash = compositeKey
  out({
    status: res.status, id, link: link.toString(), compositeKey, encrypted: toBase58(encrypted),
    key: { b58: toBase58(key), hex: hex(key), b64: b64(key), b64url: Buffer.from(key).toString("base64url") },
  })
}

async function unseal(href: string) {
  const link = new URL(href)
  const { id, encryptionKey, version } = decodeCompositeKey(link.hash.slice(1))
  // The fragment stays here: only the id goes out, as the unseal page sends it.
  const res = await fetch(new URL(`/api/v1/load?id=${id}`, link.origin))
  if (!res.ok) return out({ status: res.status, body: await res.text() })
  const json = (await res.json()) as { iv: string; encrypted: string; remainingReads: number | null }
  const text = await decrypt(json.encrypted, encryptionKey, json.iv, version)
  out({ status: res.status, text, remainingReads: json.remainingReads })
}

if (cmd === "share") await share(args[0], args[1], Number(args[2]), Number(args[3]))
else if (cmd === "unseal") await unseal(args[0])
else {
  console.error("usage: share-client.mjs share <origin> <text> <ttl> <reads> | unseal <link>")
  process.exit(2)
}
