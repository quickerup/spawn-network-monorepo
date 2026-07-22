/**
 * generate-node-toml.ts
 *
 * Invoked by the spawn-node-bot workflow with a single CLI arg: token_ref
 * (a key pointing at the encrypted bot token in Cloudflare KV, NOT the
 * token itself — the raw token should never touch CI logs or git history).
 *
 * Responsibilities:
 *   1. Read + decrypt the bot token from KV using ENCRYPTION_KEY.
 *   2. Derive a stable, unique node ID (do not reuse token_ref directly
 *      if it isn't filesystem/URL-safe).
 *   3. Render apps/node-bot-template/wrangler.template.toml -> a concrete
 *      wrangler.toml written to apps/node-instances/<nodeId>/wrangler.toml.
 *   4. Write the BOT_TOKEN as a Wrangler secret (not into the toml file).
 *
 * This is a stub — wire up the real KV read + decryption + wrangler
 * secret put before relying on this in production.
 */

const [, , tokenRef] = process.argv;

if (!tokenRef) {
  console.error("Usage: generate-node-toml.ts <token_ref>");
  process.exit(1);
}

async function main() {
  const { CF_API_TOKEN, TOKEN_STORE_KV_ID, ENCRYPTION_KEY } = process.env;

  if (!CF_API_TOKEN || !TOKEN_STORE_KV_ID || !ENCRYPTION_KEY) {
    throw new Error(
      "Missing required env vars: CF_API_TOKEN, TOKEN_STORE_KV_ID, ENCRYPTION_KEY"
    );
  }

  // TODO: fetch encrypted token from KV via Cloudflare REST API
  // TODO: decrypt using ENCRYPTION_KEY
  // TODO: derive nodeId (e.g. slugified bot username from getMe, or a uuid)
  const nodeId = tokenRef.replace(/[^a-zA-Z0-9-_]/g, "").slice(0, 24);

  console.log(`Generating config for node: ${nodeId}`);

  // TODO: read apps/node-bot-template/wrangler.template.toml,
  // substitute ${UNIQUE_ID} -> nodeId, write to
  // apps/node-instances/${nodeId}/wrangler.toml

  // TODO: `wrangler secret put BOT_TOKEN --config <generated-toml-path>`
  // so the raw token lands only in Cloudflare, never in git.

  console.log("Done (stub — implement KV read, decrypt, and file writes).");
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
