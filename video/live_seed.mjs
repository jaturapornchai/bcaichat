#!/usr/bin/env node
/**
 * BC Ai Chat — Live Seed & API Contract Reference Probe for 4K 5-Phone Video
 * Connects to http://127.0.0.1:8096, logs in demo1..demo5, inspects conv_group_demo5 + 1-1 DMs,
 * exercises text/read_count=4/sticker/PIN/unsend-purge/audio/poll/RSVP/@ai/rich_card on a clean
 * temporary group (cleaned up afterwards), and saves sanitized reference data to
 * D:\bcaichat\video\data\live_reference.json (zero tokens or secrets written).
 */

import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const OUT_FILE = path.join(__dirname, "data", "live_reference.json");
const BASE_URL = process.env.BCAICHAT_API_URL || "http://127.0.0.1:8096";
const WS_BASE_URL = BASE_URL.replace(/^http/, "ws");

const decodeB64List = (arr) => arr.map((b) => Buffer.from(b, "base64").toString("utf8"));
const BANNED_BRANDS = decodeB64List([
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
  "T3BlbkNoYXQ=",
  "T2ZmaWNpYWwgQWNjb3VudA==",
]);

const BANNED_BUSINESS_TERMS = [
  "\u0e1d\u0e48\u0e32\u0e22\u0e02\u0e32\u0e22",
  "\u0e1a\u0e31\u0e0d\u0e0a\u0e35\u0e01\u0e32\u0e23\u0e40\u0e07\u0e34\u0e19",
  "\u0e1a\u0e31\u0e0d\u0e0a\u0e35\u0e41\u0e25\u0e30\u0e01\u0e32\u0e23\u0e40\u0e07\u0e34\u0e19",
  "\u0e04\u0e25\u0e31\u0e07\u0e2a\u0e34\u0e19\u0e04\u0e49\u0e32",
  "\u0e14\u0e39\u0e41\u0e25\u0e25\u0e39\u0e01\u0e04\u0e49\u0e32",
  "\u0e08\u0e31\u0e14\u0e0b\u0e37\u0e49\u0e2d",
  "\u0e2d\u0e19\u0e38\u0e21\u0e31\u0e15\u0e34\u0e43\u0e1a\u0e25\u0e32",
  "\u0e2d\u0e2d\u0e01\u0e43\u0e1a\u0e40\u0e2a\u0e19\u0e2d\u0e23\u0e32\u0e04\u0e32",
  "\u0e43\u0e1a\u0e40\u0e2a\u0e19\u0e2d\u0e23\u0e32\u0e04\u0e32",
  "\u0e43\u0e1a\u0e01\u0e33\u0e01\u0e31\u0e1a\u0e20\u0e32\u0e29\u0e35",
  "\u0e42\u0e2d\u0e19\u0e22\u0e49\u0e32\u0e22\u0e07\u0e32\u0e19",
  "\u0e41\u0e0a\u0e17\u0e2d\u0e07\u0e04\u0e4c\u0e01\u0e23",
  "\u0e04\u0e27\u0e32\u0e21\u0e25\u0e31\u0e1a\u0e2d\u0e07\u0e04\u0e4c\u0e01\u0e23",
  "\u0e1e\u0e19\u0e31\u0e01\u0e07\u0e32\u0e19\u0e2d\u0e07\u0e04\u0e4c\u0e01\u0e23",
];

function assertCleanText(text, label) {
  for (const brand of BANNED_BRANDS) {
    const escaped = brand.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    const re = new RegExp(`\\b${escaped}\\b`, "i");
    assert.ok(!re.test(text), `Forbidden brand "${brand}" detected in ${label}`);
  }
  for (const term of BANNED_BUSINESS_TERMS) {
    assert.ok(!text.includes(term), `Forbidden legacy business term detected in ${label}`);
  }
}

function sanitizeNode(value) {
  if (Array.isArray(value)) return value.map(sanitizeNode);
  if (value && typeof value === "object") {
    const out = {};
    for (const [k, v] of Object.entries(value)) {
      if (k === "token" || k === "invite_token" || k === "api_key" || k === "secret" || k === "flex_payload") {
        continue;
      }
      out[k] = sanitizeNode(v);
    }
    return out;
  }
  return value;
}

async function api(method, urlPath, token = null, body = undefined) {
  const headers = {};
  if (token) headers["authorization"] = `Bearer ${token}`;
  if (body !== undefined) headers["content-type"] = "application/json";
  const res = await fetch(`${BASE_URL}${urlPath}`, {
    method,
    headers,
    body: body !== undefined ? JSON.stringify(body) : undefined,
  });
  const raw = await res.text();
  let data = null;
  try {
    data = raw ? JSON.parse(raw) : null;
  } catch {
    data = raw;
  }
  return { status: res.status, data, raw };
}

