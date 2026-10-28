import { readFileSync } from "node:fs";
import * as path from "node:path";
import { afterEach, describe, expect, it } from "vitest";

const web = (f: string) => readFileSync(path.resolve(__dirname, "../../../apps/web", f), "utf8");

describe("site identity (apps/web/lib/site.ts)", () => {
  const saved = process.env.NEXT_PUBLIC_SITE_URL;
  afterEach(() => {
    if (saved === undefined) delete process.env.NEXT_PUBLIC_SITE_URL;
    else process.env.NEXT_PUBLIC_SITE_URL = saved;
  });

  // The rename's seam: one literal line each, whatever the product is called.
  it("declares SITE_NAME and SOURCE_URL as one literal line each", async () => {
    const { SITE_NAME, SOURCE_URL } = await import("lib/site");
    const name = /^export const SITE_NAME = (".*")$/m.exec(web("lib/site.ts"));
    expect(name, "SITE_NAME line").not.toBeNull();
    expect(JSON.parse(name![1]!)).toBe(SITE_NAME);
    expect(SITE_NAME.trim()).not.toBe("");
    expect(web("lib/site.ts")).toMatch(/^export const SOURCE_URL = "https:\/\/github\.com\/[A-Za-z0-9-]+\/[a-z0-9-]+"$/m);
    expect(SOURCE_URL).toMatch(/^https:\/\/github\.com\/[A-Za-z0-9-]+\/[a-z0-9-]+$/);
  });

  it("builds on the environment's origin, without a trailing slash", async () => {
    const { siteUrl } = await import("lib/site");
    process.env.NEXT_PUBLIC_SITE_URL = "https://secrets.example.com/";
    expect(siteUrl()).toBe("https://secrets.example.com");
    delete process.env.NEXT_PUBLIC_SITE_URL;
    expect(siteUrl()).toBe("http://localhost:3000");
  });
});

describe("the site's name and source link reach the pages", () => {
  it("names the site in the title, the header, the home page, the deploy page and the footer", () => {
    expect(web("app/layout.tsx")).toContain("title: SITE_NAME");
    expect(web("app/layout.tsx")).toContain("{SITE_NAME} runs on");
    expect(web("app/header.tsx")).toContain("{SITE_NAME}");
    expect(web("app/page.tsx")).toContain("{SITE_NAME} is Open Source on");
    expect(web("app/deploy/page.tsx")).toContain("Deploy {SITE_NAME} for Free");
    expect(web("app/api/v1/og/route.tsx")).toContain('searchParams.get("subtitle") ?? SITE_NAME');
  });

  it("links the site's own repository from the header, the home page and the deploy page", () => {
    expect(web("app/header.tsx")).toContain("href: SOURCE_URL");
    expect(web("app/page.tsx")).toContain("href={SOURCE_URL}");
    expect(web("app/deploy/page.tsx")).toContain("href={SOURCE_URL}");
  });

  // The template's own name appears in code only as the credit to it.
  it("spells the template's name only in the credit to it", () => {
    for (const f of ["app/layout.tsx", "app/header.tsx", "app/page.tsx", "app/deploy/page.tsx", "app/share/page.tsx", "app/unseal/page.tsx"]) {
      const lines = web(f).split("\n").filter((l) => l.includes("EnvShare"));
      for (const l of lines) expect(`${f}: ${l.trim()}`).toMatch(/^app\/layout\.tsx: EnvShare$/);
    }
  });
});
