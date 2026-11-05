ALTER TABLE leads ADD COLUMN departure_date TEXT;
CREATE INDEX IF NOT EXISTS idx_leads_handoff ON leads(human_handoff_required);
