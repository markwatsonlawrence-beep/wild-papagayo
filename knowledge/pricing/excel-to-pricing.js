// Wild Papagayo -- Excel pricing matrix -> tour-pricing.json
//
// The Excel file (knowledge/pricing/Matriz_Cotizador_Wild_Papagayo_Catalogo_Completo.xlsx)
// is the commercial source of truth, maintained by the business team. This
// script is the ONLY thing allowed to produce tour-pricing.json -- that file
// is a generated artifact and must never be hand-edited.
//
// The browser never reads the .xlsx directly; only this Node script does,
// offline, at conversion time. knowledge/pricing/ is excluded from every
// deploy (see deploy-package.ps1 $excludeDirs), so the Excel itself is never
// publicly reachable.
//
// Usage:
//   node knowledge/pricing/excel-to-pricing.js                    (full catalogue, strict, writes tour-pricing.json)
//   node knowledge/pricing/excel-to-pricing.js --tour=<slug>       (pilot mode -- see below)
//   node knowledge/pricing/excel-to-pricing.js --dry-run           (runs every validation, writes nothing)
//   node knowledge/pricing/excel-to-pricing.js --tour=<slug> --dry-run  (pilot + dry-run combined)
//
// Pilot mode (--tour=<slug>): still runs every validation rule over the
// WHOLE spreadsheet (a corrupt row anywhere still fails the run), but a row
// that can't be mapped to a known tour slug is only a hard error if that
// row's tour IS the requested pilot tour, or if no --tour filter was given
// at all (full-catalogue mode). Unmapped rows for OTHER tours are reported
// as warnings so a single pilot tour can be converted without first fixing
// every alias in the catalogue. tour-pricing.json, when --tour is used,
// contains only the zones/hotels data plus the requested tour(s) -- never a
// partial/guessed version of an unrelated tour.
//
// Never invents, substitutes, or rounds a price. Any row with an empty or
// invalid price cell is carried through as "no price for this cell" -- the
// runtime estimator turns that into "Custom Quote Required", never $0/NaN.
//
// Mapping keys: the "Tour Slug" and "Option ID" columns are the PRIMARY,
// authoritative mapping keys -- production mapping never depends on visible
// names once a row has them. An explicit Tour Slug that doesn't match a
// known tour is always a hard error. Rows without a Tour Slug fall back to
// legacy name/alias/URL matching (see resolveBySlugUrlOrName below), but
// that fallback always logs a warning, even on success, so migration gaps
// stay visible until every row is on the explicit columns.
//
// tour-pricing.json is PUBLIC (fetched client-side, served over HTTPS with
// no auth). It must only ever contain the public-facing sale price and the
// public per-zone surcharge shown to a customer -- never supplier rates,
// internal cost, margin, commission, or internal transport cost. Do not add
// a field here that isn't something Wild Papagayo is comfortable showing to
// any website visitor.
//
// "Estimator Status" (ACTIVE / INACTIVE / MANUAL QUOTE) is authoritative and
// never inferred from whether a knowledge/tours/*.json file exists. A row in
// scope for the current run (its own pilot tour, or any row in a
// full-catalogue run) MUST have an explicit status -- blank is a hard error,
// not a silent default. INACTIVE rows are excluded from tour-pricing.json
// entirely. MANUAL QUOTE rows are included but the frontend must always show
// Custom Quote Required for them regardless of any numeric price present.
//
// "Zone Adjustment Applies" (YES / NO / blank) disambiguates "no adjustment
// needed, base price applies to all listed hotels" (NO) from "adjustment not
// yet confirmed, treat as Custom Quote Required" (blank/unconfirmed) -- a
// blank Zone A/B/C cell no longer automatically means "unknown."

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const XLSX = require('xlsx');

const ROOT = path.join(__dirname, '..', '..'); // wild-papagayo/
const EXCEL_PATH = path.join(__dirname, 'Matriz_Cotizador_Wild_Papagayo_Catalogo_Completo.xlsx');
const TOURS_DIR = path.join(ROOT, 'knowledge', 'tours');
const OUTPUT_PATH = path.join(ROOT, 'tour-pricing.json');

const KNOWN_ZONE_CODES = new Set(['a', 'b', 'c', 'especial']);
const ZONE_LABELS = { a: 'Zone A', b: 'Zone B', c: 'Zone C', especial: 'Special / Custom' };
const TOURS_PUBLIC_DIR = path.join(ROOT, 'tours');
const VALID_ESTIMATOR_STATUSES = new Set(['ACTIVE', 'INACTIVE', 'MANUAL QUOTE']);

