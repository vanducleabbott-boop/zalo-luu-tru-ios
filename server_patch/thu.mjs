// Chạy thử: node thu.mjs <goc.json>
import { readFileSync } from 'node:fs';
import { giaiTheNganHang } from './the_ngan_hang.mjs';
const kq = await giaiTheNganHang(JSON.parse(readFileSync(process.argv[2], 'utf8')));
console.log(kq ? JSON.stringify(kq).replace(/\d{6,}/g, s => s.slice(0, 2) + '…' + s.slice(-2)) : 'null');
