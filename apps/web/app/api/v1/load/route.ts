import { takeSecret } from "lib/store"

// The unseal page's read: the ciphertext and IV for `?id=`, and the reads
// left after this one (null when unlimited). The template's
// pages/api/v1/load.ts. Each call spends one read; the last one deletes the
// document (lib/store.ts).
export const dynamic = "force-dynamic"

export async function GET(req: Request) {
  const id = new URL(req.url).searchParams.get("id")
  if (!id) {
    return new Response("id param is missing", { status: 400 })
  }
  const found = await takeSecret(id)
  if (!found || !("encrypted" in found.value)) {
    return new Response("Not Found", { status: 404 })
  }
  return Response.json({ iv: found.value.iv, encrypted: found.value.encrypted, remainingReads: found.remainingReads })
}