const errors = [];
const warnings = [];
function fail(msg) { errors.push(msg); }
function warn(msg) { warnings.push(msg); }

// ---- CLI ----
const args = process.argv.slice(2);
const tourArg = args.find(a => a.startsWith('--tour='));
const pilotSlugs = tourArg ? tourArg.slice('--tour='.length).split(',').map(s => s.trim()).filter(Boolean) : null;
const dryRun = args.includes('--dry-run') || args.includes('--validate-only');

// ---- Text normalization for tour-name matching ----
function stripAccents(s) {
  return String(s || '').normalize('NFD').replace(/[̀-ͯ]/g, '');
}
function norm(s) {
  return stripAccents(s).toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim();
}
function prefixBeforeEmDash(s) {
  const i = String(s || '').indexOf(' — ');
  return i === -1 ? s : String(s).slice(0, i);
}
function stripTrailingWord(s, word) {
  const re = new RegExp('\\s+' + word + '$', 'i');
  return String(s || '').replace(re, '');
}
function slugifyOption(label) {
  return norm(label).replace(/\s+/g, '-') || 'default';
}

// ---- Load the tour catalogue and build a strict name/alias index ----
if (!fs.existsSync(TOURS_DIR)) fail('knowledge/tours directory not found');
const tourFiles = fs.existsSync(TOURS_DIR) ? fs.readdirSync(TOURS_DIR).filter(f => f.endsWith('.json')) : [];
const tours = tourFiles.map(f => {
  try {
    return JSON.parse(fs.readFileSync(path.join(TOURS_DIR, f), 'utf8'));
  } catch (e) {
    fail(`knowledge/tours/${f} is not valid JSON: ${e.message}`);
    return null;
  }
}).filter(Boolean);

const knownSlugs = new Set(tours.map(t => t.slug));
const nameIndex = new Map(); // normalized variant -> Set(slug)
function indexVariant(variant, slug) {
  const n = norm(variant);
  if (!n) return;
  if (!nameIndex.has(n)) nameIndex.set(n, new Set());
  nameIndex.get(n).add(slug);
}
tours.forEach(t => {
  const names = [t.name, ...(t.aliases || [])];
  names.forEach(name => {
    if (!name) return;
    indexVariant(name, t.slug);
    indexVariant(prefixBeforeEmDash(name), t.slug);
    indexVariant(stripTrailingWord(name, 'tour'), t.slug);
    indexVariant(stripTrailingWord(prefixBeforeEmDash(name), 'tour'), t.slug);
  });
});

// A tour name is also considered resolved if it is an unambiguous PREFIX of
// exactly one tour's own name (covers cases like Excel "Arenal Hanging
// Bridges" vs. the real page name "Arenal Hanging Bridges Mistico") -- but
// only ever accepted when exactly one tour matches; multiple matches is a
// hard error, never a guess.
function resolveBySlugUrlOrName(excelTourName, fuenteUrl) {
  // 1) A tour-specific URL in "Fuente" is the strongest signal.
  if (fuenteUrl) {
    const m = String(fuenteUrl).match(/\/tours\/([a-z0-9-]+)\/?$/i);
    if (m && knownSlugs.has(m[1])) return { slug: m[1], via: 'fuente_url' };
  }
  // 2) Exact/alias/dash/trailing-"Tour" normalized match.
  const n = norm(excelTourName);
  const exact = nameIndex.get(n);
  if (exact && exact.size === 1) return { slug: [...exact][0], via: 'exact_name' };
  if (exact && exact.size > 1) return { slug: null, via: 'ambiguous', candidates: [...exact] };
  // 3) Unambiguous prefix match against real tour names.
  const prefixMatches = tours.filter(t => norm(t.name).startsWith(n) && n.length >= 6);
  if (prefixMatches.length === 1) return { slug: prefixMatches[0].slug, via: 'prefix_match' };
  if (prefixMatches.length > 1) return { slug: null, via: 'ambiguous', candidates: prefixMatches.map(t => t.slug) };
  return { slug: null, via: 'unresolved' };
}

// ---- Load the Excel workbook ----
if (!fs.existsSync(EXCEL_PATH)) {
  fail(`Excel matrix not found at ${EXCEL_PATH}`);
}
let wb;
if (errors.length === 0) {
  try {
    wb = XLSX.readFile(EXCEL_PATH);
  } catch (e) {
    fail(`Could not open the Excel file: ${e.message}`);
  }
}

