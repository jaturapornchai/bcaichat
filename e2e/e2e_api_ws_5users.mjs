#!/usr/bin/env node
/**
 * BC Ai Chat — Comprehensive 5-User Real-time Personal API + WebSocket + AI + MongoDB + MinIO E2E Suite
 * Run: node D:\bcaichat\e2e\e2e_api_ws_5users.mjs
 */

import assert from "node:assert/strict";

const BASE_URL = process.env.BCAICHAT_API_URL || "http://127.0.0.1:8096";
const WS_BASE_URL = BASE_URL.replace(/^http/, "ws");

const decodeList = (arr) => arr.map((b64) => Buffer.from(b64, "base64").toString("utf8"));
const BANNED_WORDS = decodeList([
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
]);
const BANNED_COLORS = decodeList(["IzA2Yzc1NQ==", "IzAwYjkwMA=="]);

// Base64-encoded legacy business terms so this E2E file contains zero literal business words
const BANNED_BUSINESS_TERMS = [
  "\\u0e1d\\u0e48\\u0e32\\u0e22\\u0e02\\u0e32\\u0e22",
  "\\u0e1a\\u0e31\\u0e0d\\u0e0a\\u0e35\\u0e01\\u0e32\\u0e23\\u0e40\\u0e07\\u0e34\\u0e19",
  "\\u0e1a\\u0e31\\u0e0d\\u0e0a\\u0e35\\u0e41\\u0e25\\u0e30\\u0e01\\u0e32\\u0e23\\u0e40\\u0e07\\u0e34\\u0e19",
  "\\u0e04\\u0e25\\u0e31\\u0e07\\u0e2a\\u0e34\\u0e19\\u0e04\\u0e49\\u0e32",
  "\\u0e14\\u0e39\\u0e41\\u0e25\\u0e25\\u0e39\\u0e01\\u0e04\\u0e49\\u0e32",
  "\\u0e08\\u0e31\\u0e14\\u0e0b\\u0e37\\u0e49\\u0e2d",
  "\\u0e2d\\u0e19\\u0e38\\u0e21\\u0e31\\u0e15\\u0e34\\u0e43\\u0e1a\\u0e25\\u0e32",
  "\\u0e2d\\u0e2d\\u0e01\\u0e43\\u0e1a\\u0e40\\u0e2a\\u0e19\\u0e2d\\u0e23\\u0e32\\u0e04\\u0e32",
  "\\u0e43\\u0e1a\\u0e40\\u0e2a\\u0e19\\u0e2d\\u0e23\\u0e32\\u0e04\\u0e32",
  "\\u0e43\\u0e1a\\u0e01\\u0e33\\u0e01\\u0e31\\u0e1a\\u0e20\\u0e32\\u0e29\\u0e35",
  "\\u0e42\\u0e2d\\u0e19\\u0e22\\u0e49\\u0e32\\u0e22\\u0e07\\u0e32\\u0e19",
  "\\u0e41\\u0e0a\\u0e17\\u0e2d\\u0e07\\u0e04\\u0e4c\\u0e01\\u0e23",
  "\\u0e04\\u0e27\\u0e32\\u0e21\\u0e25\\u0e31\\u0e1a\\u0e2d\\u0e07\\u0e04\\u0e4c\\u0e01\\u0e23",
  "\\u0e1e\\u0e19\\u0e31\\u0e01\\u0e07\\u0e32\\u0e19\\u0e2d\\u0e07\\u0e04\\u0e4c\\u0e01\\u0e23",
].map((s) => JSON.parse(`"${s}"`));

const results = [];
function record(step, detail = "") {
  results.push({ step, detail });
  console.log(`✅ [PASS] ${step}${detail ? ` — ${detail}` : ""}`);
}

function assertCleanBranding(text, contextLabel) {
  const lower = text.toLowerCase();
  for (const c of BANNED_COLORS) {
    assert.ok(!lower.includes(c), `Banned color ${c} found in ${contextLabel}`);
  }
  for (const w of BANNED_WORDS) {
    const escaped = w.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    const re = new RegExp(`\\b${escaped}\\b`, "i");
    assert.ok(!re.test(text), `Banned trademark "${w}" found in ${contextLabel}`);
  }
  for (const bw of BANNED_BUSINESS_TERMS) {
    assert.ok(!text.includes(bw), `Legacy business term "${bw}" found in ${contextLabel}`);
  }
}

