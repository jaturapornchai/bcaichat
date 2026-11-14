# UX/UI & API Specification — BC Ai Chat (`d:\bcaichat\frontend`)

## 1. แนวคิดหลัก: 100% Personal + Mobile-First + Minimal Popups
1. **แชทส่วนตัว ครอบครัว และแก๊งเพื่อน (ธีมดินเผาบ้านเชียง `ban_chiang`)**:
   - ออกแบบบนโทนดินเผาบ้านเชียง (`#812920`, Deep `#681F18`, Soft `#FFDAD5`, Bubble `#FADBD4`, Mist Ivory `#FBF9F8`, Terracotta Night `#1C1412`, Ban Chiang Cream `#F5EFEA`) พร้อม 7 ธีมสีไทยร่วมสมัยที่สลับและซิงค์สดข้ามทุกเครื่อง
   - **กฎเหล็ก UI (Baseline-First)**: ข้อความ ปุ่ม ช่องกรอก ไอคอน และ Badge ในแถวเดียวกันต้องอยู่ระนาบ Baseline และกึ่งกลางแนวนอนเดียวกัน (`crossAxisAlignment: CrossAxisAlignment.center`) ห้ามเหลื่อมสูง-ต่ำ
   - **Mobile-First & Minimal Popups**: เปิดแอปแล้วเข้าหน้า **แชท (index 1)** ทันทีเหมือนแอปแชทมือถือจริง และใช้แผงยืดหดในหน้า (Inline Panels / Trays) แทนการเปิด `showDialog` / `showModalBottomSheet` ซ้อนทับหน้าจอ
   - รองรับ Native 4 แพลตฟอร์ม (`android`, `ios`, `windows`, `macos`) — ห้ามสร้างโฟลเดอร์ `frontend/web/`

2. **โครงสร้าง 4 แท็บหลัก & ฟีเจอร์ในห้องแชท**:
   - **Login & 5 บัญชี Demo + ลุงจืด**:
     - รองรับ `jead@bcaichat.local` (`ลุงจืด` เจ้าของระบบ), `demo1..5@bcaichat.local` (เพื่อนสนิท/ครอบครัว/ก๊วนกีฬา), `somchai@bcaichat.local`, `nida@bcaichat.local` และเปิดทดสอบ 5 หน้าต่างบน Windows (`--test-login=... --test-slot=0..4`)
     - แก้ไข Server URL (`bcaichat_api_base` / `API_BASE_URL`) แบบ Inline ภายในหน้า Login
   - **แท็บ 0: หน้าหลัก (`หน้าหลัก`)**: โปรไฟล์ส่วนตัว, QR Code (`bcaichat://add/...`), แก้ไขข้อมูล, เพิ่มเพื่อน, สร้างกลุ่ม และเข้ากลุ่มด้วยรหัสเชิญแบบ Inline Collapsible Panels พร้อมจัดการรายการโปรด/ซ่อน/บล็อกเพื่อน และทางลัด Mini-App ส่วนตัว
   - **แท็บ 1: แชท (`แชท` — ค่าเริ่มต้นเมื่อเปิดแอป)**:
     - แถบโฟลเดอร์เลื่อนแนวนอนบนมือถือ: `ทั้งหมด`, `ส่วนตัว`, `ครอบครัว`, `กลุ่ม`, `ปักหมุด`, `ยังไม่อ่าน`, `เก็บถาวร` (ตัวกรอง `ครอบครัว` รองรับทั้ง `family` และ `work` เพื่อความเข้ากันได้ของข้อมูลเดิม)
     - **ภายในห้องแชท (`ChatRoomScreen`)**:
       - ปักหมุดประกาศหัวห้อง, ค้นหาข้อความในห้อง, สลับ 3 โทนพื้นหลัง (`ครีมบ้านเชียง`, `กลางคืนดินเผา`, `งาช้างอบอุ่น`)
       - โหมดข้อความ: `ปกติ` / `เรื่องด่วน` / `ส่งเงียบนอกเวลา`, โหมดข้อความลับส่วนตัว (`🔒 ความลับส่วนตัว` ซ่อนบนหน้าจอก่อนแตะเปิดอ่าน), แท็ก `@all` / `@สมาชิก` / `@ai`, สติกเกอร์ชุด *"อารมณ์ดีดินเผาไทย"*, ข้อความเสียง, การ์ดโต้ตอบ (`rich_card`), Emoji Reactions, ตอบกลับ, ลบเฉพาะฉัน, ยกเลิกทุกคน, ลบไร้ร่องรอย
       - เครื่องมือในห้องแบบ Inline Overlay / Composer Tray (ไร้ Dialog): **คลังรูปภาพ ไฟล์ถาวร & โน้ตห้อง**, **อัลบั้มรูป (`Albums`)**, **นัดเจอ & กิจกรรม (`Events / RSVP`)**, **โพลโหวต (`Polls`)**, **จัดการกลุ่ม & เชิญ 🤖 BC AI**, **BC AI สรุปแชทให้เข้าใจไว**, และ **AI เกลาคำพูด/คิดคำตอบ/แปลภาษา**
   - **แท็บ 2: สมุดบันทึก (`สมุดบันทึก`)**: สมุดบันทึกส่วนตัว (`สมุดบันทึก BC`) ซิงค์ข้ามเครื่อง ปักหมุด ถูกใจ คอมเมนต์ และสร้าง/แก้ไขโน้ตแบบ Inline
   - **แท็บ 3: ตั้งค่า (`ตั้งค่า`)**: เลือก 7 ธีมสีไทย (ซิงค์เมื่อเป็นเจ้าของระบบ), ตั้งค่าเสียงและการแจ้งเตือนรายเครื่องแบบ Inline, เปิดดูเครื่องมือเสริมส่วนตัว (`ผู้ช่วย AI ส่วนตัว`, `หารค่าข้าวกับเพื่อน`, `จัดทริปเที่ยว`, `ลิสต์ของฝาก / ช้อปปิ้ง`, `การ์ดชวนนัดเจอ`), และส่วนจัดการระบบเฉพาะผู้ดูแล (สถานะ MinIO, ตั้งค่า DeepSeek AI ส่วนตัว, ส่งประกาศเข้าห้องข่าวสาร, สมาชิก Gmail)

