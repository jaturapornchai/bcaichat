# AGENTS.md — BC Ai Chat (`D:\bcaichat`)

เอกสารกติกาและคู่มือสถาปัตยกรรมสำหรับ AI และนักพัฒนาในโปรเจกต์ **BC Ai Chat** (แอปแชทส่วนตัว ครอบครัว แก๊งเพื่อน และผู้ช่วย AI · Mobile-First & Minimal Popups)

---

## 1. สถาปัตยกรรมระบบ (System Architecture)

| ส่วนประกอบ | เทคโนโลยีหลัก | ตำแหน่งไฟล์ | พอร์ต / Endpoint |
| :--- | :--- | :--- | :--- |
| **Infrastructure** | Docker Compose (`mongo:7.0`, `minio/minio:latest`) | `docker-compose.yml` | MongoDB `:27030` (DB `bcaichat`) · MinIO API `:9130` / Console `:9131` (bucket `bcaichat-storage`) |
| **Backend API & WS** | Rust (`axum`, `tokio`, `mongodb`, `reqwest`, `jsonwebtoken`) ชื่อแพ็กเกจ `bcaichat-backend` (`bcaichat_backend`) | `backend/` | HTTP `http://127.0.0.1:8096` · WS `ws://127.0.0.1:8096/ws` |
| **Web App** | Next.js 15 (`^15.3.3`), React 19 (`^19.1.0`), TypeScript, Tailwind CSS v4 (`@tailwindcss/postcss`), `lucide-react` | `web/` | `http://localhost:3096` (rewrites `/api/*` และ `/miniapp/*` ไปยัง `:8096`) |
| **Native App (4 Platforms)** | Flutter (`android`, `ios`, `windows`, `macos`) แพ็กเกจ `bcaichat_app` / ID `com.bcaichat.app` | `frontend/` | เชื่อมต่อ `:8096` (Android Emulator ใช้ `http://10.0.2.2:8096` เป็นค่าเริ่มต้น) |
| **Apple CI Build** | GitHub Actions (`workflow_dispatch` บน `macos-latest`) | `.github/workflows/build-apple.yml` | สร้าง artifact `bcaichat-apple-builds` (`iOS` unsigned + `macOS`) |
| **E2E Suites** | Node.js API/WS Test & Playwright 5-Context Browser Test | `e2e/` | `e2e/e2e_api_ws_5users.mjs`, `e2e/e2e_playwright_web_5users.mjs` |

### โครงสร้างโมดูล & UX หลัก (Personal Mobile-First + Zero-Popup)
- **Backend (`backend/src/`)**: `main.rs`, `lib.rs`, `config.rs`, `models.rs` (default category `'เพื่อน'`, alias `folder="family"` / `"work"`), `auth.rs`, `minio.rs`, `push.rs`, `ws.rs`, `seed.rs` (migrate/upsert ข้อมูลส่วนตัว + 5 Mini-Apps ส่วนตัว), และ `routes/` (`admin_routes`, `ai_routes`, `auth_routes`, `chat_routes`, `file_routes`, `miniapp_routes`, `push_routes`)
- **Web (`web/src/`)**:
  - SEO & GEO: `public/robots.txt`, `public/llms.txt`, `src/app/sitemap.ts`, `src/app/layout.tsx` (`SocialNetworkingApplication` JSON-LD, ฟอนต์ `Prompt` OFL, `<h1>` เดียวต่อหน้า)
  - 4 แท็บหลัก (`เพื่อน`, `แชท` default, `สมุดบันทึก`, `ตั้งค่า`) + Immersive Room บน `< md` + Inline Trays/Panels (`room-side-panel`, `rich-card-inline-tray`, `ai-inline-tray`, 0 `.fixed.inset-0` / `role="dialog"`)
  - หน้า `/multi-demo` ทดสอบ 5 จอพร้อมกัน (`MultiDemoWorkspace.tsx`)
- **Flutter (`frontend/lib/`)**:
  - เฉพาะ Native 4 แพลตฟอร์ม (`android/`, `ios/`, `windows/`, `macos/`) — **ห้ามสร้างโฟลเดอร์ `frontend/web/` หรือไฟล์ `push_web*.dart`**
  - 4 แท็บหลัก (`0: หน้าหลัก`, `1: แชท` default, `2: สมุดบันทึก`, `3: ตั้งค่า`) + Inline Collapsible Panels/Trays บน `login_screen.dart`, `main_shell.dart`, `mini_app_runner_screen.dart`, และ `chat_room_screen.dart` (0 `showDialog` / `showModalBottomSheet`)
  - Windows multi-window (`windows/runner/main.cpp`): รองรับ `--test-slot=0..4` จัดเรียงหน้าต่างทดสอบ 5 จอข้างกันอัตโนมัติ

