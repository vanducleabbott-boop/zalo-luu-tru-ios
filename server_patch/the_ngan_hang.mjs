// Giải mã thẻ tài khoản ngân hàng Zalo (msgType "chat.webcontent", content.action "zinstant.bankcard").
// Dữ liệu thẻ không nằm trong tin mà ở params.item.data_url (CDN Zalo, công khai, nén gzip);
// trong đó có chuỗi "bundle_data":"{...bankNum, bankName...}".
// Dùng: const ck = await giaiTheNganHang(goc)  -> { chu, chuyenKhoan } hoặc null.
import { gunzipSync } from 'node:zlib';

const NGAN_HANG = {
  vietinbank: ['970415', 'VietinBank'], vietcombank: ['970436', 'Vietcombank'], bidv: ['970418', 'BIDV'],
  mbbank: ['970422', 'MBBank'], mb: ['970422', 'MBBank'], techcombank: ['970407', 'Techcombank'],
  acb: ['970416', 'ACB'], vpbank: ['970432', 'VPBank'], tpbank: ['970423', 'TPBank'],
  sacombank: ['970403', 'Sacombank'], hdbank: ['970437', 'HDBank'], vib: ['970441', 'VIB'],
  shb: ['970443', 'SHB'], msb: ['970426', 'MSB'], ocb: ['970448', 'OCB'], lpbank: ['970449', 'LPBank'],
  seabank: ['970440', 'SeABank'], agribank: ['970405', 'Agribank'], namabank: ['970428', 'Nam A Bank'],
  bacabank: ['970409', 'Bac A Bank'], bvbank: ['970454', 'BVBank'], pvcombank: ['970412', 'PVcomBank'],
  cake: ['546034', 'CAKE by VPBank'], timo: ['963388', 'Timo'], kienlongbank: ['970452', 'KienlongBank'],
  pgbank: ['970430', 'PGBank'], shinhanbank: ['970424', 'Shinhan Bank'], eximbank: ['970431', 'Eximbank'],
  abbank: ['970425', 'ABBANK'], vietabank: ['970427', 'VietABank'], ncb: ['970419', 'NCB'],
};

const boDem = new Map();   // data_url -> kết quả (thẻ không đổi nội dung)

export function laTheNganHang(goc) {
  return goc?.msgType === 'chat.webcontent' && goc?.content?.action === 'zinstant.bankcard';
}

export async function giaiTheNganHang(goc) {
  if (!laTheNganHang(goc)) return null;
  let params = goc.content.params;
  try { if (typeof params === 'string') params = JSON.parse(params); } catch { return null; }
  const url = params?.item?.data_url || params?.bubbleItem?.data_url;
  if (!url) return null;
  if (boDem.has(url)) return boDem.get(url);

  const res = await fetch(url, { signal: AbortSignal.timeout(10000) });
  if (!res.ok) return null;
  let buf = Buffer.from(await res.arrayBuffer());
  if (buf[0] === 0x1f && buf[1] === 0x8b) buf = gunzipSync(buf);
  const s = buf.toString('utf8');

  const m = s.match(/"bundle_data":"((?:[^"\\]|\\.)*)"/);
  if (!m) return null;
  let b;
  try { b = JSON.parse(JSON.parse(`"${m[1]}"`)); } catch { return null; }
  const stk = String(b.bankNum || '').replace(/\s/g, '');
  const tenNH = String(b.bankName || '').trim();
  if (!stk || !tenNH) return null;

  const ma = tenNH.toLowerCase().replace(/[^a-z]/g, '');
  const [bin, ten] = NGAN_HANG[ma] || [null, tenNH];
  const ketQua = {
    chu: `${ten} - ${stk}`,
    chuyenKhoan: {
      nganHang: ten,
      maNganHang: NGAN_HANG[ma] ? ma : tenNH,
      bin,
      stk,
      tenNguoiNhan: null,
      soTien: null,
      noiDung: null,
      qrUrl: `https://img.vietqr.io/image/${bin || ma}-${stk}-compact2.png`,
    },
  };
  boDem.set(url, ketQua);
  return ketQua;
}
