// Reads real width/height directly from WebP file headers (no npm dependency,
// no external calls) and writes image-dimensions.json keyed by filename, so
// generators can inject real <img width height> attributes instead of guessing.
const fs = require('fs');
const path = require('path');

const imagesDir = path.join(__dirname, 'images');
const outPath = path.join(__dirname, 'image-dimensions.json');

function readWebpDimensions(buf) {
  if (buf.toString('ascii', 0, 4) !== 'RIFF' || buf.toString('ascii', 8, 12) !== 'WEBP') return null;
  const fourcc = buf.toString('ascii', 12, 16);
  if (fourcc === 'VP8X') {
    const width = 1 + (buf[24] | (buf[25] << 8) | (buf[26] << 16));
    const height = 1 + (buf[27] | (buf[28] << 8) | (buf[29] << 16));
    return { width, height };
  }
  if (fourcc === 'VP8 ') {
    // Lossy: chunk data starts at 20; sync code 0x9d 0x01 0x2a at offset 20+3
    if (buf[23] === 0x9d && buf[24] === 0x01 && buf[25] === 0x2a) {
      const w = buf.readUInt16LE(26) & 0x3fff;
      const h = buf.readUInt16LE(28) & 0x3fff;
      return { width: w, height: h };
    }
    return null;
  }
  if (fourcc === 'VP8L') {
    // Lossless: chunk data at offset 20, byte0 = 0x2f signature, then 4 bytes packed
    if (buf[20] !== 0x2f) return null;
    const b0 = buf[21], b1 = buf[22], b2 = buf[23], b3 = buf[24];
    const width = 1 + (((b1 & 0x3f) << 8) | b0);
    const height = 1 + (((b3 & 0x0f) << 10) | (b2 << 2) | ((b1 & 0xc0) >> 6));
    return { width, height };
  }
  return null;
}

const files = fs.readdirSync(imagesDir).filter(f => f.toLowerCase().endsWith('.webp'));
const out = {};
let ok = 0, fail = 0;
for (const f of files) {
  try {
    const fd = fs.openSync(path.join(imagesDir, f), 'r');
    const buf = Buffer.alloc(40);
    fs.readSync(fd, buf, 0, 40, 0);
    fs.closeSync(fd);
    const dim = readWebpDimensions(buf);
    if (dim) { out[f] = dim; ok++; } else { fail++; console.warn('Could not parse:', f); }
  } catch (e) {
    fail++;
    console.warn('Error reading', f, e.message);
  }
}
fs.writeFileSync(outPath, JSON.stringify(out, null, 2), 'utf8');
console.log('Wrote', outPath, '--', ok, 'images parsed,', fail, 'failed');