---

## 2. รายชื่อบัญชีทดสอบ & ข้อมูล Seed (`backend/src/seed.rs`)

### บัญชี Demo ทั้ง 5 บัญชี (อยู่เป็นเพื่อนกันและอยู่ในกลุ่ม `conv_group_demo5` "แก๊งเพื่อนสนิท 5 คน + BC AI" ร่วมกับ `user_ai`)

| User ID | Email | ชื่อแสดงผล | BC ID | กลุ่ม/ความสัมพันธ์ |
| :--- | :--- | :--- | :--- | :--- |
| `user_demo1` | `demo1@bcaichat.local` | ก้อง (Demo 1) | `@kong.bc` | เพื่อนสนิท (สายเที่ยว & ถ่ายรูป) |
| `user_demo2` | `demo2@bcaichat.local` | แพร (Demo 2) | `@prae.bc` | เพื่อนสนิท (สายคาเฟ่ & ชวนกินข้าว) |
| `user_demo3` | `demo3@bcaichat.local` | บอส (Demo 3) | `@boss.bc` | ครอบครัว (สายแกดเจ็ต & เพลง) |
| `user_demo4` | `demo4@bcaichat.local` | มายด์ (Demo 4) | `@mind.bc` | เพื่อนสนิท (สายดูหนัง & ซีรีส์) |
| `user_demo5` | `demo5@bcaichat.local` | ต้น (Demo 5) | `@ton.bc` | ก๊วนกีฬา (สายวิ่ง & แคมป์ปิ้ง) |

### บัญชีเจ้าของระบบ ผู้ช่วย AI และบัญชีครอบครัว/เพื่อนบ้าน

| User ID | Email | ชื่อแสดงผล | BC ID | Role / หน้าที่ |
| :--- | :--- | :--- | :--- | :--- |
| `user_jead` | `jead@bcaichat.local` | ลุงจืด | `jead.bc` | `admin` — เจ้าของระบบ, จัดการธีม, AI Settings, ประกาศข่าวสาร |
| `user_ai` | `ai@bcaichat.local` | 🤖 BC AI ผู้ช่วยส่วนตัว | `@bc.ai` | `admin` — ตอบแชท 1-1 หรือเรียก `@ai` / `@bc.ai` / `/ai` / `บีซีเอไอ` ในกลุ่ม |
| `user_somchai` | `somchai@bcaichat.local` | สมชาย เพื่อนบ้าน | `somchai.s` | `user` — เพื่อนบ้านประจำซอย (`conv_group_family`) |
| `user_nida` | `nida@bcaichat.local` | นิดา พี่สาว | `nida.acc` | `user` — พี่สาวในกลุ่มครอบครัว (`conv_group_family`) |
| `user_official` | `official@bcaichat.local` | ข่าวสาร BC Ai Chat | `@bc.official` | `admin` — ห้องข่าวสารและเคล็ดลับการใช้แอป |

### บริการเสริมส่วนตัว (Personal Mini-Apps)
`ai_companion` (`ผู้ช่วย AI ส่วนตัว` `/miniapp/ai`), `split_bill` (`หารค่าข้าวกับเพื่อน` `/miniapp/split`), `trip_planner` (`จัดทริปเที่ยว` `/miniapp/trip`), `gift_wishlist` (`ลิสต์ของฝาก / ช้อปปิ้ง` `/miniapp/wishlist`), `hangout_invite` (`การ์ดชวนนัดเจอ` `/miniapp/hangout`)

---

## 3. กฎเหล็กประจำโปรเจกต์ (Iron Rules)

1. **ธีมบ้านเชียงเป็นค่าเริ่มต้น (`ban_chiang`)**:
   - สีหลัก: Primary `#812920`, Deep `#681F18`, Ring `#A04035`, Ochre `#83280E`, Gold Clay `#D4A373`, Surface `#FBF9F8`, Panel `#F6F3F2`, Sand `#E4DFD1`, Card `#FFFFFF`, Border `#DCC0BC`, Soft `#FFDAD5`, Sent Bubble `#FADBD4`
   - รองรับ 7 ธีมไทยร่วมสมัย (`ban_chiang`, `silk_amber`, `indigo_kram`, `jade_celadon`, `lotus_rose`, `spice_cinnamon`, `royal_amethyst`) ซิงค์สดผ่าน WS `theme_changed` และ 3 โทนห้องแชท (`ban_chiang_cream` `#F5EFEA`, `terracotta_night` `#1C1412`, `ivory_white` `#FBF9F8`)
