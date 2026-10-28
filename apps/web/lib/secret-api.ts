import { z } from "zod"

// The HTTP API's request and response shapes (app/api/v1/secret/route.ts),
// as the template declared them in pages/api/v1/secret/index.ts. Here rather
// than in the route: Next 16's build refuses a route module that exports
// anything but its handlers and route config.
export const requestValidation = z.object({
  // ttl in seconds
  // defaults to 43260 (the template's value; its comment and README say 30 days)
  // not more than 30758400
  // 0 means no expiration
  ttl: z
    .string()
    .nullable()
    .transform((v) => (v ? parseInt(v, 10) : 43260))
    .refine((v) => v >= 0 && v <= 30758400, "ttl must be between 0 and 30758400 seconds"),

  // number of reads before deletion
  // defaults to null (no limit)
  reads: z
    .string()
    .nullable()
    .transform((v) => (v ? parseInt(v, 10) : null))
    .refine((v) => v === null || v > 0, "reads must be greater than 0"),
  secret: z.string().min(1),
})
export const responseValidation = z.union([
  z.object({
    data: z.object({
      id: z.string(),
      ttl: z.number().optional(),
      reads: z.number().optional(),
      expiresAt: z.string().optional(),
      url: z.string().url(),
    }),
  }),
  z.object({
    error: z.string(),
  }),
])

