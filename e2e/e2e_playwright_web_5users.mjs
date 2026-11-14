import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const webPlaywrightPath = path.resolve(
  __dirname,
  "../web/node_modules/playwright/index.mjs"
);
const { chromium } = await import(`file://${webPlaywrightPath.replace(/\\/g, "/")}`);

async function launchChromiumBrowser() {
  try {
    return await chromium.launch({ headless: true });
  } catch {
    const cacheDir = path.join(process.env.LOCALAPPDATA || "", "ms-playwright");
    if (fs.existsSync(cacheDir)) {
      const dirs = fs
        .readdirSync(cacheDir)
        .filter((d) => /^chromium_headless_shell-\d+$/.test(d) || /^chromium-\d+$/.test(d))
        .sort((a, b) => Number(b.split("-").pop()) - Number(a.split("-").pop()));
      for (const d of dirs) {
        const candidates = [
          path.join(cacheDir, d, "chrome-headless-shell-win64", "chrome-headless-shell.exe"),
          path.join(cacheDir, d, "chrome-win64", "chrome.exe"),
        ];
        for (const exe of candidates) {
          if (fs.existsSync(exe)) {
            return await chromium.launch({ headless: true, executablePath: exe });
          }
        }
      }
    }
    return await chromium.launch({ headless: true, channel: "chrome" });
  }
}

const WEB_URL = process.env.WEB_URL || "http://localhost:3096";
const API_URL = process.env.API_URL || "http://127.0.0.1:8096";
const RUN_ID = Date.now().toString(36).toUpperCase();

// 1x1 terracotta PNG pixel buffer (in-memory upload test for Album)
const TINY_PNG_BASE64 =
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8z8AABQMBgQ4r6hAAAAAASUVORK5CYII=";

const FORBIDDEN_WORDS = [
  "TElORQ==",
  "TGFyaw==",
  "V2VDaGF0",
  "V2hhdHNBcHA=",
  "S2FrYW8=",
  "VGVsZWdyYW0=",
  "TWVzc2VuZ2Vy",
  "RmxleCBNZXNzYWdl",
  "RmxleCBDYXJk",
  "S2VlcCBNZW1v",
].map((b) => Buffer.from(b, "base64").toString("utf8"));
const FORBIDDEN_HEX = ["MDZDNzU1", "MDBCOTAw"].map((b) =>
  Buffer.from(b, "base64").toString("utf8")
);
const FORBIDDEN_BUSINESS_WORDS = [
  "ฝ่ายขาย",
  "บัญชีการเงิน",
  "บัญชีและการเงิน",
  "คลังสินค้า",
  "ดูแลลูกค้า",
  "จัดซื้อ",
  "อนุมัติใบลา",
  "ออกใบเสนอราคา",
  "ใบกำกับภาษี",
  "แชทองค์กร",
  "โอนย้ายงาน",
];

function logStep(name) {
  console.log(`\n▶ [${new Date().toLocaleTimeString("th-TH")}] ${name}`);
}