---

## 2. Backend API Contract (`http://127.0.0.1:8096`)
- **Base URL**: `http://127.0.0.1:8096` (Android Emulator default: `http://10.0.2.2:8096`)
- **WebSocket URL**: `ws://127.0.0.1:8096/ws?token=<JWT>`
- **Header**: `Authorization: Bearer <JWT>`
- **Endpoints หลัก**:
  1. Auth & Profile: `POST /api/auth/google`, `GET /api/auth/me`, `PUT /api/auth/profile`
  2. Friends: `GET /api/friends`, `PUT /api/friends/:id` (`is_favorite`, `is_blocked`, `is_hidden`), `GET /api/users/search?q=...`, `POST /api/friends/add`
  3. Conversations & Group: `GET /api/conversations?folder=all` (รองรับ `family` / `work`), `POST /api/conversations/direct`, `POST /api/conversations/group`, `POST /api/conversations/join`, `PUT /api/conversations/:id/meta`, `POST /api/conversations/:id/members`, `DELETE /api/conversations/:id/members/:member_id`, `PUT /api/conversations/:id/pin-message`
  4. Messages, Reactions, Polls & Events: `GET /api/conversations/:id/messages`, `POST /api/conversations/:id/messages` (`text|sticker|image|file|audio|rich_card|poll|event`), `POST /api/conversations/:id/read`, `POST /api/messages/:id/react`, `POST /api/messages/:id/delete-for-me`, `DELETE /api/messages/:id/unsend`, `POST /api/conversations/:id/polls`, `POST /api/polls/:id/vote`, `POST /api/polls/:id/close`, `POST /api/conversations/:id/events`, `GET /api/conversations/:id/events`, `POST /api/events/:id/rsvp`
  5. Vault, Albums, Notes & AI: `GET /api/conversations/:id/vault`, `GET /api/conversations/:id/albums`, `POST /api/conversations/:id/albums`, `POST /api/albums/:id/photos`, `DELETE /api/albums/:id`, `GET /api/notes?conversation_id=...`, `POST /api/notes`, `PUT /api/notes/:id`, `DELETE /api/notes/:id`, `POST /api/notes/:id/like`, `POST /api/notes/:id/comments`, `POST /api/ai/summarize`, `POST /api/ai/assist`
  6. Upload & Admin: `POST /api/upload`, `GET /api/mini-apps`, `GET /api/settings/theme`, `GET /api/admin/overview`, `GET /api/admin/users`, `PUT /api/admin/users/:id/role`, `PUT /api/admin/theme`, `GET/PUT /api/admin/ai-settings`, `GET/POST/PUT/DELETE /api/admin/mini-apps`, `POST /api/admin/broadcast`
