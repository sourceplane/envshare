import { metrics } from "lib/store"

// The site's two counters, from D1 (lib/store.ts) — the template read them
// from Redis. The template also showed its own repository's GitHub star
// count, fetched from GitHub's API on every render; that number is not this
// site's, and an unauthenticated call from a shared Worker IP is quickly
// rate-limited, so it is not carried.
export const Stats = async () => {
  const { reads, writes } = await metrics()

  const stats = [
    {
      label: "Documents Encrypted",
      value: writes,
    },
    {
      label: "Documents Decrypted",
      value: reads,
    },
  ] satisfies { label: string; value: number }[]

  return (
    <section className="container mx-auto">
      <ul className="grid grid-cols-1 gap-4 sm:grid-cols-2 ">
        {stats.map(({ label, value }) => (
          <li
            key={label}
            className="flex items-center justify-between gap-2 px-4 py-3 overflow-hidden rounded m sm:flex-col"
          >
            <dd className="text-2xl font-bold tracking-tight text-center sm:text-5xl text-zinc-200">
              {Intl.NumberFormat("en-US", { notation: "compact" }).format(value)}
            </dd>
            <dt className="leading-6 text-center text-zinc-500">{label}</dt>
          </li>
        ))}
      </ul>
    </section>
  )
}
