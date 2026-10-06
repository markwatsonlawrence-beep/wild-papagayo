-- Wild Papagayo -- Bubu leads table attribution fields (Phase 2)
-- Adds nullable attribution columns so a lead can be traced back to the
-- page that first brought the visitor in, the page where they converted,
-- the referrer, any UTM params, the tour they were viewing, and a
-- non-identifying session id. All columns are nullable with no default --
-- existing rows remain valid (all NULL), and code that doesn't yet send
-- these fields (an older cached script) keeps working unchanged.
--
-- NOT APPLIED as part of this task. Prepared for manual review and
-- execution (e.g. `wrangler d1 execute <DB> --file=bubu-leads-migration-002-attribution.sql`)
-- once the attribution.contract has been reviewed.
--
-- landing_page     -- first page path seen this session, e.g. /tours/celesteriver
-- conversion_page  -- page path at the moment this lead was created/updated
-- referrer_host    -- normalized referrer host, or "(direct)" / "(internal)"
-- utm_source/medium/campaign/content/term -- standard UTM params, if present
-- tour_slug        -- tour slug derived from page context (NOT the same as
--                     tour_interest, which is what the visitor said in chat)
-- session_id       -- random client-generated id, sessionStorage-scoped, non-PII
-- first_touch_at   -- ISO 8601 timestamp of first-touch capture

ALTER TABLE leads ADD COLUMN landing_page TEXT;
ALTER TABLE leads ADD COLUMN conversion_page TEXT;
ALTER TABLE leads ADD COLUMN referrer_host TEXT;
ALTER TABLE leads ADD COLUMN utm_source TEXT;
ALTER TABLE leads ADD COLUMN utm_medium TEXT;
ALTER TABLE leads ADD COLUMN utm_campaign TEXT;
ALTER TABLE leads ADD COLUMN utm_content TEXT;
ALTER TABLE leads ADD COLUMN utm_term TEXT;
ALTER TABLE leads ADD COLUMN tour_slug TEXT;
ALTER TABLE leads ADD COLUMN session_id TEXT;
ALTER TABLE leads ADD COLUMN first_touch_at TEXT;

CREATE INDEX IF NOT EXISTS idx_leads_tour_slug ON leads(tour_slug);
CREATE INDEX IF NOT EXISTS idx_leads_landing_page ON leads(landing_page);