function reportAndExit() {
  if (warnings.length) {
    console.log(`\n${warnings.length} warning(s):`);
    warnings.forEach(w => console.log('  WARN:', w));
  }
  if (errors.length) {
    console.log(`\n${errors.length} error(s) -- tour-pricing.json was NOT written:`);
    errors.forEach(e => console.log('  ERROR:', e));
    process.exit(1);
  }
}

if (errors.length) { reportAndExit(); }

// ---- Sheet: Hoteles y Zonas ----
const hotelsSheet = wb.Sheets['Hoteles y Zonas'];
if (!hotelsSheet) fail('Sheet "Hoteles y Zonas" not found');
const hotelRows = hotelsSheet ? XLSX.utils.sheet_to_json(hotelsSheet, { header: 1, defval: null }) : [];
// Header row is the first row whose first cell is exactly "Hotel / Resort"
const hotelHeaderIdx = hotelRows.findIndex(r => r[0] === 'Hotel / Resort');
const hotelDataRows = hotelHeaderIdx === -1 ? [] : hotelRows.slice(hotelHeaderIdx + 1);

const hotels = [];
const seenHotelNames = new Set();
hotelDataRows.forEach((r, i) => {
  const rowNum = hotelHeaderIdx + 2 + i; // 1-based Excel row
  const [name, zoneRaw] = r;
  if (!name) return; // blank trailing rows
  const nameKey = norm(name);
  if (seenHotelNames.has(nameKey)) {
    fail(`Hoteles y Zonas row ${rowNum}: duplicate hotel "${name}"`);
    return;
  }
  seenHotelNames.add(nameKey);

  let zoneCode = null;
  const zoneNorm = norm(zoneRaw);
  if (zoneNorm === 'a') zoneCode = 'a';
  else if (zoneNorm === 'b') zoneCode = 'b';
  else if (zoneNorm === 'c') zoneCode = 'c';
  else if (zoneNorm === 'especial' || zoneNorm === 'special') zoneCode = 'especial';
  else {
    fail(`Hoteles y Zonas row ${rowNum}: hotel "${name}" has an invalid zone "${zoneRaw}" (expected A, B, C or Especial)`);
    return;
  }
  hotels.push({ name: String(name).trim(), zone: zoneCode });
});

// ---- Sheet: Precios Tours ----
const pricingSheet = wb.Sheets['Precios Tours'];
if (!pricingSheet) fail('Sheet "Precios Tours" not found');
const priceRows = pricingSheet ? XLSX.utils.sheet_to_json(pricingSheet, { header: 1, defval: null }) : [];
const priceHeaderIdx = priceRows.findIndex(r => r[0] === 'Tour');
const priceDataRows = priceHeaderIdx === -1 ? [] : priceRows.slice(priceHeaderIdx + 1);

function parsePriceCell(v, rowNum, label) {
  if (v === null || v === undefined || v === '') return null; // no price -- Custom Quote Required downstream
  const n = Number(v);
  if (!Number.isFinite(n)) { fail(`Precios Tours row ${rowNum}: "${label}" is not a valid number (${JSON.stringify(v)})`); return null; }
  if (n < 0) { fail(`Precios Tours row ${rowNum}: "${label}" is negative (${n})`); return null; }
  return n;
}
function parseZoneAdjustmentCell(v, rowNum, label) {
  if (v === null || v === undefined || v === '') return null; // undefined -- Custom Quote Required for that zone
  const n = Number(v);
  if (!Number.isFinite(n)) { fail(`Precios Tours row ${rowNum}: "${label}" is not a valid number (${JSON.stringify(v)})`); return null; }
  if (n < 0) { fail(`Precios Tours row ${rowNum}: "${label}" is negative (${n})`); return null; }
  return n;
}

const tourEntries = {}; // slug -> { options: [] }
const seenTourOption = new Set(); // "slug||optionId"

