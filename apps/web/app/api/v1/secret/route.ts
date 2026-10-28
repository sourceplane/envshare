import { requestValidation, responseValidation } from "lib/secret-api"
import { putSecret } from "lib/store"
import { generateId } from "pkg/id"

// The HTTP API's write (README → API): store an ALREADY-ENCRYPTED secret,
// sent as the body, with optional `envshare-ttl` (seconds) and
// `envshare-reads` headers. The template's pages/api/v1/secret/index.ts.
export const dynamic = "force-dynamic"

export async function POST(req: Request) {
  try {
    const parsed = requestValidation.safeParse({
      ttl: req.headers.get("envshare-ttl"),
      reads: req.headers.get("envshare-reads"),
      secret: await req.text(),
    })
    if (!parsed.success) {
      return Response.json({ error: JSON.parse(parsed.error.message) }, { status: 400 })
    }
    const { ttl, reads, secret } = parsed.data

    const id = generateId()
    // A TTL under KV's 60-second floor is raised to it; the response says
    // which TTL the secret was stored with.
    const stored = await putSecret(id, { secret }, { ttl, reads })

    const url = new URL(req.url)
    url.pathname = `/api/v1/secret/${id}`
    url.search = ""

    return Response.json(
      responseValidation.parse({
        data: {
          id,
          ttl: stored.ttl ?? undefined,
          reads: stored.reads ?? undefined,
          expiresAt: stored.expiresAt === null ? undefined : new Date(stored.expiresAt).toISOString(),
          url: url.toString(),
        },
      }),
    )
  } catch (e) {
    console.error(e)
    return Response.json({ error: "Internal Server Error" }, { status: 500 })
  }
}
