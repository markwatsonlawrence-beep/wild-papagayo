// Wild Papagayo - Diagnostic Health Check (Cloudflare Pages Function)
// Temporary, Phase 0X only. No imports, no dependencies, no Anthropic.
// Purpose: prove Pages Functions are being compiled/registered at all,
// independent of the Anthropic SDK.
export async function onRequestGet() {
  return new Response(JSON.stringify({ status: 'ok' }), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });
}