priceDataRows.forEach((r, i) => {
  const rowNum = priceHeaderIdx + 2 + i; // 1-based Excel row
  const [tourName, optionLabel, pp2, pp3, pp4plus, zoneA, zoneB, zoneC, notes, fuente, slugCell, optionIdCell, zoneAppliesCell, statusCell] = r;
  if (!tourName) return; // blank trailing rows

  // PRIMARY mapping key: the explicit "Tour Slug" column. Authoritative --
  // no name/alias/URL guessing involved when it's present. An explicit slug
  // that doesn't match any known tour is always a hard error (never
  // silently ignored), regardless of pilot scope.
  let resolved;
  if (slugCell) {
    const explicitSlug = String(slugCell).trim();
    if (!knownSlugs.has(explicitSlug)) {
      fail(`Precios Tours row ${rowNum}: "Tour Slug" column has "${explicitSlug}", which is not a known tour slug`);
      return;
    }
    resolved = { slug: explicitSlug, via: 'explicit_slug_column' };
  } else {
    // Legacy fallback -- only reached when the row hasn't been migrated to
    // the explicit Tour Slug column yet. Always warned about, even on
    // success, so migration gaps stay visible.
    resolved = resolveBySlugUrlOrName(tourName, fuente);
    if (resolved.slug) {
      warn(`Precios Tours row ${rowNum}: "${tourName}" has no "Tour Slug" value -- resolved via legacy ${resolved.via} fallback to "${resolved.slug}". Add the explicit slug to stop relying on this fallback.`);
    }
  }

  const inPilotScope = !pilotSlugs || pilotSlugs.includes(resolved.slug);

  if (!resolved.slug) {
    const detail = resolved.via === 'ambiguous'
      ? `matches multiple tours: ${resolved.candidates.join(', ')}`
      : 'no matching tour slug (checked exact name, aliases, dash-prefix, "Tour" suffix, and Fuente URL)';
    const msg = `Precios Tours row ${rowNum}: tour "${tourName}" could not be mapped to a known slug -- ${detail}`;
    if (!pilotSlugs || tourName) {
      // In pilot mode, an unrelated unmapped tour is a warning (out of
      // scope for this run); in full-catalogue mode, or if it happens to
      // be a pilot tour itself, it's a hard error.
      if (pilotSlugs) warn(msg + ' (out of scope for this pilot run)');
      else fail(msg);
    }
    return;
  }
  if (!optionLabel) {
    fail(`Precios Tours row ${rowNum}: tour "${tourName}" (${resolved.slug}) has no Option/Package label`);
    return;
  }

  // PRIMARY option key: the explicit "Option ID" column. Falls back to a
  // slugified label only when absent, with a warning -- same posture as
  // the tour slug above.
  let optionId;
  if (optionIdCell) {
    optionId = String(optionIdCell).trim();
  } else {
    optionId = slugifyOption(optionLabel);
    warn(`Precios Tours row ${rowNum}: "${resolved.slug}" option "${optionLabel}" has no "Option ID" value -- derived "${optionId}" from the label. Add the explicit Option ID to stop relying on this fallback.`);
  }

  const dedupeKey = resolved.slug + '||' + optionId;
  if (seenTourOption.has(dedupeKey)) {
    fail(`Precios Tours row ${rowNum}: duplicate option "${optionLabel}" for tour "${resolved.slug}"`);
    return;
  }
  seenTourOption.add(dedupeKey);

  // Only validate/emit rows that are actually in scope for this run -- but
  // duplicates/malformed data anywhere already failed above regardless of
  // scope, which is intentional (a corrupt row anywhere still blocks a
  // clean pilot run of the requested tour).
  if (!inPilotScope) return;

  // ---- Estimator Status (authoritative: ACTIVE / INACTIVE / MANUAL QUOTE) ----
  // Blank is only tolerated when this row is merely along for the ride in a
  // full-catalogue run scoped elsewhere -- it is never tolerated for a row
  // that's actually in scope for this run (pilot tour or full-catalogue
  // mode), because generating output for a tour nobody has classified yet
  // would be exactly the kind of silent assumption this project avoids.
  const statusRaw = statusCell ? String(statusCell).trim().toUpperCase() : '';
  if (statusRaw && !VALID_ESTIMATOR_STATUSES.has(statusRaw)) {
    fail(`Precios Tours row ${rowNum}: "${resolved.slug}"/"${optionId}" has an invalid Estimator Status "${statusCell}" (expected ACTIVE, INACTIVE, or MANUAL QUOTE)`);
    return;
  }
  if (!statusRaw) {
    fail(`Precios Tours row ${rowNum}: "${resolved.slug}"/"${optionId}" is in scope for this run but has no Estimator Status set`);
    return;
  }

  if (statusRaw === 'INACTIVE') {
    // Excluded entirely -- no prices, packages or hotel rules exposed.
    return;
  }

  // ---- ACTIVE-only structural requirements ----
  if (statusRaw === 'ACTIVE') {
    if (!optionIdCell) {
      fail(`Precios Tours row ${rowNum}: "${resolved.slug}" option "${optionLabel}" is ACTIVE but has no explicit "Option ID" -- required for ACTIVE rows, not just recommended`);
      return;
    }
    const publicPagePath = path.join(TOURS_PUBLIC_DIR, resolved.slug + '.html');
    if (!fs.existsSync(publicPagePath)) {
      fail(`Precios Tours row ${rowNum}: "${resolved.slug}" is ACTIVE but has no public tour page at tours/${resolved.slug}.html`);
      return;
    }
  }

  // ---- Zone Adjustment Applies (YES / NO / blank=unconfirmed-legacy) ----
  const zoneAppliesRaw = zoneAppliesCell ? String(zoneAppliesCell).trim().toUpperCase() : '';
  let zoneAdjustmentApplies = null; // null = unconfirmed -- legacy per-zone-cell behavior (blank cell -> Custom Quote Required)
  if (zoneAppliesRaw === 'YES') zoneAdjustmentApplies = true;
  else if (zoneAppliesRaw === 'NO') zoneAdjustmentApplies = false;
  else if (zoneAppliesRaw) {
    fail(`Precios Tours row ${rowNum}: "${resolved.slug}"/"${optionId}" has an invalid "Zone Adjustment Applies" value "${zoneAppliesCell}" (expected YES or NO)`);
    return;
  }

  const entry = {
    id: optionId,
    label: String(optionLabel).trim(),
    estimator_status: statusRaw === 'ACTIVE' ? 'active' : 'manual_quote',
    pp_2: parsePriceCell(pp2, rowNum, '2 pax p.p.'),
    pp_3: parsePriceCell(pp3, rowNum, '3 pax p.p.'),
    pp_4plus: parsePriceCell(pp4plus, rowNum, '4+ pax p.p.'),
    zone_adjustment_applies: zoneAdjustmentApplies,
    zone_adjustment: {
      a: parseZoneAdjustmentCell(zoneA, rowNum, 'Zona A ajuste/grupo'),
      b: parseZoneAdjustmentCell(zoneB, rowNum, 'Zona B ajuste/grupo'),
      c: parseZoneAdjustmentCell(zoneC, rowNum, 'Zona C ajuste/grupo'),
    },
    notes: notes ? String(notes).trim() : null,
    source_row: rowNum,
  };

  if (!tourEntries[resolved.slug]) tourEntries[resolved.slug] = { tour_name_excel: String(tourName).trim(), options: [] };
  tourEntries[resolved.slug].options.push(entry);
});

