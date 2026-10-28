# envshare — risks and open questions

| ID | Risk | State | Notes |
|---|---|---|---|
| ES-A | `baseline-v1` is not yet proven live: the `d1-edit` mint, the two applies and their wiring publishes, the migrations against the real D1 API, the deploy and the workers.dev probes | OPEN | Proven offline in Baseline CI. One bootstrap from the tag closes it |
| ES-B | KV's real propagation: a link opened seconds after it was made, in another location, can answer "not found" once | OPEN | A read spends nothing on a KV miss, so a retry works; a live read from a second location measures it |
| ES-C | The two halves are not one transaction: a reader can fetch the ciphertext an instant before another reader's last read deletes it | ACCEPTED | The count still decides: that reader's UPDATE finds nothing and gets 404. No read beyond the limit is ever served |
| ES-D | The shortest TTL is 60 seconds | ACCEPTED | KV's floor; the share form's shortest choice is one minute, and the API reports the TTL stored |
| ES-E | The HTTP API stores what it is sent | ACCEPTED | As upstream: it is for already-encrypted secrets, and the README says so |
| ES-F | The API's default TTL is 43260 seconds (about 12 hours), though the template's README says 30 days | ACCEPTED | Kept as the template's code has it; the README here states the value |
| ES-G | Next.js 16 on OpenNext 1.20.11 | ACCEPTED | Pinned 16.3.8 (16.4.x fails on 1.20.11) |