2. **ปลอดลิขสิทธิ์ 100% (Zero-Copyright Policy)**:
   - ใช้เฉพาะแบรนด์ **BC Ai Chat**, **สมุดบันทึก BC**, **การ์ดโต้ตอบ** (`rich_card`), **ข่าวสาร BC Ai Chat**, ชุดสติกเกอร์ต้นฉบับ *"อารมณ์ดีดินเผาไทย"*
   - ห้ามใช้ชื่อแบรนด์ เครื่องหมายการค้า ชื่อฟีเจอร์ หรือชุดสีเขียวของแพลตฟอร์มแชทภายนอกโดยเด็ดขาด
   - ห้ามนำภาพถ่ายโบราณวัตถุจากกรมศิลปากรหรือแหล่งภายนอกมาใช้ (ตกแต่งด้วยลวดลายเส้นเกลียวคลื่นประยุกต์ CSS/SVG ต้นฉบับเท่านั้น)
   - ใช้ฟอนต์ `Prompt` (SIL OFL), ไอคอน `lucide-react` (MIT) / Material Icons (Apache-2.0), และเสียงสังเคราะห์ Web Audio API / ไฟล์ WAV ต้นฉบับใน `frontend/assets/sounds/`
3. **ห้าม Commit Secrets & Workspace Isolation**:
   - ห้ามพิมพ์หรือ commit `.env`, `DEEPSEEK_API_KEY`, `ELEVENLABS_API_KEY`, `JWT_SECRET`, `*.pem`, `*.key`, `credentials*.json` (`.env` ถูกกันไว้ใน `.gitignore` แล้ว; ใช้ `.env.example` เฉพาะค่าตัวอย่าง)
   - พัฒนาแบบ Forward-Only ภายใน repository นี้เท่านั้น ห้ามแก้ไขไฟล์นอก workspace
4. **Baseline-First, Mobile-First & Contract Safety**:
   - ข้อความ ปุ่ม ช่องกรอก ไอคอน และ Badge ในแถวเดียวกันต้องอยู่ระนาบ Baseline / กึ่งกลางแนวนอนเดียวกัน (`items-center` / `CrossAxisAlignment.center`)
   - เลี่ยง Popup ซ้อนหน้าจอ ใช้ Inline Collapsible Panels/Trays และแถบโฟลเดอร์เลื่อนแนวนอนบนมือถือ (`ทั้งหมด`, `ส่วนตัว`, `ครอบครัว`, `กลุ่ม`, `ปักหมุด`, `ยังไม่อ่าน`, `เก็บถาวร`)
   - ฟิลด์ใหม่ใน Rust DTO ต้องระบุ `#[serde(default)]` เพื่อคงความเข้ากันได้ข้ามแพลตฟอร์ม และคง fallback alias (`work` -> `family`, `[ลับเฉพาะองค์กร]` -> `[ลับส่วนตัว]`) สำหรับข้อมูลเก่า

---

## 4. คำสั่งตรวจสอบและทดสอบ E2E (Verification & Test Commands)

```powershell
# 1. Infrastructure (ที่ D:\bcaichat)
docker compose up -d
docker compose ps

# 2. Rust Backend Unit/Integration Tests & Server (:8096)
cd D:\bcaichat\backend
cargo test
cargo run

# 3. API + WebSocket + MinIO + AI E2E (5 Demo Accounts)
cd D:\bcaichat
node e2e/e2e_api_ws_5users.mjs

# 4. Next.js Web Typecheck, Build, Server (:3096) & Playwright 5-Context E2E
cd D:\bcaichat\web
npx tsc --noEmit
npm run build
npm run start
node D:\bcaichat\e2e\e2e_playwright_web_5users.mjs

# 5. Flutter 4-Platform Analysis, Tests, Live E2E & Windows Release Build
cd D:\bcaichat\frontend
flutter pub get
flutter analyze
flutter test
flutter test test_e2e/live_backend_e2e_test.dart
flutter build windows --release
```