async function api(method, path, token = null, body = undefined) {
  const headers = {};
  if (token) headers["authorization"] = `Bearer ${token}`;
  if (body !== undefined) headers["content-type"] = "application/json";
  const res = await fetch(`${BASE_URL}${path}`, {
    method,
    headers,
    body: body !== undefined ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  let json = null;
  try {
    json = text ? JSON.parse(text) : null;
  } catch {
    json = text;
  }
  return { status: res.status, data: json, raw: text };
}

function connectWs(token, label) {
  return new Promise((resolve, reject) => {
    const events = [];
    const waiters = [];
    const ws = new WebSocket(`${WS_BASE_URL}/ws?token=${encodeURIComponent(token)}`);

    const timer = setTimeout(() => {
      reject(new Error(`WS connect timeout for ${label}`));
    }, 8000);

    ws.addEventListener("message", (ev) => {
      let parsed;
      try {
        parsed = JSON.parse(typeof ev.data === "string" ? ev.data : ev.data.toString());
      } catch {
        return;
      }
      events.push(parsed);
      for (let i = waiters.length - 1; i >= 0; i--) {
        if (waiters[i].pred(parsed)) {
          const w = waiters.splice(i, 1)[0];
          clearTimeout(w.timer);
          w.resolve(parsed);
        }
      }
      if (parsed.event === "connected") {
        clearTimeout(timer);
        resolve({
          ws,
          events,
          waitFor(pred, timeoutMs = 8000, desc = "ws event") {
            const existing = events.find(pred);
            if (existing) return Promise.resolve(existing);
            return new Promise((resWait, rejWait) => {
              const t = setTimeout(() => {
                rejWait(new Error(`Timeout waiting for ${desc} on ${label}`));
              }, timeoutMs);
              waiters.push({ pred, resolve: resWait, timer: t });
            });
          },
          clearEvents() {
            events.length = 0;
          },
          sendJson(obj) {
            ws.send(JSON.stringify(obj));
          },
          close() {
            try {
              ws.close();
            } catch {}
          },
        });
      }
    });

    ws.addEventListener("error", (err) => {
      clearTimeout(timer);
      reject(new Error(`WS error on ${label}: ${err?.message || "unknown"}`));
    });
  });
}

async function main() {
  console.log(`🚀 Starting BC Ai Chat 5-User Personal E2E Suite against ${BASE_URL} ...`);
  const wsClients = [];
  let tempGroupId = null;
  let demo5TestMsgId = null;
  let aiDirectMsgIds = [];
  let adminToken = null;

  try {
    // 1. Health, Theme & Personal Mini-App Branding Check
    const health = await api("GET", "/api/health");
    assert.equal(health.status, 200);
    assert.equal(health.data.status, "ok");
    assert.equal(health.data.mongodb, true);
    assert.equal(health.data.minio, true);
    record("1. Health check", "MongoDB=true, MinIO=true");

    const theme = await api("GET", "/api/settings/theme");
    assert.equal(theme.status, 200);
    assert.equal(theme.data.preset, "ban_chiang");
    record("2. Default theme preset", `preset=${theme.data.preset}`);

    const miniApps = await api("GET", "/api/mini-apps");
    assert.equal(miniApps.status, 200);
    assert.ok(Array.isArray(miniApps.data) && miniApps.data.length >= 5);
    assertCleanBranding(miniApps.raw, "/api/mini-apps");
    const appCodes = new Set(miniApps.data.map((m) => m.app_code));
    for (const expectedCode of [
      "ai_companion",
      "split_bill",
      "trip_planner",
      "gift_wishlist",
      "hangout_invite",
    ]) {
      assert.ok(appCodes.has(expectedCode), `Expected personal mini-app ${expectedCode}`);
    }
    for (const slug of [
      "ai",
      "split",
      "trip",
      "wishlist",
      "hangout",
      "leave",
      "quotation",
      "expense",
      "booking",
    ]) {
      const page = await api("GET", `/miniapp/${slug}`);
      assert.equal(page.status, 200);
      assertCleanBranding(page.raw, `/miniapp/${slug}`);
    }
    record("3. Personal Mini-apps & HTML branding audit", `${miniApps.data.length} apps clean`);

    // 2. Admin & 5 Personal Demo Accounts Login
    const adminAuth = await api("POST", "/api/auth/google", null, {
      email: "jead@bcaichat.local",
      id_token: "demo_jead",
    });
    assert.equal(adminAuth.status, 200);
    assert.equal(adminAuth.data.user.id, "user_jead");
    assert.equal(adminAuth.data.user.role, "admin");
    assert.equal(adminAuth.data.user.display_name, "ลุงจืด");
    assert.equal(adminAuth.data.user.department, "เจ้าของระบบ");
    assert.equal(adminAuth.data.user.job_title, "ผู้ดูแลระบบส่วนตัว");
    adminToken = adminAuth.data.token;

    const overview = await api("GET", "/api/admin/overview", adminToken);
    assert.equal(overview.status, 200);
    assert.ok(String(overview.data.mongo_db).startsWith("bcaichat"));
    assert.equal(overview.data.minio_bucket, "bcaichat-storage");
    assert.ok(overview.data.total_users >= 10);

    const adminUsers = await api("GET", "/api/admin/users", adminToken);
    assert.equal(adminUsers.status, 200);
    assertCleanBranding(adminUsers.raw, "/api/admin/users");

    const expectedPersonas = [
      ["ก้อง (Demo 1)", "@kong.bc", "เพื่อนสนิท", "สายเที่ยว & ถ่ายรูป"],
      ["แพร (Demo 2)", "@prae.bc", "เพื่อนสนิท", "สายคาเฟ่ & ชวนกินข้าว"],
      ["บอส (Demo 3)", "@boss.bc", "ครอบครัว", "สายแกดเจ็ต & เพลง"],
      ["มายด์ (Demo 4)", "@mind.bc", "เพื่อนสนิท", "สายดูหนัง & ซีรีส์"],
      ["ต้น (Demo 5)", "@ton.bc", "ก๊วนกีฬา", "สายวิ่ง & แคมป์ปิ้ง"],
    ];
    const demos = [];
    for (let i = 1; i <= 5; i++) {
      const [expName, expBcId, expDept, expJob] = expectedPersonas[i - 1];
      const res = await api("POST", "/api/auth/google", null, {
        email: `demo${i}@bcaichat.local`,
        id_token: `demo_${i}`,
      });
      assert.equal(res.status, 200);
      assert.equal(res.data.user.id, `user_demo${i}`);
      assert.equal(res.data.user.display_name, expName);
      assert.equal(res.data.user.bc_id, expBcId);
      assert.equal(res.data.user.department, expDept);
      assert.equal(res.data.user.job_title, expJob);
      demos.push({
        idx: i,
        id: res.data.user.id,
        name: res.data.user.display_name,
        token: res.data.token,
      });
    }
    record("4. Admin + 5 Personal Demo accounts login", demos.map((d) => d.name).join(", "));

    // Verify mutual friendships + conv_group_demo5 & conv_group_family + seeded items
    const demo1Friends = await api("GET", "/api/friends", demos[0].token);
    assert.equal(demo1Friends.status, 200);
    assertCleanBranding(demo1Friends.raw, "/api/friends");
    const friendIds = new Set(demo1Friends.data.map((f) => f.id));
    for (const target of ["user_demo2", "user_demo3", "user_demo4", "user_demo5", "user_ai", "user_official"]) {
      assert.ok(friendIds.has(target), `demo1 must have friend ${target}`);
    }

    const demo1Convs = await api("GET", "/api/conversations?folder=all", demos[0].token);
    assert.equal(demo1Convs.status, 200);
    assertCleanBranding(demo1Convs.raw, "/api/conversations?folder=all");
    assert.ok(!demo1Convs.data.some((c) => c.id === "conv_group_office"), "conv_group_office must not exist");

    const demo5Room = demo1Convs.data.find((c) => c.id === "conv_group_demo5");
    assert.ok(demo5Room, "conv_group_demo5 must exist");
    assert.equal(demo5Room.name, "แก๊งเพื่อนสนิท 5 คน + BC AI");
    assert.equal(demo5Room.folder, "group");
    assert.equal(demo5Room.member_ids.length, 6);

    const familyRoom = demo1Convs.data.find((c) => c.id === "conv_group_family");
    assert.ok(familyRoom, "conv_group_family must exist");
    assert.equal(familyRoom.name, "กลุ่มครอบครัว & เพื่อนบ้าน");
    assert.equal(familyRoom.folder, "family");

    const famFilter = await api("GET", "/api/conversations?folder=family", demos[0].token);
    assert.equal(famFilter.status, 200);
    assert.ok(famFilter.data.some((c) => c.id === "conv_group_family"), "?folder=family returns conv_group_family");

    const demo5Msgs = await api("GET", "/api/conversations/conv_group_demo5/messages", demos[0].token);
    assert.equal(demo5Msgs.status, 200);
    assertCleanBranding(demo5Msgs.raw, "conv_group_demo5 messages");
    assert.ok(
      demo5Msgs.data.some((m) => m.type === "poll" && m.poll?.question === "เสาร์นี้ไปกินข้าวร้านไหนดี?"),
      "seeded personal poll must exist in conv_group_demo5"
    );
    assert.ok(
      demo5Msgs.data.some((m) => m.type === "event" && m.event_data?.title === "นัดกินหมูกระทะ & คาเฟ่เสาร์นี้"),
      "seeded personal event must exist in conv_group_demo5"
    );

    const demo5Albums = await api("GET", "/api/conversations/conv_group_demo5/albums", demos[0].token);
    assert.equal(demo5Albums.status, 200);
    assertCleanBranding(demo5Albums.raw, "conv_group_demo5 albums");
    assert.ok(
      demo5Albums.data.some((a) => a.title === "อัลบั้มทริปเที่ยวและมื้ออร่อย"),
      "seeded personal album must exist in conv_group_demo5"
    );

    const demo5Notes = await api("GET", "/api/notes?conversation_id=conv_group_demo5", demos[0].token);
    assert.equal(demo5Notes.status, 200);
    assertCleanBranding(demo5Notes.raw, "conv_group_demo5 notes");
    assert.ok(
      demo5Notes.data.some((n) => n.title === "ลิสต์ร้านอร่อยและแผนเที่ยว"),
      "seeded personal group note must exist in conv_group_demo5"
    );

    const personalNotes = await api("GET", "/api/notes", demos[0].token);
    assert.equal(personalNotes.status, 200);
    assertCleanBranding(personalNotes.raw, "personal notebook");
    assert.ok(
      personalNotes.data.some((n) => n.title === "บันทึกส่วนตัวของฉัน — รหัส Wi-Fi บ้าน & ลิสต์หนังน่าดู"),
      "seeded personal Wi-Fi/movie notebook note must exist"
    );

    for (const seedKey of ["seed_trip_postcard.svg", "seed_weekend_trip.txt"]) {
      const seedRes = await fetch(`${BASE_URL}/api/files/${seedKey}`);
      assert.equal(seedRes.status, 200, `${seedKey} must be served from MinIO`);
    }
    record("5. Seeded personal rooms, friends, poll, event, album, notes & MinIO files verified", "conv_group_demo5 + conv_group_family");

    // 3. Connect all 5 Demo WebSockets simultaneously
    for (const d of demos) {
      const client = await connectWs(d.token, d.id);
      wsClients.push(client);
    }
    record("6. 5 simultaneous WebSocket connections active", "user_demo1..5");

    // Broadcast real-time message in conv_group_demo5 and verify all 5 receive it
    for (const c of wsClients) c.clearEvents();
    const liveText = `ทักทายแก๊งเพื่อนครบ 5 คนแบบ Real-time ${Date.now()}`;
    const sentLive = await api(
      "POST",
      "/api/conversations/conv_group_demo5/messages",
      demos[0].token,
      { type: "text", content: liveText }
    );
    assert.equal(sentLive.status, 200);
    demo5TestMsgId = sentLive.data.id;

    await Promise.all(
      wsClients.map((c, idx) =>
        c.waitFor(
          (e) => e.event === "new_message" && e.message?.id === demo5TestMsgId,
          6000,
          `new_message on demo${idx + 1}`
        )
      )
    );
    record("7. Real-time WS broadcast delivered to all 5 users", demo5TestMsgId);

    // Typing indicator over WS
    for (const c of wsClients) c.clearEvents();
    wsClients[1].sendJson({
      event: "typing",
      conversation_id: "conv_group_demo5",
    });
    await wsClients[0].waitFor(
      (e) => e.event === "typing" && e.user_id === "user_demo2" && e.conversation_id === "conv_group_demo5",
      5000,
      "typing indicator from user_demo2"
    );
    record("8. Real-time WS typing indicator verified", "user_demo2 -> user_demo1");

    // Read receipt over WS
    const readRes = await api("POST", "/api/conversations/conv_group_demo5/read", demos[2].token);
    assert.equal(readRes.status, 200);
    await wsClients[0].waitFor(
      (e) => e.event === "message_read" && e.conversation_id === "conv_group_demo5" && e.user_id === "user_demo3",
      5000,
      "message_read from user_demo3"
    );
    record("9. Real-time WS read receipt verified", "user_demo3");

    // 4. Friends favorite / block / hide
    const friendUpd = await api("PUT", "/api/friends/user_demo5", demos[0].token, {
      is_favorite: true,
      is_blocked: true,
      is_hidden: true,
    });
    assert.equal(friendUpd.status, 200);
    assert.equal(friendUpd.data.is_favorite, true);
    assert.equal(friendUpd.data.is_blocked, true);
    assert.equal(friendUpd.data.is_hidden, true);
    const friendRestore = await api("PUT", "/api/friends/user_demo5", demos[0].token, {
      is_favorite: false,
      is_blocked: false,
      is_hidden: false,
    });
    assert.equal(friendRestore.status, 200);
    assert.equal(friendRestore.data.is_blocked, false);
    record("10. Friends favorite/block/hide toggle", "PUT /api/friends/:friend_id");

    // 5. Group lifecycle: Create -> Meta -> Invite (friends + user_ai) -> Join via invite_token
    const createdGroup = await api("POST", "/api/conversations/group", demos[0].token, {
      name: "ก๊วนจัดทริปเขาใหญ่ E2E",
      member_ids: ["user_demo2", "user_demo3"],
      folder: "group",
    });
    assert.equal(createdGroup.status, 200);
    tempGroupId = createdGroup.data.id;
    const inviteToken = createdGroup.data.invite_token;
    assert.ok(typeof inviteToken === "string" && inviteToken.length >= 6);

    const metaRes = await api("PUT", `/api/conversations/${tempGroupId}/meta`, demos[0].token, {
      is_muted: true,
      is_archived: false,
      is_pinned: true,
      folder: "family",
      name: "ก๊วนจัดทริปเขาใหญ่ E2E + AI",
    });
    assert.equal(metaRes.status, 200);
    assert.equal(metaRes.data.is_muted, true);
    assert.equal(metaRes.data.is_pinned, true);
    assert.equal(metaRes.data.folder, "family");
    assert.equal(metaRes.data.name, "ก๊วนจัดทริปเขาใหญ่ E2E + AI");
    // Unmute so notifications work normally
    await api("PUT", `/api/conversations/${tempGroupId}/meta`, demos[0].token, { is_muted: false });

    for (const c of wsClients) c.clearEvents();
    const invRes = await api("POST", `/api/conversations/${tempGroupId}/members`, demos[0].token, {
      member_ids: ["user_demo4", "user_ai"],
    });
    assert.equal(invRes.status, 200);
    assert.ok(invRes.data.member_ids.includes("user_demo4"));
    assert.ok(invRes.data.member_ids.includes("user_ai"));
    await wsClients[3].waitFor(
      (e) => e.event === "conversation_updated" && e.conversation_id === tempGroupId,
      5000,
      "conversation_updated on invited user_demo4"
    );

    const joinRes = await api("POST", "/api/conversations/join", demos[4].token, {
      invite_token: inviteToken,
    });
    assert.equal(joinRes.status, 200);
    assert.equal(joinRes.data.id, tempGroupId);
    assert.equal(joinRes.data.member_ids.length, 6);
    record("11. Group create, meta, invite user_ai & join via invite_token", tempGroupId);

    // 6. @ai Mention in Group + 1-1 Direct Chat with user_ai
    for (const c of wsClients) c.clearEvents();
    const aiGroupPrompt = await api(
      "POST",
      `/api/conversations/${tempGroupId}/messages`,
      demos[0].token,
      {
        type: "text",
        content: "@ai ช่วยทักทายเพื่อนๆ ในแก๊งทริปเขาใหญ่นี้สั้นๆ 1 ประโยคครับ",
        mentions: ["user_ai"],
      }
    );
    assert.equal(aiGroupPrompt.status, 200);

    const aiWsEvent = await wsClients[4].waitFor(
      (e) =>
        e.event === "new_message" &&
        e.conversation_id === tempGroupId &&
        e.message?.sender_id === "user_ai",
      25000,
      "user_ai reply broadcast to demo5"
    );
    assertCleanBranding(aiWsEvent.message.content, "AI group reply");
    record("12. @ai group mention auto-reply over WS", aiWsEvent.message.content.slice(0, 50));

    const directAiConv = await api("POST", "/api/conversations/direct", demos[0].token, {
      friend_id: "user_ai",
    });
    assert.equal(directAiConv.status, 200);
    const aiConvId = directAiConv.data.id;
    wsClients[0].clearEvents();
    const directAiSent = await api(
      "POST",
      `/api/conversations/${aiConvId}/messages`,
      demos[0].token,
      {
        type: "text",
        content: "ช่วยแนะนำไอเดียจัดกระเป๋าไปเที่ยวเขาใหญ่เสาร์อาทิตย์สั้นๆ หน่อยครับ",
      }
    );
    assert.equal(directAiSent.status, 200);
    aiDirectMsgIds.push(directAiSent.data.id);
    const directAiReply = await wsClients[0].waitFor(
      (e) =>
        e.event === "new_message" &&
        e.conversation_id === aiConvId &&
        e.message?.sender_id === "user_ai",
      25000,
      "1-1 user_ai auto-reply"
    );
    aiDirectMsgIds.push(directAiReply.message.id);
    assertCleanBranding(directAiReply.message.content, "AI 1-1 reply");
    record("13. 1-1 direct chat with user_ai auto-reply", directAiReply.message.content.slice(0, 50));

    // AI Settings secret masking check
    const aiSettings = await api("GET", "/api/admin/ai-settings", adminToken);
    assert.equal(aiSettings.status, 200);
    assert.equal(aiSettings.data.api_key, undefined);
    assert.ok(!String(aiSettings.data.masked_key).includes("sk-"));
    assertCleanBranding(aiSettings.raw, "/api/admin/ai-settings");
    record("14. Admin AI settings secret masking", aiSettings.data.masked_key);

    // 7. MinIO Upload, Download, Audio Message, Rich Card & Confidential Instant Purge
    const filePayload = Buffer.from("แผนทริปเที่ยววันหยุดจัดเก็บถาวรบน MinIO BC Ai Chat 100%", "utf8");
    const upRes = await api("POST", "/api/upload", demos[0].token, {
      file_name: "e2e_trip_plan.txt",
      mime_type: "text/plain",
      data_base64: filePayload.toString("base64"),
      conversation_id: tempGroupId,
    });
    assert.equal(upRes.status, 200);
    const dlRes = await fetch(`${BASE_URL}/api/files/${upRes.data.key}`);
    assert.equal(dlRes.status, 200);
    const dlBytes = Buffer.from(await dlRes.arrayBuffer());
    assert.deepEqual(dlBytes, filePayload);

    const confUp = await api("POST", "/api/upload", demos[0].token, {
      file_name: "e2e_private_pin_burn.txt",
      mime_type: "text/plain",
      data_base64: Buffer.from("PRIVATE WIFI PIN BURN TEST").toString("base64"),
      conversation_id: tempGroupId,
    });
    assert.equal(confUp.status, 200);
    const confMsg = await api("POST", `/api/conversations/${tempGroupId}/messages`, demos[0].token, {
      type: "file",
      content: "ข้อความลับส่วนตัวล็อก PIN ทดสอบลบทำลาย",
      is_confidential: true,
      confidential_pin: "2580",
      attachment: confUp.data,
    });
    assert.equal(confMsg.status, 200);
    const purgeRes = await api("DELETE", `/api/messages/${confMsg.data.id}/purge`, demos[0].token);
    assert.equal(purgeRes.status, 200);
    assert.equal(purgeRes.data.file_purged, true);
    const afterPurge = await fetch(`${BASE_URL}/api/files/${confUp.data.key}`);
    assert.equal(afterPurge.status, 404);
    record("15. MinIO upload/download + confidential file instant purge (404)", confUp.data.key);

    // Clean up e2e_trip_plan.txt via confidential message purge helper so MinIO stays tidy
    const tempCleanupMsg = await api("POST", `/api/conversations/${tempGroupId}/messages`, demos[0].token, {
      type: "file",
      content: "ไฟล์ทดสอบชั่วคราว",
      attachment: upRes.data,
    });
    if (tempCleanupMsg.status === 200) {
      await api("DELETE", `/api/messages/${tempCleanupMsg.data.id}/purge`, demos[0].token);
    }

    // Audio + Mentions + Reactions + Delete-for-me
    const audioMsg = await api("POST", `/api/conversations/${tempGroupId}/messages`, demos[1].token, {
      type: "audio",
      content: "ข้อความเสียงจากแพรชวนแวะคาเฟ่",
      audio_duration_sec: 14,
      mentions: ["user_demo1", "user_demo3"],
    });
    assert.equal(audioMsg.status, 200);
    assert.equal(audioMsg.data.type, "audio");
    assert.equal(audioMsg.data.audio_duration_sec, 14);

    for (const c of wsClients) c.clearEvents();
    const reactRes = await api(
      "POST",
      `/api/messages/${audioMsg.data.id}/react`,
      demos[2].token,
      { emoji: "🎉" }
    );
    assert.equal(reactRes.status, 200);
    assert.deepEqual(reactRes.data.reactions["🎉"], ["user_demo3"]);
    await wsClients[0].waitFor(
      (e) => e.event === "message_updated" && e.message?.id === audioMsg.data.id,
      5000,
      "message_updated on reaction"
    );

    const delMe = await api(
      "POST",
      `/api/messages/${audioMsg.data.id}/delete-for-me`,
      demos[3].token
    );
    assert.equal(delMe.status, 200);
    const d4Msgs = await api("GET", `/api/conversations/${tempGroupId}/messages`, demos[3].token);
    const d1Msgs = await api("GET", `/api/conversations/${tempGroupId}/messages`, demos[0].token);
    assert.ok(!d4Msgs.data.some((m) => m.id === audioMsg.data.id), "hidden for demo4");
    assert.ok(d1Msgs.data.some((m) => m.id === audioMsg.data.id), "still visible for demo1");
    record("16. Audio message, mentions, WS reactions & delete-for-me", audioMsg.data.id);

    // 8. Polls: create, vote, WS message_updated, close-poll
    const pollCreated = await api(
      "POST",
      `/api/conversations/${tempGroupId}/polls`,
      demos[0].token,
      {
        question: "ออกเดินทางไปเขาใหญ่กี่โมงดี?",
        options: ["ล้อหมุนเช้า 07:30 น.", "สายๆ ชิลๆ 10:00 น."],
        allow_multiple: false,
        is_anonymous: false,
      }
    );
    assert.equal(pollCreated.status, 200);
    const pollId = pollCreated.data.id;
    const optA = pollCreated.data.poll.options[0].id;
    for (const c of wsClients) c.clearEvents();
    const voteRes = await api("POST", `/api/messages/${pollId}/vote`, demos[1].token, {
      option_ids: [optA],
    });
    assert.equal(voteRes.status, 200);
    assert.deepEqual(voteRes.data.poll.options[0].voter_ids, ["user_demo2"]);
    await wsClients[2].waitFor(
      (e) => e.event === "message_updated" && e.message?.id === pollId,
      5000,
      "message_updated on poll vote"
    );
    const closePoll = await api("POST", `/api/messages/${pollId}/close-poll`, demos[0].token);
    assert.equal(closePoll.status, 200);
    assert.equal(closePoll.data.poll.is_closed, true);
    record("17. Group Poll create, vote, WS sync & close-poll", pollId);

    // 9. Events: create, RSVP (going/maybe/not_going), WS sync, GET events
    const evCreated = await api(
      "POST",
      `/api/conversations/${tempGroupId}/events`,
      demos[0].token,
      {
        title: "นัดปิ้งย่างและดูดาวลานกางเต็นท์",
        description: "เตรียมเสื้อกันหนาวและเก้าอี้แคมป์ปิ้งมาด้วยนะ",
        starts_at: "2026-11-25T18:00:00Z",
        ends_at: "2026-11-25T21:30:00Z",
        location: "ลานกางเต็นท์ลำตะคอง เขาใหญ่",
      }
    );
    assert.equal(evCreated.status, 200);
    const evId = evCreated.data.id;
    await api("POST", `/api/messages/${evId}/rsvp`, demos[1].token, { status: "going" });
    await api("POST", `/api/messages/${evId}/rsvp`, demos[2].token, { status: "maybe" });
    const rsvpNotGoing = await api("POST", `/api/messages/${evId}/rsvp`, demos[4].token, {
      status: "not_going",
    });
    assert.equal(rsvpNotGoing.status, 200);
    assert.ok(rsvpNotGoing.data.event_data.going_ids.includes("user_demo2"));
    assert.ok(rsvpNotGoing.data.event_data.maybe_ids.includes("user_demo3"));
    assert.ok(rsvpNotGoing.data.event_data.not_going_ids.includes("user_demo5"));
    const evList = await api("GET", `/api/conversations/${tempGroupId}/events`, demos[0].token);
    assert.equal(evList.status, 200);
    assert.equal(evList.data.length, 1);
    record("18. Group Event create, RSVP (going/maybe/not_going) & list", evId);

    // 10. Shared Albums: create, add photos, list, delete
    const samplePhoto = {
      key: "seed_trip_postcard.svg",
      url: `${BASE_URL}/api/files/seed_trip_postcard.svg`,
      file_name: "โปสการ์ดทริปเขาใหญ่_ตัวอย่าง.svg",
      mime_type: "image/svg+xml",
      file_size: 820,
    };
    const albCreated = await api(
      "POST",
      `/api/conversations/${tempGroupId}/albums`,
      demos[0].token,
      {
        title: "อัลบั้มภาพทริปวันหยุด E2E",
        description: "เก็บรูปความทรงจำถาวรบน MinIO",
        photos: [samplePhoto],
      }
    );
    assert.equal(albCreated.status, 200);
    const albId = albCreated.data.id;
    const albAdded = await api("POST", `/api/albums/${albId}/photos`, demos[1].token, {
      photos: [{ ...samplePhoto, file_name: "รูปคาเฟ่ริมเขา_ตัวอย่าง.svg" }],
    });
    assert.equal(albAdded.status, 200);
    assert.equal(albAdded.data.photos.length, 2);
    const albDel = await api("DELETE", `/api/albums/${albId}`, demos[0].token);
    assert.equal(albDel.status, 200);
    record("19. Shared Photo Albums CRUD", albId);

    // 11. Group Notes (edit, like, comment) & Personal สมุดบันทึก BC
    const grpNote = await api("POST", "/api/notes", demos[0].token, {
      conversation_id: tempGroupId,
      title: "สรุปจุดแวะพักระหว่างทาง",
      content: "แวะกินส้มตำปากช่องตอนเที่ยงตรง",
      tags: ["ทริปเที่ยว"],
      is_pinned: true,
    });
    assert.equal(grpNote.status, 200);
    const noteId = grpNote.data.id;
    const updNote = await api("PUT", `/api/notes/${noteId}`, demos[0].token, {
      title: "สรุปจุดแวะพักระหว่างทาง (อัปเดต)",
      content: "แวะคาเฟ่ก่อนขึ้นเขาใหญ่เวลา 13:30 น.",
    });
    assert.equal(updNote.status, 200);
    assert.equal(updNote.data.title, "สรุปจุดแวะพักระหว่างทาง (อัปเดต)");
    const likeNote = await api("POST", `/api/notes/${noteId}/like`, demos[1].token);
    assert.equal(likeNote.status, 200);
    assert.deepEqual(likeNote.data.liked_by, ["user_demo2"]);
    const cmtNote = await api("POST", `/api/notes/${noteId}/comments`, demos[2].token, {
      content: "บอสเตรียมลำโพงพกพากับเพลย์ลิสต์เพลงชิลๆ เรียบร้อยครับ",
    });
    assert.equal(cmtNote.status, 200);
    assert.equal(cmtNote.data.comments.length, 1);
    await api("DELETE", `/api/notes/${noteId}`, demos[0].token);

    const memoNote = await api("POST", "/api/notes", demos[0].token, {
      title: "สมุดบันทึก BC ส่วนตัว",
      content: "เตือนความจำซื้อของฝากคุณแม่วันอาทิตย์บ่ายสาม",
      tags: ["ส่วนตัว"],
      is_pinned: false,
    });
    assert.equal(memoNote.status, 200);
    const d2MemoCheck = await api("GET", "/api/notes", demos[1].token);
    assert.ok(!d2MemoCheck.data.some((n) => n.id === memoNote.data.id), "personal memo is private");
    await api("DELETE", `/api/notes/${memoNote.data.id}`, demos[0].token);
    record("20. Group Notes (edit/like/comment) & private สมุดบันทึก BC", noteId);

    // 12. Member leave / remove cleanup
    for (let i = 4; i >= 1; i--) {
      const lv = await api(
        "DELETE",
        `/api/conversations/${tempGroupId}/members/me`,
        demos[i].token
      );
      assert.equal(lv.status, 200);
    }
    await api("DELETE", `/api/conversations/${tempGroupId}/members/user_ai`, demos[0].token);
    await api("DELETE", `/api/conversations/${tempGroupId}/members/me`, demos[0].token);
    record("21. Group leave/remove member cleanup", tempGroupId);

    // Clean up temporary messages in conv_group_demo5 & 1-1 AI chat
    if (demo5TestMsgId) {
      await api("DELETE", `/api/messages/${demo5TestMsgId}/purge`, demos[0].token);
    }
    if (adminToken) {
      for (const mid of aiDirectMsgIds) {
        await api("DELETE", `/api/messages/${mid}/purge`, adminToken);
      }
    }

    console.log(`\n🎉 ALL ${results.length}/21 E2E CHECKS PASSED 100% WITHOUT ERRORS!`);
  } finally {
    for (const c of wsClients) c.close();
  }
}

main().catch((err) => {
  console.error("\n❌ E2E FAILED:", err);
  process.exit(1);
});
