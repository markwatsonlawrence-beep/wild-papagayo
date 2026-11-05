// Responsive image variants (audit 2026-11-02). Writes images/<name>-<w>w.webp next to an original
// .webp for the widths requested, only when the original is wider than <w>. Originals are never
// touched. Each variant is checked against a lossless resize of the original (ImageMagick SSIM/PSNR)
// and deleted again if it falls below the quality floor, so that image simply keeps its original.
// Generators add srcset entries only for variants that exist (Get-SrcsetAttrs).
//
// Usage: SHARP=<path to sharp> node engine/image-variants.js <targets.json>
//   targets.json = { "200": ["a.webp", ...], "480": [...], "800": [...] }   (file names inside images/)
'use strict';
const fs = require('fs'); const path = require('path'); const { execFileSync } = require('child_process');
const sharp = require(process.env.SHARP || 'sharp');
sharp.cache(false); // Windows: a cached file handle would keep a rejected variant locked (EBUSY on delete)
const IMAGES = path.join(__dirname, '..', 'images');
const QUALITY = 82; const THUMB_QUALITY = 88; // tiny thumbnails need a little more quality to hold detail
const MIN_SSIM = 0.97; const MIN_PSNR = 32;
const targets = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const tmp = fs.mkdtempSync(path.join(require('os').tmpdir(), 'wp-variants-'));
// ImageMagick 7.1 prints "<raw> (<normalized>)" on stderr (exit 1 when the images differ).
// SSIM is reported as a dissimilarity: similarity = 1 - normalized. PSNR: the raw value in dB.
const metric = (m, a, b) => {
  const r = require('child_process').spawnSync('magick', ['compare', '-metric', m, a, b, 'null:'], { encoding: 'utf8' });
  const s = String(r.stderr || r.stdout || ''); const raw = parseFloat(s); const norm = parseFloat((s.match(/\(([^)]+)\)/) || [])[1]);
  return m === 'SSIM' ? 1 - norm : raw;
};
(async () => {
  const report = [];
  for (const [w, files] of Object.entries(targets)) for (const f of files) {
    const src = path.join(IMAGES, f); const out = path.join(IMAGES, f.replace(/\.webp$/i, `-${w}w.webp`));
    if (!/\.webp$/i.test(f) || !fs.existsSync(src)) { report.push({ f, w, status: 'skip-missing-or-not-webp' }); continue; }
    const meta = await sharp(src).metadata();
    if (meta.width <= Number(w)) { report.push({ f, w, status: 'skip-original-not-wider', orig: meta.width }); continue; }
    if (fs.existsSync(out)) { report.push({ f, w, status: 'exists' }); continue; }
    await sharp(src).resize({ width: Number(w) }).webp({ quality: Number(w) <= 200 ? THUMB_QUALITY : QUALITY, effort: 5 }).toFile(out);
    const ref = path.join(tmp, 'ref.png'), got = path.join(tmp, 'got.png');
    await sharp(src).resize({ width: Number(w) }).png().toFile(ref); await sharp(fs.readFileSync(out)).png().toFile(got);
    const ssim = metric('SSIM', ref, got), psnr = metric('PSNR', ref, got);
    const ok = (ssim >= MIN_SSIM || ssim === Infinity) && psnr >= MIN_PSNR;
    const r = { f, w, origW: meta.width, origBytes: fs.statSync(src).size, bytes: fs.statSync(out).size, ssim, psnr, status: ok ? 'ok' : 'rejected-quality' };
    if (!ok) fs.unlinkSync(out);
    report.push(r);
  }
  fs.rmSync(tmp, { recursive: true, force: true });
  fs.writeFileSync(process.argv[3] || 'image-variants-report.json', JSON.stringify(report, null, 1));
  const c = {}; for (const r of report) c[r.w + ' ' + r.status] = (c[r.w + ' ' + r.status] || 0) + 1; console.log(JSON.stringify(c));
})();
