import "./globals.css"
import { SITE_NAME, siteUrl } from "lib/site"
import type { Metadata } from "next"
import localFont from "next/font/local"
import Link from "next/link"
import { Header } from "./header"

// Inter, self-hosted: the variable font's latin subset, from
// @fontsource-variable/inter 5.2.8 — OFL-1.1, ./fonts/Inter-OFL.txt. The
// template fetched it from Google Fonts at build time (`@next/font/google`),
// which fails on GitHub's runners.
const inter = localFont({
  src: "./fonts/inter-latin-wght-normal.woff2",
  weight: "100 900",
  variable: "--font-inter",
  display: "swap",
})

// The template's app/head.tsx, as the App Router's metadata.
export function generateMetadata(): Metadata {
  const title = "Share Environment Variables Securely"
  const subtitle = SITE_NAME
  const og = new URL("/api/v1/og", siteUrl())
  og.searchParams.set("title", title)
  og.searchParams.set("subtitle", subtitle)
  const image = { url: og.toString(), width: 1200, height: 630 }

  return {
    metadataBase: new URL(siteUrl()),
    title: SITE_NAME,
    description: subtitle,
    keywords: ["envshare", "secure", "secrets", "share", "environment", "variables"],
    robots: "all",
    other: { "revisit-after": "7 days", language: "English", title },
    openGraph: { type: "website", url: siteUrl(), title, description: subtitle, images: [image] },
    twitter: { card: "summary_large_image", title, description: subtitle, images: [image.url] },
  }
}

export const viewport = { themeColor: "#000000", width: "device-width", initialScale: 1 }

export default function RootLayout({
  children,
}: {
  children: React.ReactNode
}) {
  return (
    <html lang="en" className={inter.variable}>
      <body className="relative min-h-screen bg-black bg-gradient-to-tr from-zinc-900/50 to-zinc-700/30">
        <Header />

        <main className=" min-h-[80vh] ">{children}</main>

        <footer className="bottom-0 border-t inset-2x-0 border-zinc-500/10">
          <div className="flex flex-col gap-1 px-6 py-12 mx-auto text-xs text-center text-zinc-700 max-w-7xl lg:px-8">
            <p>
              Based on{" "}
              <Link href="https://github.com/chronark/envshare" className="underline duration-150 hover:text-zinc-200">
                EnvShare
              </Link>{" "}
              by{" "}
              <Link href="https://twitter.com/chronark_" className="font-semibold duration-150 hover:text-zinc-200">
                @chronark_
              </Link>{" "}
              and{" "}
              <Link
                href="https://github.com/chronark/envshare/graphs/contributors"
                className="underline duration-150 hover:text-zinc-200"
              >
                many others{" "}
              </Link>
            </p>
            <p>
              {SITE_NAME} runs on{" "}
              <Link
                target="_blank"
                href="https://workers.cloudflare.com"
                className="underline duration-150 hover:text-zinc-200"
              >
                Cloudflare Workers
              </Link>{" "}
              and keeps only encrypted data, in Workers KV.
            </p>
          </div>
        </footer>
      </body>
    </html>
  )
}
