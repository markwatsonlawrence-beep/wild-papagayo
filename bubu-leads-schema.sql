-- Wild Papagayo -- Bubu leads table (Phase 1, web-only)
-- One row per conversation that reached WARM or HOT classification.
-- lead_id == conversation_id (1:1, Phase 1 keeps this simple -- no
-- cross-conversation dedup by email/phone yet).
CREATE TABLE IF NOT EXISTS leads (
  lead_id TEXT PRIMARY KEY,
  conversation_id TEXT NOT NULL,
  source TEXT NOT NULL DEFAULT 'website', -- website | whatsapp | facebook (only website used in Phase 1)
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  language TEXT,
  name TEXT,
  email TEXT,
  phone TEXT,
  hotel TEXT,
  travel_date TEXT,
  departure_date TEXT,
  adults INTEGER,
  children INTEGER,
  children_ages TEXT,
  interests TEXT,
  tour_interest TEXT,
  transfer_interest TEXT,
  origin TEXT,
  destination TEXT,
  recommended_products TEXT,
  lead_temperature TEXT NOT NULL, -- INFORMATION | WARM | HOT
  status TEXT NOT NULL DEFAULT 'NEW', -- NEW | ENGAGED | QUOTE_NEEDED | BOOKING_INTENT | HUMAN_FOLLOWUP | BOOKED | LOST
  human_handoff_required INTEGER NOT NULL DEFAULT 0, -- 0/1
  conversation_summary TEXT
);

CREATE INDEX IF NOT EXISTS idx_leads_temperature ON leads(lead_temperature);
CREATE INDEX IF NOT EXISTS idx_leads_updated_at ON leads(updated_at);
CREATE INDEX IF NOT EXISTS idx_leads_handoff ON leads(human_handoff_required);