async function checkSeoAndGeoEndpoints() {
  logStep("1. ตรวจ SEO / GEO Endpoints (/robots.txt, /llms.txt, /sitemap.xml, /)");
  const robotsRes = await fetch(`${WEB_URL}/robots.txt`);
  assert.equal(robotsRes.status, 200, "/robots.txt must return 200");
  const robots = await robotsRes.text();
  for (const bot of [
    "Googlebot",
    "OAI-SearchBot",
    "ChatGPT-User",
    "GPTBot",
    "ClaudeBot",
    "PerplexityBot",
    "Google-Extended",
    "Sitemap:",
  ]) {
    assert.ok(robots.includes(bot), `/robots.txt missing ${bot}`);
  }

  const llmsRes = await fetch(`${WEB_URL}/llms.txt`);
  assert.equal(llmsRes.status, 200, "/llms.txt must return 200");
  const llms = await llmsRes.text();
  assert.ok(llms.includes("BC Ai Chat"), "/llms.txt must mention BC Ai Chat");
  for (const bw of FORBIDDEN_BUSINESS_WORDS) {
    assert.ok(!llms.includes(bw), `/llms.txt must not contain business word: ${bw}`);
  }

  const sitemapRes = await fetch(`${WEB_URL}/sitemap.xml`);
  assert.equal(sitemapRes.status, 200, "/sitemap.xml must return 200");
  const sitemap = await sitemapRes.text();
  assert.ok(sitemap.includes("<urlset"), "/sitemap.xml must contain <urlset");
  assert.ok(sitemap.includes("/multi-demo"), "/sitemap.xml must include /multi-demo");

  const homeRes = await fetch(`${WEB_URL}/`);
  assert.equal(homeRes.status, 200, "/ must return 200");
  const homeHtml = await homeRes.text();
  const h1Count = (homeHtml.match(/<h1[\s>]/gi) || []).length;
  assert.equal(h1Count, 1, `/ must have exactly 1 <h1>, found ${h1Count}`);
  assert.ok(homeHtml.includes('"@graph"'), "/ must include JSON-LD @graph");
  assert.ok(
    homeHtml.includes("SocialNetworkingApplication"),
    "/ JSON-LD must use SocialNetworkingApplication"
  );
  for (const bw of FORBIDDEN_BUSINESS_WORDS) {
    assert.ok(!homeHtml.includes(bw), `/ HTML must not contain business word: ${bw}`);
  }
  for (const hex of FORBIDDEN_HEX) {
    assert.ok(!homeHtml.toUpperCase().includes(hex), `HTML must not contain #${hex}`);
  }
  console.log("  ✓ SEO/GEO endpoints + single <h1> + JSON-LD @graph verified");
}

async function checkServicesReady() {
  logStep("0. ตรวจ Backend (:8096) และ Web (:3096)");
  const apiHealth = await fetch(`${API_URL}/api/health`);
  assert.equal(apiHealth.status, 200, "Backend /api/health must be 200");
  const webRoot = await fetch(`${WEB_URL}/`);
  assert.equal(webRoot.status, 200, "Web root must be 200");
  console.log("  ✓ Backend :8096 and Next.js :3096 are healthy");
}

function attachErrorCollector(page, label, collector) {
  page.on("pageerror", (err) => {
    collector.push(`[${label}] pageerror: ${err.message}`);
  });
  page.on("console", (msg) => {
    if (msg.type() === "error") {
      const loc = msg.location()?.url ? ` (${msg.location().url})` : "";
      collector.push(`[${label}] console.error: ${msg.text()}${loc}`);
    }
  });
  page.on("response", (res) => {
    if (res.status() >= 400) {
      console.warn(`  ⚠ [${label}] HTTP ${res.status()} -> ${res.url()}`);
    }
  });
}

async function assertNoForbiddenTextInDom(page, label) {
  const bodyText = await page.evaluate(() => document.body.innerText || "");
  for (const w of FORBIDDEN_WORDS) {
    const re = new RegExp(`\\b${w}\\b`, "i");
    assert.ok(!re.test(bodyText), `[${label}] forbidden brand word detected: ${w}`);
  }
  for (const bw of FORBIDDEN_BUSINESS_WORDS) {
    assert.ok(!bodyText.includes(bw), `[${label}] forbidden business word detected: ${bw}`);
  }
  const html = await page.content();
  for (const hex of FORBIDDEN_HEX) {
    assert.ok(!html.toUpperCase().includes(hex), `[${label}] forbidden color #${hex}`);
  }
}

async function assertZeroFixedInsetOverlays(page, label) {
  const overlayCount = await page.evaluate(
    () => document.querySelectorAll(".fixed.inset-0").length
  );
  assert.equal(
    overlayCount,
    0,
    `[${label}] expected 0 .fixed.inset-0 modal overlays, found ${overlayCount}`
  );
}

async function sendTextAsUser(page, text) {
  const input = page.getByTestId("chat-message-input");
  await input.waitFor({ state: "visible", timeout: 15000 });
  await input.fill(text);
  await page.getByTestId("chat-send-btn").click();
}

