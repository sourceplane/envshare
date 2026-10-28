import { takeSecret } from "lib/store"
import { z } from "zod"

// The HTTP API's read (README → API): the stored secret and the reads left.
// The template's pages/api/v1/secret/[id].ts. Each call spends one read; the
// last one deletes the secret (lib/store.ts).
export const dynamic = "force-dynamic"

const responseValidation = z.union([
  z.object({
    data: z.object({
      remainingReads: z.number().int().optional(),
      secret: z.string(),
    }),
  }),
  z.object({
    error: z.string(),
  }),
])

export async function GET(_req: Request, { params }: { params: Promise<{ id: string }> }) {
  try {
    const { id } = await params
    if (!id) {
      return Response.json({ error: "Missing `id` parameter" }, { status: 400 })
    }
    const found = await takeSecret(id)
    if (!found || !("secret" in found.value)) {
      return Response.json({ error: "Not Found" }, { status: 404 })
    }
    return Response.json(
      responseValidation.parse({
        data: { secret: found.value.secret, remainingReads: found.remainingReads ?? undefined },
      }),
    )
  } catch (e) {
    console.error(e)
    return Response.json({ error: "Internal Server Error" }, { status: 500 })
  }
}