function connectWs(token, label) {
  return new Promise((resolve, reject) => {
    const events = [];
    const waiters = [];
    const ws = new WebSocket(`${WS_BASE_URL}/ws?token=${encodeURIComponent(token)}`);
    const timer = setTimeout(() => reject(new Error(`WS connect timeout (${label})`)), 8000);

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
          waitFor(pred, timeoutMs = 15000, desc = "ws event") {
            const hit = events.find(pred);
            if (hit) return Promise.resolve(hit);
            return new Promise((resWait, rejWait) => {
              const t = setTimeout(() => rejWait(new Error(`Timeout waiting for ${desc}`)), timeoutMs);
              waiters.push({ pred, resolve: resWait, timer: t });
            });
          },
          clear() {
            events.length = 0;
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
      reject(new Error(`WS error (${label}): ${err?.message || "unknown"}`));
    });
  });
}

async function main() {
  console.log(`[live_seed] Probing live backend at ${BASE_URL} ...`);
  const health = await api("GET", "/api/health");
  assert.equal(health.status, 200);
  assert.equal(health.data.status, "ok");
  assert.equal(health.data.mongodb, true);
  assert.equal(health.data.minio, true);

  const themeRes = await api("GET", "/api/settings/theme");
  assert.equal(themeRes.status, 200);

  const miniAppsRes = await api("GET", "/api/mini-apps");
  assert.equal(miniAppsRes.status, 200);

  const phoneSlots = ["kong", "prae", "boss", "mind", "ton"];
  const demos = [];
  for (let i = 1; i <= 5; i++) {
    const auth = await api("POST", "/api/auth/google", null, {
      email: `demo${i}@bcaichat.local`,
      id_token: `demo_${i}`,
    });
    assert.equal(auth.status, 200, `Login failed for demo${i}`);
    demos.push({
      slot: phoneSlots[i - 1],
      idx: i,
      user: auth.data.user,
      token: auth.data.token,
    });
  }

  // Inspect main seeded group conv_group_demo5 & personal notes
  const convsRes = await api("GET", "/api/conversations?folder=all", demos[0].token);
  assert.equal(convsRes.status, 200);
  const groupDemo5 = convsRes.data.find((c) => c.id === "conv_group_demo5");
  assert.ok(groupDemo5, "conv_group_demo5 must exist");

  const groupMsgsRes = await api("GET", "/api/conversations/conv_group_demo5/messages", demos[0].token);
  assert.equal(groupMsgsRes.status, 200);

  const groupAlbumsRes = await api("GET", "/api/conversations/conv_group_demo5/albums", demos[0].token);
  assert.equal(groupAlbumsRes.status, 200);

  const groupNotesRes = await api("GET", "/api/notes?conversation_id=conv_group_demo5", demos[0].token);
  assert.equal(groupNotesRes.status, 200);

  const mindPersonalNotesRes = await api("GET", "/api/notes", demos[3].token);
  assert.equal(mindPersonalNotesRes.status, 200);

  // Open/verify 1-on-1 DM rooms: kong <-> prae, boss <-> ton, mind <-> user_ai
  const dmKongPrae = await api("POST", "/api/conversations/direct", demos[0].token, {
    friend_id: "user_demo2",
  });
  assert.equal(dmKongPrae.status, 200);

  const dmBossTon = await api("POST", "/api/conversations/direct", demos[2].token, {
    friend_id: "user_demo5",
  });
  assert.equal(dmBossTon.status, 200);

  const dmMindAi = await api("POST", "/api/conversations/direct", demos[3].token, {
    friend_id: "user_ai",
  });
  assert.equal(dmMindAi.status, 200);

  // Exercise temporary live room for message structures (cleaned up in finally)
  let tempRoomId = null;
  const wsKong = await connectWs(demos[0].token, "kong");
  const samplePayloads = {};

  try {
    const createdGroup = await api("POST", "/api/conversations/group", demos[0].token, {
      name: "ห้องจำลองสัญญาข้อมูลวิดีโอเขาใหญ่",
      member_ids: ["user_demo2", "user_demo3", "user_demo4", "user_demo5", "user_ai"],
      folder: "group",
    });
    assert.equal(createdGroup.status, 200);
    tempRoomId = createdGroup.data.id;

    // 1. Text + read_count = 4
    const textMsg = await api("POST", `/api/conversations/${tempRoomId}/messages`, demos[0].token, {
      type: "text",
      content: "พร้อมลุยทริปเขาใหญ่เสาร์อาทิตย์นี้กันหรือยังทุกคน!",
    });
    assert.equal(textMsg.status, 200);
    for (let i = 1; i <= 4; i++) {
      await api("POST", `/api/conversations/${tempRoomId}/read`, demos[i].token);
    }
    const checkMsgs = await api("GET", `/api/conversations/${tempRoomId}/messages`, demos[0].token);
    samplePayloads.textWithRead4 = checkMsgs.data.find((m) => m.id === textMsg.data.id);

    // 2. Sticker
    const stickerMsg = await api("POST", `/api/conversations/${tempRoomId}/messages`, demos[1].token, {
      type: "sticker",
      content: "สติกเกอร์อารมณ์ดีดินเผาไทย: ชนแก้วพร้อมลุย",
      sticker_code: "clay_cheers",
    });
    assert.equal(stickerMsg.status, 200);
    samplePayloads.sticker = stickerMsg.data;

    // 3. Confidential PIN + Unsend Purge
    const pinMsg = await api("POST", `/api/conversations/${tempRoomId}/messages`, demos[1].token, {
      type: "text",
      content: "[ลับส่วนตัว] หุ้นซื้อเค้กวันเกิดเซอร์ไพรส์บอส เก็บความลับด้วยนะ!",
      is_confidential: true,
      confidential_pin: "2580",
    });
    assert.equal(pinMsg.status, 200);
    samplePayloads.secretPin = pinMsg.data;

    const typoMsg = await api("POST", `/api/conversations/${tempRoomId}/messages`, demos[0].token, {
      type: "text",
      content: "เผลอพิมพ์ผิด เดี๋ยวบอสรู้แผนเค้ก!",
    });
    assert.equal(typoMsg.status, 200);
    const purgeRes = await api("DELETE", `/api/messages/${typoMsg.data.id}/purge`, demos[0].token);
    assert.equal(purgeRes.status, 200);
    samplePayloads.unsendPurgeResult = purgeRes.data;

    // 4. Audio voice note
    const voiceMsg = await api("POST", `/api/conversations/${tempRoomId}/messages`, demos[4].token, {
      type: "audio",
      content: "ข้อความเสียงจากต้น: ลมบนจุดกางเต็นท์เย็นสบายมาก เตรียมเสื้อคลุมมาด้วย",
      audio_duration_sec: 12,
    });
    assert.equal(voiceMsg.status, 200);
    samplePayloads.voiceNote = voiceMsg.data;

    // 5. Poll + all 5 votes
    const pollMsg = await api("POST", `/api/conversations/${tempRoomId}/polls`, demos[0].token, {
      question: "คืนวันเสาร์พักโซนไหนดีที่เขาใหญ่?",
      options: ["ลานกางเต็นท์วิวเขา ดูดาวเต็มฟ้า", "บ้านพักพูลวิลล่า ปิ้งย่างส่วนตัว"],
      allow_multiple: false,
      is_anonymous: false,
    });
    assert.equal(pollMsg.status, 200);
    const opt0 = pollMsg.data.poll.options[0].id;
    const opt1 = pollMsg.data.poll.options[1].id;
    await api("POST", `/api/messages/${pollMsg.data.id}/vote`, demos[0].token, { option_ids: [opt0] });
    await api("POST", `/api/messages/${pollMsg.data.id}/vote`, demos[4].token, { option_ids: [opt0] });
    await api("POST", `/api/messages/${pollMsg.data.id}/vote`, demos[2].token, { option_ids: [opt0] });
    await api("POST", `/api/messages/${pollMsg.data.id}/vote`, demos[1].token, { option_ids: [opt1] });
    const finalVote = await api("POST", `/api/messages/${pollMsg.data.id}/vote`, demos[3].token, {
      option_ids: [opt0],
    });
    assert.equal(finalVote.status, 200);
    samplePayloads.pollVoted = finalVote.data;

    // 6. Event RSVP
    const eventMsg = await api("POST", `/api/conversations/${tempRoomId}/events`, demos[0].token, {
      title: "ทริปเขาใหญ่ 2 วัน 1 คืน แก๊งเพื่อน 5 คน",
      description: "ล้อหมุนเสาร์ 07:30 น. แวะคาเฟ่ + กางเต็นท์ดูดาว",
      starts_at: "2026-11-21T07:30:00Z",
      ends_at: "2026-11-22T18:00:00Z",
      location: "อุทยานแห่งชาติเขาใหญ่ ลานลำตะคอง",
    });
    assert.equal(eventMsg.status, 200);
    let latestRsvp = null;
    for (let i = 0; i < 5; i++) {
      const r = await api("POST", `/api/messages/${eventMsg.data.id}/rsvp`, demos[i].token, {
        status: "going",
      });
      latestRsvp = r.data;
    }
    samplePayloads.eventRsvp = latestRsvp;

    // 7. Interactive Rich Card (หารค่าข้าวกับเพื่อน)
    const richCardMsg = await api("POST", `/api/conversations/${tempRoomId}/messages`, demos[1].token, {
      type: "rich_card",
      content: "การ์ดโต้ตอบ: หารค่าข้าวและค่าทริปเขาใหญ่ 5 คน",
      card_payload: {
        card_type: "split_bill",
        title: "หารค่าข้าว & เสบียงปิ้งย่างเขาใหญ่",
        total_amount: "2,450 บาท",
        per_person: "490 บาท / คน",
        participants_count: 5,
        status: "คำนวณครบ 5 คนอัตโนมัติ",
      },
    });
    assert.equal(richCardMsg.status, 200);
    samplePayloads.richCard = richCardMsg.data;

    // 8. @ai group mention auto-reply
    wsKong.clear();
    const aiAsk = await api("POST", `/api/conversations/${tempRoomId}/messages`, demos[3].token, {
      type: "text",
      content: "@ai ช่วยสรุปแพลนเที่ยวเขาใหญ่ 2 วัน 1 คืน สำหรับเพื่อนสนิท 5 คน แบบกระชับ 2 บรรทัดหน่อยจ้า",
      mentions: ["user_ai"],
    });
    assert.equal(aiAsk.status, 200);
    const aiWs = await wsKong.waitFor(
      (e) =>
        e.event === "new_message" &&
        e.conversation_id === tempRoomId &&
        e.message?.sender_id === "user_ai",
      25000,
      "AI reply in temp group"
    );
    samplePayloads.aiReply = aiWs.message;
  } finally {
    wsKong.close();
    if (tempRoomId) {
      // Purge all temporary messages and leave room so DB stays spotless
      const allTempMsgs = await api("GET", `/api/conversations/${tempRoomId}/messages`, demos[0].token);
      if (allTempMsgs.status === 200 && Array.isArray(allTempMsgs.data)) {
        for (const m of allTempMsgs.data) {
          if (m.sender_id !== "user_ai") {
            const owner = demos.find((d) => d.user.id === m.sender_id) || demos[0];
            await api("DELETE", `/api/messages/${m.id}/purge`, owner.token);
          }
        }
      }
      for (let i = 4; i >= 1; i--) {
        await api("DELETE", `/api/conversations/${tempRoomId}/members/me`, demos[i].token);
      }
      await api("DELETE", `/api/conversations/${tempRoomId}/members/user_ai`, demos[0].token);
      await api("DELETE", `/api/conversations/${tempRoomId}/members/me`, demos[0].token);
    }
  }

  const referenceDoc = sanitizeNode({
    generatedAt: new Date().toISOString(),
    backendEndpoint: BASE_URL,
    health: health.data,
    defaultTheme: themeRes.data,
    supportedThemes: [
      "ban_chiang",
      "silk_amber",
      "indigo_kram",
      "jade_celadon",
      "lotus_rose",
      "spice_cinnamon",
      "royal_amethyst",
    ],
    supportedRoomTones: ["ban_chiang_cream", "terracotta_night", "ivory_white"],
    personas: demos.map((d) => ({
      slot: d.slot,
      idx: d.idx,
      user: d.user,
    })),
    miniApps: miniAppsRes.data,
    rooms: {
      groupDemo5: {
        conversation: groupDemo5,
        seededMessageCount: groupMsgsRes.data.length,
        seededAlbums: groupAlbumsRes.data,
        seededGroupNotes: groupNotesRes.data,
      },
      dmKongPrae: dmKongPrae.data,
      dmBossTon: dmBossTon.data,
      dmMindAi: dmMindAi.data,
      mindPersonalNotes: mindPersonalNotesRes.data,
    },
    verifiedLiveContracts: samplePayloads,
  });

  const serialized = JSON.stringify(referenceDoc, null, 2);
  assertCleanText(serialized, "live_reference.json");
  assert.ok(!serialized.includes("eyJ"), "JWT must not appear in live_reference.json");

  fs.mkdirSync(path.dirname(OUT_FILE), { recursive: true });
  fs.writeFileSync(OUT_FILE, serialized, "utf8");
  console.log(`[live_seed] Saved clean reference to ${OUT_FILE} (${Buffer.byteLength(serialized)} bytes)`);
}

main().catch((err) => {
  console.error("[live_seed] FAILED:", err.message || err);
  process.exit(1);
});