async function run() {
  await checkServicesReady();
  await checkSeoAndGeoEndpoints();

  const browser = await launchChromiumBrowser();
  const errors = [];
  const contexts = [];
  const pages = [];

  try {
    logStep("2. เปิด 5 Browser Contexts พร้อมกันและล็อกอิน Demo 1–5 (localhost:3096/?demo=1..5)");
    for (let i = 1; i <= 5; i++) {
      const ctx = await browser.newContext({
        viewport: { width: 1280, height: 820 },
      });
      const page = await ctx.newPage();
      attachErrorCollector(page, `Demo${i}`, errors);
      contexts.push(ctx);
      pages.push(page);
    }

    await Promise.all(
      pages.map(async (page, idx) => {
        const slot = idx + 1;
        await page.goto(`${WEB_URL}/?demo=${slot}`, { waitUntil: "domcontentloaded" });
        await page.getByTestId("active-room-title").waitFor({ state: "visible", timeout: 25000 });
        await page.getByTestId("chat-message-input").waitFor({ state: "visible", timeout: 15000 });
      })
    );

    const [p1, p2, p3, p4, p5] = pages;

    // Ensure all 5 users have conv_group_demo5 open and verify Ban Chiang palette CSS var + desktop layout
    for (let i = 0; i < pages.length; i++) {
      const demoConv = pages[i].getByTestId("conv-item-conv_group_demo5");
      if (await demoConv.count()) {
        await demoConv.first().click();
      }
      await pages[i].waitForFunction(
        () =>
          getComputedStyle(document.documentElement)
            .getPropertyValue("--bc-primary")
            .trim()
            .toLowerCase() === "#812920"
      );
      const noHorizontalScroll = await pages[i].evaluate(
        () => document.documentElement.scrollWidth <= window.innerWidth + 2
      );
      assert.ok(noHorizontalScroll, `Demo ${i + 1} desktop viewport must not overflow horizontally`);
      await assertNoForbiddenTextInDom(pages[i], `Demo${i + 1}`);
    }
    console.log("  ✓ All 5 browser contexts logged in with Ban Chiang theme (#812920) and 0 overflow");

    logStep("3. ทดสอบส่งข้อความสดข้ามจอผ่าน WebSocket (Demo 1 <-> Demo 2..5)");
    const msg1 = `E2E_WS_DEMO1_${RUN_ID}: สวัสดีแก๊งเพื่อนบ้านเชียง`;
    await sendTextAsUser(p1, msg1);

    await Promise.all(
      pages.map((p) =>
        p.locator(`[data-testid^="message-item-"]:has-text("${msg1}")`).first().waitFor({
          state: "visible",
          timeout: 15000,
        })
      )
    );

    const msg2 = `E2E_WS_DEMO2_${RUN_ID}: รับทราบครับ Demo 1`;
    await sendTextAsUser(p2, msg2);
    await p1
      .locator(`[data-testid^="message-item-"]:has-text("${msg2}")`)
      .first()
      .waitFor({ state: "visible", timeout: 15000 });
    console.log("  ✓ Real-time WebSocket chat verified across all 5 browser contexts");

    logStep("4. ทดสอบ Emoji Reaction สดข้ามจอ (Demo 3 กด 👍 -> ขึ้นที่ Demo 1)");
    const msg1CardOnP3 = p3.locator(`[data-testid^="message-item-"]:has-text("${msg1}")`).first();
    await msg1CardOnP3.locator('[data-testid^="react-👍-"]').click();
    const msg1CardOnP1 = p1.locator(`[data-testid^="message-item-"]:has-text("${msg1}")`).first();
    await msg1CardOnP1.locator('button:has-text("👍")').filter({ hasText: "1" }).waitFor({
      state: "visible",
      timeout: 15000,
    });
    console.log("  ✓ Live emoji reaction count (👍 1) verified on Demo 1 via WebSocket");

    logStep("5. ทดสอบสร้างโพล & โหวตข้ามผู้ใช้ (Demo 1 สร้าง -> Demo 4, 5 โหวต)");
    const pollQ = `E2E_POLL_${RUN_ID}: นัดสรุปงานเวลาไหนดี`;
    await p1.getByTestId("room-btn-polls").click();
    await p1.getByTestId("room-side-panel").waitFor({ state: "visible", timeout: 10000 });
    await assertZeroFixedInsetOverlays(p1, "PollSidePanel");
    await p1.getByPlaceholder("คำถามโพล เช่น เสาร์นี้ไปกินร้านไหนดี?").fill(pollQ);
    await p1.getByPlaceholder("ตัวเลือกที่ 1").fill("10:00 น.");
    await p1.getByPlaceholder("ตัวเลือกที่ 2").fill("14:00 น.");
    await p1.getByTestId("create-poll-submit").click();
    await p1.getByRole("button", { name: "ปิดหน้าต่างเครื่องมือ" }).click();

    const pollCardP4 = p4.locator(`[data-testid^="message-item-"]:has-text("${pollQ}")`).first();
    await pollCardP4.waitFor({ state: "visible", timeout: 15000 });
    await pollCardP4.locator('[data-testid^="poll-opt-"]').first().click();

    const pollCardP5 = p5.locator(`[data-testid^="message-item-"]:has-text("${pollQ}")`).first();
    await pollCardP5.waitFor({ state: "visible", timeout: 15000 });
    await pollCardP5.locator('[data-testid^="poll-opt-"]').first().click();

    const pollCardP1 = p1.locator(`[data-testid^="message-item-"]:has-text("${pollQ}")`).first();
    await pollCardP1
      .locator('[data-testid^="poll-opt-"]')
      .first()
      .filter({ hasText: "2" })
      .waitFor({ state: "visible", timeout: 15000 });
    console.log("  ✓ Live Poll creation and cross-user voting (2 votes) verified");

    logStep("6. ทดสอบสร้างนัดหมาย & RSVP (Demo 2 สร้าง -> Demo 1, 3 กดเข้าร่วม)");
    const eventTitle = `E2E_EVENT_${RUN_ID}: นัดกินข้าวแก๊งเพื่อน`;
    await p2.getByTestId("room-btn-events").click();
    await p2.getByTestId("room-side-panel").waitFor({ state: "visible", timeout: 10000 });
    await assertZeroFixedInsetOverlays(p2, "EventSidePanel");
    await p2.getByPlaceholder("ชื่อนัดหมาย เช่น นัดกินหมูกระทะเสาร์นี้").fill(eventTitle);
    await p2.getByPlaceholder("สถานที่นัดเจอ / ลิงก์วิดีโอคอล").fill("ร้านหมูกระทะบ้านเชียง");
    await p2.getByPlaceholder("รายละเอียดนัดหมาย...").fill("ทดสอบครบทุกฟีเจอร์");
    await p2.getByTestId("create-event-submit").click();
    await p2.getByRole("button", { name: "ปิดหน้าต่างเครื่องมือ" }).click();

    const evCardP1 = p1.locator(`[data-testid^="message-item-"]:has-text("${eventTitle}")`).first();
    await evCardP1.waitFor({ state: "visible", timeout: 15000 });
    await evCardP1.getByTestId(/rsvp-going-/).first().click();
    await evCardP1
      .locator('[data-testid^="rsvp-going-"]')
      .filter({ hasText: "1" })
      .waitFor({ state: "visible", timeout: 15000 });

    const evCardP3 = p3.locator(`[data-testid^="message-item-"]:has-text("${eventTitle}")`).first();
    await evCardP3.waitFor({ state: "visible", timeout: 15000 });
    await evCardP3.getByTestId(/rsvp-going-/).first().click();

    await p2
      .locator(`[data-testid^="message-item-"]:has-text("${eventTitle}")`)
      .first()
      .locator('[data-testid^="rsvp-going-"]')
      .filter({ hasText: "2" })
      .waitFor({ state: "visible", timeout: 15000 });
    console.log("  ✓ Event creation & live RSVP count (เข้าร่วม 2) verified");

    logStep("7. ทดสอบอัลบั้มรูป (Demo 3 สร้างอัลบั้ม + อัปโหลดรูปจริง)");
    const albumTitle = `E2E_ALBUM_${RUN_ID}`;
    await p3.getByTestId("room-btn-albums").click();
    await p3.getByTestId("room-side-panel").waitFor({ state: "visible", timeout: 10000 });
    await assertZeroFixedInsetOverlays(p3, "AlbumSidePanel");
    await p3.getByPlaceholder("ชื่ออัลบั้ม เช่น ทริปทะเล / มื้ออร่อย").fill(albumTitle);
    await p3.getByPlaceholder("คำอธิบายอัลบั้ม (ไม่บังคับ)").fill("อัปโหลดจาก E2E 5 Users");
    await p3.locator('[data-testid="room-side-panel"] input[type="file"]').first().setInputFiles({
      name: `tile-${RUN_ID}.png`,
      mimeType: "image/png",
      buffer: Buffer.from(TINY_PNG_BASE64, "base64"),
    });
    await p3.getByTestId("create-album-submit").click();
    await p3.locator(`[data-testid="room-side-panel"] h4:has-text("${albumTitle}")`).waitFor({
      state: "visible",
      timeout: 15000,
    });
    await p3.locator(`[data-testid="room-side-panel"] p:has-text("1 รูป")`).first().waitFor({
      state: "visible",
      timeout: 15000,
    });
    await p3.getByRole("button", { name: "ปิดหน้าต่างเครื่องมือ" }).click();
    console.log("  ✓ Album creation + PNG upload verified");

    logStep("8. ทดสอบโน้ตกลุ่ม ถูกใจ & คอมเมนต์ (Demo 4 สร้าง -> Demo 5 กดถูกใจ+คอมเมนต์)");
    const noteTitle = `E2E_NOTE_${RUN_ID}`;
    const noteComment = `เห็นด้วยครับ_${RUN_ID}`;
    await p4.getByTestId("room-btn-notes").click();
    await p4.getByTestId("room-side-panel").waitFor({ state: "visible", timeout: 10000 });
    await assertZeroFixedInsetOverlays(p4, "NoteSidePanelP4");
    await p4.getByPlaceholder("หัวข้อโน้ตกลุ่ม...").fill(noteTitle);
    await p4.getByPlaceholder("รายละเอียดบันทึกประจำกลุ่ม...").fill("บันทึกทริปแก๊งเพื่อน E2E");
    await p4.getByTestId("create-group-note-submit").click();
    await p4.locator(`[data-testid="room-side-panel"] h4:has-text("${noteTitle}")`).waitFor({
      state: "visible",
      timeout: 15000,
    });
    await p4.getByRole("button", { name: "ปิดหน้าต่างเครื่องมือ" }).click();

    await p5.getByTestId("room-btn-notes").click();
    await p5.getByTestId("room-side-panel").waitFor({ state: "visible", timeout: 10000 });
    await assertZeroFixedInsetOverlays(p5, "NoteSidePanelP5");
    const noteCardP5 = p5
      .locator('[data-testid="room-side-panel"] div.rounded-2xl')
      .filter({ has: p5.locator(`h4:has-text("${noteTitle}")`) })
      .first();
    await noteCardP5.waitFor({ state: "visible", timeout: 15000 });
    await noteCardP5.locator('[data-testid^="like-note-"]').click();
    await noteCardP5.locator('[data-testid^="like-note-"]:has-text("ถูกใจ (1)")').waitFor({
      state: "visible",
      timeout: 15000,
    });
    await noteCardP5.getByPlaceholder("แสดงความคิดเห็น...").fill(noteComment);
    await noteCardP5.getByRole("button", { name: "ส่ง" }).click();
    await noteCardP5.locator(`text=${noteComment}`).waitFor({ state: "visible", timeout: 15000 });
    await p5.getByRole("button", { name: "ปิดหน้าต่างเครื่องมือ" }).click();
    console.log("  ✓ Group Note create + like + comment verified");

    logStep("9. ทดสอบเรียก @ai บนเว็บจริงจนได้คำตอบ 🤖 BC AI");
    const aiPromptText = `@ai สรุปสั้นๆ ให้ที ${RUN_ID}`;
    const aiMarkerMsg = p1
      .locator('[data-testid^="message-item-"]')
      .filter({ hasText: "BC AI" });
    const prevAiCount = await aiMarkerMsg.count();
    await p1.getByTestId("chat-message-input").fill(aiPromptText);
    await p1.getByTestId("chat-send-btn").click();
    await p1
      .locator(`[data-testid^="message-item-"]:has-text("${aiPromptText}")`)
      .first()
      .waitFor({ state: "visible", timeout: 15000 });

    await p2.waitForFunction(
      ({ expectedMin, promptStr }) => {
        const items = Array.from(document.querySelectorAll('[data-testid^="message-item-"]'));
        const promptIdx = items.findIndex((el) => (el.textContent || "").includes(promptStr));
        const after = promptIdx >= 0 ? items.slice(promptIdx + 1) : items;
        const aiMsgs = after.filter((el) => (el.textContent || "").includes("BC AI"));
        return aiMsgs.length >= 1 || items.filter((el) => (el.textContent || "").includes("BC AI")).length > expectedMin;
      },
      { expectedMin: prevAiCount, promptStr: aiPromptText },
      { timeout: 25000 }
    );
    console.log("  ✓ @ai trigger produced BC AI reply visible across WS contexts");

    logStep("10. ทดสอบหน้า /multi-demo (5 จอ Demo 1–5 ในหน้าเดียว)");
    const multiCtx = await browser.newContext({ viewport: { width: 1440, height: 900 } });
    const multiPage = await multiCtx.newPage();
    attachErrorCollector(multiPage, "MultiDemo", errors);
    contexts.push(multiCtx);

    await multiPage.goto(`${WEB_URL}/multi-demo`, { waitUntil: "domcontentloaded" });
    await multiPage.locator("h1:has-text('Multi-Demo')").waitFor({ state: "visible", timeout: 15000 });
    for (let slot = 1; slot <= 5; slot++) {
      await multiPage.getByTestId(`multi-demo-pane-${slot}`).waitFor({
        state: "visible",
        timeout: 15000,
      });
    }
    await multiPage.locator("text=5/5 ออนไลน์").waitFor({ state: "visible", timeout: 20000 });

    const multiMsg = `E2E_MULTIDEMO_${RUN_ID}`;
    const pane3 = multiPage.getByTestId("multi-demo-pane-3");
    await pane3.getByPlaceholder("พิมพ์ในนาม Demo 3...").fill(multiMsg);
    await pane3.getByRole("button", { name: "ส่ง" }).click();

    const pane4 = multiPage.getByTestId("multi-demo-pane-4");
    await pane4.locator(`text=${multiMsg}`).first().waitFor({ state: "visible", timeout: 15000 });
    await assertNoForbiddenTextInDom(multiPage, "MultiDemo");
    await assertZeroFixedInsetOverlays(multiPage, "MultiDemo");
    console.log("  ✓ /multi-demo 5/5 online panes & cross-pane live messaging verified");

    logStep("11. ทดสอบ Mobile-First Viewport (390x844), Zero Modal Overlays & 100% Personal Copy");
    const mobileCtx = await browser.newContext({
      viewport: { width: 390, height: 844 },
      hasTouch: true,
      isMobile: true,
    });
    const mobilePage = await mobileCtx.newPage();
    attachErrorCollector(mobilePage, "Mobile390", errors);
    contexts.push(mobileCtx);

    await mobilePage.goto(WEB_URL, { waitUntil: "domcontentloaded" });
    await mobilePage.getByTestId("demo-login-1").waitFor({ state: "visible", timeout: 15000 });
    const loginOverflow = await mobilePage.evaluate(
      () => document.documentElement.scrollWidth > window.innerWidth + 2
    );
    assert.equal(loginOverflow, false, "Mobile 390px login must have 0 horizontal overflow");
    await assertZeroFixedInsetOverlays(mobilePage, "MobileLogin");
    await assertNoForbiddenTextInDom(mobilePage, "MobileLogin");

    await mobilePage.getByTestId("demo-login-1").click();
    await mobilePage.getByTestId("mobile-bottom-nav").waitFor({ state: "visible", timeout: 15000 });
    await mobilePage
      .getByTestId("conv-item-conv_group_demo5")
      .waitFor({ state: "visible", timeout: 15000 });

    const roomHiddenOnChatsTab = await mobilePage.getByTestId("active-room-title").isVisible();
    assert.equal(roomHiddenOnChatsTab, false, "Mobile chats list must be single-column");

    await mobilePage.getByTestId("folder-chip-family").waitFor({ state: "visible", timeout: 5000 });
    const chatsOverflow = await mobilePage.evaluate(
      () => document.documentElement.scrollWidth > window.innerWidth + 2
    );
    assert.equal(chatsOverflow, false, "Mobile 390px chats tab must have 0 horizontal overflow");
    await assertZeroFixedInsetOverlays(mobilePage, "MobileChats");

    // Check inline QR & inline Create Group on เพื่อน (home) tab
    await mobilePage.getByTestId("mobile-nav-tab-home").click();
    await mobilePage.getByTestId("toggle-qr-inline-btn").click();
    await mobilePage.getByTestId("inline-qr-card").waitFor({ state: "visible", timeout: 5000 });
    await assertZeroFixedInsetOverlays(mobilePage, "MobileInlineQR");
    await mobilePage.getByTestId("open-create-group-btn").click();
    await mobilePage
      .getByTestId("inline-create-group-form")
      .waitFor({ state: "visible", timeout: 5000 });
    await assertZeroFixedInsetOverlays(mobilePage, "MobileInlineGroup");

    // Check สมุดบันทึก & ตั้งค่า tabs (zero business copy / zero handover)
    await mobilePage.getByTestId("mobile-nav-tab-notes").click();
    await mobilePage.getByTestId("create-personal-note-btn").waitFor({ state: "visible", timeout: 5000 });
    await mobilePage.getByTestId("mobile-nav-tab-services").click();
    await mobilePage.getByTestId("logout-btn").waitFor({ state: "visible", timeout: 5000 });
    await assertNoForbiddenTextInDom(mobilePage, "MobileSettings");

    // Open room -> immersive full-screen chat on mobile (< md)
    await mobilePage.getByTestId("mobile-nav-tab-chats").click();
    await mobilePage.getByTestId("conv-item-conv_group_demo5").click();
    await mobilePage.getByTestId("active-room-title").waitFor({ state: "visible", timeout: 10000 });
    const bottomNavHiddenInRoom = !(await mobilePage.getByTestId("mobile-bottom-nav").isVisible());
    assert.equal(bottomNavHiddenInRoom, true, "Mobile room must hide bottom nav for full-screen chat");
    const roomOverflow = await mobilePage.evaluate(
      () => document.documentElement.scrollWidth > window.innerWidth + 2
    );
    assert.equal(roomOverflow, false, "Mobile 390px room must have 0 horizontal overflow");

    // Check inline room tools (Albums, Notes, Polls) & inline AI assist tray with 0 modal overlays
    for (const toolBtn of ["room-btn-albums", "room-btn-notes", "room-btn-polls"]) {
      await mobilePage.getByTestId(toolBtn).click();
      await mobilePage.getByTestId("room-side-panel").waitFor({ state: "visible", timeout: 5000 });
      await assertZeroFixedInsetOverlays(mobilePage, `Mobile-${toolBtn}`);
      const toolOverflow = await mobilePage.evaluate(
        () => document.documentElement.scrollWidth > window.innerWidth + 2
      );
      assert.equal(toolOverflow, false, `Mobile 390px ${toolBtn} must have 0 horizontal overflow`);
      await mobilePage.getByTestId("close-room-side-panel").click();
    }

    await mobilePage.getByTestId("btn-ai-assist").click();
    await mobilePage.getByTestId("ai-inline-tray").waitFor({ state: "visible", timeout: 5000 });
    await assertZeroFixedInsetOverlays(mobilePage, "MobileAiTray");
    const aiTrayOverflow = await mobilePage.evaluate(
      () => document.documentElement.scrollWidth > window.innerWidth + 2
    );
    assert.equal(aiTrayOverflow, false, "Mobile 390px AI tray must have 0 horizontal overflow");
    await mobilePage.getByRole("button", { name: "ปิดแถบผู้ช่วย AI" }).click();

    await mobilePage.getByTestId("mobile-back-btn").click();
    await mobilePage.getByTestId("mobile-bottom-nav").waitFor({ state: "visible", timeout: 5000 });
    await assertNoForbiddenTextInDom(mobilePage, "MobileFinal");
    await assertZeroFixedInsetOverlays(mobilePage, "MobileFinal");
    console.log("  ✓ Mobile-First 390x844 UX, 0 overlays, 0 overflow, 100% personal copy verified");

    assert.equal(
      errors.length,
      0,
      `Expected 0 console/page errors, got:\n${errors.join("\n")}`
    );
    console.log("\n🎉 ผ่าน E2E Web 5 Users + Multi-Demo + SEO/GEO ครบ 100% (0 console/page errors)!");
  } finally {
    await Promise.all(contexts.map((c) => c.close().catch(() => {})));
    await browser.close();
  }
}

run().catch((err) => {
  console.error("\n❌ E2E FAILED:", err);
  process.exit(1);
});
