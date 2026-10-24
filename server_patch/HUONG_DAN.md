# Gắn giải mã thẻ ngân hàng Zalo vào máy chủ (cho Gemini/Claude trên máy Windows)

Tin `chat.webcontent` có `content.action = "zinstant.bankcard"` (bấm "Gửi tài khoản ngân hàng" trong Zalo) hiện được lưu thành
`[Loại tin chưa hỗ trợ: chat.webcontent]`, nên app chỉ hiện "Thẻ Zalo".

`the_ngan_hang.mjs` đã viết sẵn và chạy thử đúng trên dữ liệu thật: tải `params.item.data_url` (gzip), đọc `bundle_data` → `bankNum`, `bankName`.

Việc cần làm trong mã máy chủ (web_zalo.mjs / luu_tru.mjs):
1. Chép `the_ngan_hang.mjs` vào cạnh mã máy chủ, `import { laTheNganHang, giaiTheNganHang } from './the_ngan_hang.mjs'`.
2. Ở chỗ nhận tin mới **trước khi lưu và trước khi đẩy SSE cho app**: nếu `laTheNganHang(goc)` thì
   `const ck = await giaiTheNganHang(goc)`; có kết quả thì đặt `chu = ck.chu` và `phu.chuyenKhoan = ck.chuyenKhoan`
   (giữ `loai = 'chat.webcontent'`, `kieu = 'chu'`). Lỗi mạng thì để nguyên như cũ, không chặn việc lưu tin.
3. Chạy bù một lần cho tin cũ:
   `select msg_id, goc from tin where loai='chat.webcontent' and goc like '%zinstant.bankcard%'` → giải → `update tin set chu=?, phu=?`
   (gộp vào `phu` hiện có, nếu có).
4. Dòng xem trước của cuộc chat (`tin_cuoi`) cũng dùng `chu` mới.

App từ v6.4 tự hiện thẻ chuyển khoản có QR khi có `phu.chuyenKhoan` hoặc `chu` dạng "VPBank - 0912345678".
Thử nhanh: `node thu.mjs goc.json` (goc.json = cột goc của 1 tin thẻ ngân hàng).
