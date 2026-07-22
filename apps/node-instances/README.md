# Node Instances

Each spawned node bot gets a subdirectory here, e.g. `node-instances/<nodeId>/wrangler.toml`,
generated from `apps/node-bot-template/wrangler.template.toml` by
`scripts/templating/generate-node-toml.ts`.

**Convention:** these generated configs ARE committed to git (not gitignored).
This gives us an audit trail of every node ever spawned and its Cloudflare
Worker name/bindings, and lets `wrangler deploy --config` target a specific
node deterministically from CI. Only the `wrangler.toml` is committed —
the actual BOT_TOKEN is pushed straight to Cloudflare as a Worker secret via
`wrangler secret put`, never written to a file in this repo.
