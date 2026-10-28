import { env } from "lib/env"

// The deploy's smoke test and the deployment record's probe. Only the
// Worker can answer it: it reads the `secrets` table through its DB binding
// (so the database is bound and the migrations ran) and touches the SECRETS
// namespace through its KV binding. It reads no document and spends no read.
export const dynamic = "force-dynamic"

export async function GET() {
  const { DB, SECRETS } = env()
  const row = await DB.prepare("SELECT count(*) AS documents FROM secrets").first<{ documents: number }>()
  await SECRETS.get("health:probe")
  return Response.json({ ok: true, documents: row?.documents ?? 0 })
}