if (pilotSlugs) {
  pilotSlugs.forEach(s => {
    if (!tourEntries[s]) fail(`--tour=${s} was requested but no ACTIVE/MANUAL QUOTE rows were found in the Excel for that slug (it may not exist, or every matching row is INACTIVE)`);
  });
}

// ---- Full-catalogue-only: every real public tour page must have SOME
// Excel row (any status) -- silently having zero rows means nobody made a
// deliberate decision about it, unlike an explicit INACTIVE. ----
if (!pilotSlugs && fs.existsSync(TOURS_PUBLIC_DIR)) {
  const publicSlugs = fs.readdirSync(TOURS_PUBLIC_DIR).filter(f => f.endsWith('.html')).map(f => f.replace(/\.html$/, ''));
  const excelSlugsWithAnyRow = new Set();
  priceDataRows.forEach(r => { if (r[10]) excelSlugsWithAnyRow.add(String(r[10]).trim()); });
  publicSlugs.forEach(slug => {
    if (knownSlugs.has(slug) && !excelSlugsWithAnyRow.has(slug)) {
      fail(`Public tour page tours/${slug}.html has no corresponding Excel row of any Estimator Status (not even INACTIVE)`);
    }
  });
}

reportAndExit();

// ---- Build output ----
const excelBytes = fs.readFileSync(EXCEL_PATH);
const hash = crypto.createHash('sha256').update(excelBytes).digest('hex').slice(0, 16);
const generatedAt = new Date().toISOString();

const output = {
  pricing_version: `sha256-${hash}`,
  generated_at: generatedAt,
  source_file: path.basename(EXCEL_PATH),
  scope: pilotSlugs ? `pilot:${pilotSlugs.join(',')}` : 'full-catalogue',
  zones: Object.fromEntries(Object.keys(ZONE_LABELS).map(code => [code, { label: ZONE_LABELS[code] }])),
  hotels,
  tours: tourEntries,
};

if (dryRun) {
  console.log(`\nDRY RUN -- all validations passed, ${OUTPUT_PATH} was NOT written.`);
} else {
  fs.writeFileSync(OUTPUT_PATH, JSON.stringify(output, null, 2) + '\n', 'utf8');
  console.log(`\nWrote ${OUTPUT_PATH}`);
}
console.log(`pricing_version: ${output.pricing_version}`);
console.log(`Tours included: ${Object.keys(tourEntries).join(', ') || '(none)'}`);
if (warnings.length) console.log(`(${warnings.length} out-of-scope warning(s) shown above)`);
