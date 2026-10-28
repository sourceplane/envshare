import { putSecret } from "lib/store"
import { generateId } from "pkg/id"

// The share page's write: ciphertext and IV only — the browser encrypted
// them and kept the key (pkg/encryption.ts, app/share/page.tsx). The
// template's pages/api/v1/store.ts, which wrote one Redis hash; here the
// ciphertext goes to KV and the read limit to D1 (lib/store.ts).
export const dynamic = "force-dynamic"

type Body = { encrypted?: unknown; ttl?: unknown; reads?: unknown; iv?: unknown }

export async function POST(req: Request) {
  let body: Body
  try {
    body = (await req.json()) as Body
  } catch {
    return Response.json({ error: "The body must be JSON" }, { status: 400 })
  }
  const { encrypted, ttl, reads, iv } = body
  if (typeof encrypted !== "string" || encrypted.length === 0 || typeof iv !== "string" || iv.length === 0) {
    return Response.json({ error: "`encrypted` and `iv` are required" }, { status: 400 })
  }

  const id = generateId()
  await putSecret(
    id,
    { encrypted, iv },
    { ttl: typeof ttl === "number" ? ttl : null, reads: typeof reads === "number" ? reads : null },
  )
  return Response.json({ id })
}
