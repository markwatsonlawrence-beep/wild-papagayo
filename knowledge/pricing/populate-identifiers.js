// One-time migration helper: fills the "Tour Slug" / "Option ID" columns in
// the Excel matrix using the same resolution logic excel-to-pricing.js used
// as its legacy (name/alias/URL) fallback. After this runs, the converter's
// PRIMARY mapping key is these explicit columns -- this script exists only
// to seed them from already-verified matches, not to run on every conversion.
// Rows it can't confidently resolve are left blank and printed for manual
// review -- never guessed.

const fs = require('fs');
const path = require('path');
const XLSX = require('xlsx');

const TOURS_DIR = path.join(__dirname, '..', 'tours');
const EXCEL_PATH = path.join(__dirname, 'Matriz_Cotizador_Wild_Papagayo_Catalogo_Completo.xlsx');

function stripAccents(s) { return String(s || '').normalize('NFD').replace(/[̀-ͯ]/g, ''); }
function norm(s) { return stripAccents(s).toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim(); }
function prefixBeforeEmDash(s) { const i = String(s || '').indexOf(' — '); return i === -1 ? s : String(s).slice(0, i); }
function stripTrailingWord(s, word) { return String(s || '').replace(new RegExp('\\s+' + word + '$', 'i'), ''); }
function slugifyOption(label) { return norm(label).replace(/\s+/g, '-') || 'default'; }

const tourFiles = fs.readdirSync(TOURS_DIR).filter(f => f.endsWith('.json'));
const tours = tourFiles.map(f => JSON.parse(fs.readFileSync(path.join(TOURS_DIR, f), 'utf8')));
const knownSlugs = new Set(tours.map(t => t.slug));

const nameIndex = new Map();
function indexVariant(variant, slug) {
  const n = norm(variant);
  if (!n) return;
  if (!nameIndex.has(n)) nameIndex.set(n, new Set());
  nameIndex.get(n).add(slug);
}
tours.forEach(t => {
  [t.name, ...(t.aliases || [])].forEach(name => {
    if (!name) return;
    indexVariant(name, t.slug);
    indexVariant(prefixBeforeEmDash(name), t.slug);
    indexVariant(stripTrailingWord(name, 'tour'), t.slug);
    indexVariant(stripTrailingWord(prefixBeforeEmDash(name), 'tour'), t.slug);
  });
});

function resolve(excelTourName, fuenteUrl) {
  if (fuenteUrl) {
    const m = String(fuenteUrl).match(/\/tours\/([a-z0-9-]+)\/?$/i);
    if (m && knownSlugs.has(m[1])) return { slug: m[1], via: 'fuente_url' };
  }
  const n = norm(excelTourName);
  const exact = nameIndex.get(n);
  if (exact && exact.size === 1) return { slug: [...exact][0], via: 'exact_name' };
  if (exact && exact.size > 1) return { slug: null, via: 'ambiguous', candidates: [...exact] };
  const prefixMatches = tours.filter(t => norm(t.name).startsWith(n) && n.length >= 6);
  if (prefixMatches.length === 1) return { slug: prefixMatches[0].slug, via: 'prefix_match' };
  if (prefixMatches.length > 1) return { slug: null, via: 'ambiguous', candidates: prefixMatches.map(t => t.slug) };
  return { slug: null, via: 'unresolved' };
}

const wb = XLSX.readFile(EXCEL_PATH);
const ws = wb.Sheets['Precios Tours'];
const rows = XLSX.utils.sheet_to_json(ws, { header: 1, defval: null });
const headerIdx = rows.findIndex(r => r[0] === 'Tour');
if (headerIdx === -1) { console.error('Header row not found'); process.exit(1); }

// Add the two new header cells if not already present.
const headerRowNum = headerIdx + 1; // 1-based Excel row
const slugColLetter = 'K';
const optionColLetter = 'L';
function setCell(addr, value) {
  ws[addr] = { t: 's', v: value };
}
setCell(slugColLetter + headerRowNum, 'Tour Slug');
setCell(optionColLetter + headerRowNum, 'Option ID');

let filled = 0, unresolved = 0;
for (let i = headerIdx + 1; i < rows.length; i++) {
  const r = rows[i];
  const tourName = r[0];
  const optionLabel = r[1];
  const fuente = r[9];
  if (!tourName) continue;
  const excelRowNum = i + 1; // 1-based
  const resolved = resolve(tourName, fuente);
  if (resolved.slug) {
    setCell(slugColLetter + excelRowNum, resolved.slug);
    setCell(optionColLetter + excelRowNum, slugifyOption(optionLabel));
    filled++;
  } else {
    unresolved++;
    const detail = resolved.via === 'ambiguous' ? `ambiguous: ${resolved.candidates.join(', ')}` : 'no match';
    console.log(`UNRESOLVED row ${excelRowNum}: "${tourName}" (${detail}) -- left blank for manual entry`);
  }
}

// Extend the sheet range so the new columns are recognized.
const ref = XLSX.utils.decode_range(ws['!ref']);
if (ref.e.c < 11) { ref.e.c = 11; ws['!ref'] = XLSX.utils.encode_range(ref); }

XLSX.writeFile(wb, EXCEL_PATH);
console.log(`\nFilled Tour Slug + Option ID for ${filled} row(s); ${unresolved} row(s) left blank for manual review.`);
