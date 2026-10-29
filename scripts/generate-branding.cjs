#!/usr/bin/env node
// Development-only: npm install sharp in an external tooling directory and set
// NODE_PATH to its node_modules. Normal app builds use the committed exports.
const fs = require('node:fs/promises');
const path = require('node:path');
const sharp = require('sharp');
const root = path.resolve(__dirname, '..');
const output = path.join(root, 'assets/branding');

async function main() {
  const source = path.join(output, 'JustVibeRemote.svg');
  await sharp(source).resize(1024, 1024).png().toFile(path.join(output, 'JustVibeRemote.png'));
  const sizes = [16, 24, 32, 48, 64, 128, 256];
  const frames = await Promise.all(sizes.map(size => sharp(source).resize(size, size).png().toBuffer()));
  const header = Buffer.alloc(6 + sizes.length * 16);
  header.writeUInt16LE(1, 2); header.writeUInt16LE(sizes.length, 4);
  let offset = header.length;
  frames.forEach((frame, index) => {
    const entry = 6 + index * 16, size = sizes[index];
    header[entry] = header[entry + 1] = size === 256 ? 0 : size;
    header.writeUInt16LE(1, entry + 4); header.writeUInt16LE(32, entry + 6);
    header.writeUInt32LE(frame.length, entry + 8); header.writeUInt32LE(offset, entry + 12);
    offset += frame.length;
  });
  await fs.writeFile(path.join(output, 'JustVibeRemote.ico'), Buffer.concat([header, ...frames]));
  // Standard PNG-backed ICNS chunks, including Retina representations.
  const chunks = [];
  for (const [type, size] of [['ic07',128], ['ic08',256], ['ic09',512], ['ic10',1024],
                              ['ic11',32], ['ic12',64], ['ic13',256], ['ic14',512]]) {
    const png = await sharp(source).resize(size, size).png().toBuffer();
    const chunk = Buffer.alloc(8);
    chunk.write(type, 0, 'ascii'); chunk.writeUInt32BE(png.length + 8, 4);
    chunks.push(chunk, png);
  }
  const icnsHeader = Buffer.alloc(8);
  icnsHeader.write('icns', 0, 'ascii');
  icnsHeader.writeUInt32BE(8 + chunks.reduce((sum, chunk) => sum + chunk.length, 0), 4);
  await fs.writeFile(path.join(output, 'JustVibeRemote.icns'), Buffer.concat([icnsHeader, ...chunks]));
  console.log('Generated JustVibeRemote branding exports.');
}
main().catch(error => { console.error(error); process.exitCode = 1; });
