import { getCloudflareContext } from "@opennextjs/cloudflare"
import { SITE_NAME } from "lib/site"
import { ImageResponse } from "next/og"

// The Open Graph card every page links (app/layout.tsx): the template's
// pages/api/v1/og.tsx on next/og. The template read its font with
// `fetch(new URL("…/Inter-SemiBold.ttf", import.meta.url))`; a Worker reads it
// from its own static assets (public/fonts, OFL-1.1). Without one — `next dev`
// has no ASSETS binding — the card falls back to next/og's built-in font.
export const dynamic = "force-dynamic"

async function inter(req: Request): Promise<ArrayBuffer | null> {
  try {
    const assets = getCloudflareContext().env.ASSETS
    if (!assets) return null
    const res = await assets.fetch(new URL("/fonts/Inter-SemiBold.ttf", req.url))
    return res.ok ? await res.arrayBuffer() : null
  } catch {
    return null
  }
}

export async function GET(req: Request) {
  try {
    const { searchParams } = new URL(req.url)
    // Redundant fallback alternate tagline
    const title = searchParams.get("title") ?? "Share Environment Variables Securely"
    const subtitle = searchParams.get("subtitle") ?? SITE_NAME

    const font = await inter(req)

    return new ImageResponse(
      <div
        style={{
          width: "1200px",
          height: "630px",
          display: "flex",
          flexDirection: "column",
          alignItems: "center",
          justifyContent: "center",
          textAlign: "center",
        }}
      >
        <div
          style={{
            display: "flex",
            width: "100%",
            height: "100%",
            backgroundColor: "black",
            backgroundImage: "linear-gradient(to top right, rgba(24,24,27,.5), rgba(63,63,70,.3))",
          }}
        >
          <div
            style={{
              display: "flex",
              flexDirection: "column",
              width: "100%",
              height: "100%",
              alignItems: "center",
              justifyContent: "center",
              textAlign: "center",
              fontSize: 30,
              letterSpacing: "-0.025em",
              color: "rgb(209, 213, 219)",
            }}
          >
            <h1
              style={{
                fontSize: 72,
                color: "transparent",
                paddingLeft: "12rem",
                paddingRight: "12rem",
                backgroundImage: "linear-gradient(to top, rgba(244, 244,  245, .5), rgba(255,255,255,1))",
                backgroundClip: "text",
              }}
            >
              {title}
            </h1>
            <p style={{ marginTop: 16, fontWeight: 700 }}>{subtitle}</p>
          </div>
        </div>
      </div>,
      {
        height: 630,
        width: 1200,
        ...(font ? { fonts: [{ name: "Inter", data: font, style: "normal" as const }] } : {}),
      },
    )
  } catch (e) {
    console.log(`${(e as Error).message}`)
    return new Response("Failed to generate the image", {
      status: 500,
    })
  }
}
