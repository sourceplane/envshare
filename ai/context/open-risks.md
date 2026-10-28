# envshare — open risks

What is not yet proven or not yet decided. The full write-up of every risk,
including the accepted and resolved ones, is
`specs/epics/envshare/risks-and-open-questions.md`; this page lists only
what is still live, so it should be short.

| ID | Risk | State | What closes it |
|---|---|---|---|
| ES-A | Not yet proven live: the `d1-edit` mint, the two Terraform applies and their wiring publishes, the migrations against the real D1 API, the deploy and the workers.dev probes | OPEN | One bootstrap from a tag against a workspace whose Cloudflare token can mint D1 Edit |
| ES-B | KV's real propagation delay: a link opened within seconds of its creation, in another location, can answer "not found" once | OPEN | A live share read from a second location; the read spends nothing on a miss, so the link works on a retry |

Accepted, and worth knowing before you change them: ES-C (the count is
D1's, the ciphertext KV's: a reader can be served a document whose KV value
another reader's last read is deleting at that moment, but the count still
allows only the reads it was given), ES-D (the shortest TTL is 60 seconds,
KV's floor), ES-E (the HTTP API stores whatever it is sent, as the
template's did: a client that posts plain text gets plain text stored).
