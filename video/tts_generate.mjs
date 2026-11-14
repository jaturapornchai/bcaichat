#!/usr/bin/env node
/**
 * BC Ai Chat — ElevenLabs Thai TTS (`eleven_v4`) + Original Clay SFX + Timeline + SRT + YouTube Metadata
 *
 * Security Iron Rule:
 * - Reads ElevenLabs API key ONLY at runtime from process.env.ELEVENLABS_API_KEY, root `.env`, or process.env.ELEVENLABS_KEY_FILE
 * - NEVER logs, prints, or writes the key anywhere.
 */

import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const SCRIPT_PATH = path.join(__dirname, "script.json");
const CACHE_DIR = path.join(__dirname, "cache");
const DATA_DIR = path.join(__dirname, "data");
const OUTPUT_DIR = path.join(__dirname, "output");

const TIMELINE_OUT = path.join(DATA_DIR, "timeline.json");
const VOICE_WAV_OUT = path.join(DATA_DIR, "voice_master.wav");
const SFX_WAV_OUT = path.join(DATA_DIR, "sfx_master.wav");
const SRT_OUT = path.join(OUTPUT_DIR, "subtitles_th.srt");
const YOUTUBE_OUT = path.join(__dirname, "youtube.md");

const SAMPLE_RATE = 48000;

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
  "B2B",
  "ERP",
  "บัญชีบริษัท",
  "พนักงานบริษัท",
  "ฝ่ายขาย",
  "บัญชีการเงิน",
  "บัญชีและการเงิน",
  "คลังสินค้า",
  "ดูแลลูกค้า",
  "จัดซื้อ",
  "อนุมัติใบลา",
  "ออกใบเสนอราคา",
  "ใบเสนอราคา",
  "ใบกำกับภาษี",
  "โอนย้ายงาน",
  "แชทองค์กร",
  "ความลับองค์กร",
  "สื่อสารองค์กร",
  "พนักงานองค์กร",
  "เรื่องงาน",
  "งานด่วน",
];

function assertZeroForbiddenContent(text, contextLabel, secretKey) {
  if (secretKey && secretKey.length >= 8) {
    assert.ok(!text.includes(secretKey), `CRITICAL: Secret leaked in ${contextLabel}`);
  }
  assert.ok(!/\bsk[-_][A-Za-z0-9]{12,}/.test(text), `Potential secret token found in ${contextLabel}`);
  assert.ok(!/\bAIza[0-9A-Za-z_-]{20,}/.test(text), `Potential API key found in ${contextLabel}`);
  for (const brand of BANNED_BRANDS) {
    const escaped = brand.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    const re = new RegExp(`\\b${escaped}\\b`, "i");
    assert.ok(!re.test(text), `Forbidden brand "${brand}" found in ${contextLabel}`);
  }
  assert.ok(!/\bKeep\b/.test(text), `Forbidden word "Keep" found in ${contextLabel}`);
  for (const term of BANNED_BUSINESS_TERMS) {
    assert.ok(!text.includes(term), `Forbidden business term "${term}" found in ${contextLabel}`);
  }
}

function loadElevenLabsKey() {
  const fromEnv = process.env.ELEVENLABS_API_KEY?.trim();
  if (fromEnv) return fromEnv;

  const envPath = path.resolve(__dirname, "..", ".env");
  if (fs.existsSync(envPath)) {
    for (const rawLine of fs.readFileSync(envPath, "utf8").split(/\r?\n/)) {
      const m = rawLine.match(/^\s*ELEVENLABS_API_KEY\s*=\s*(.+?)\s*$/);
      if (m && m[1]) {
        const cleaned = m[1].replace(/^["']|["']$/g, "").trim();
        if (cleaned && !cleaned.startsWith("your_")) return cleaned;
      }
    }
  }

  const keyFile = process.env.ELEVENLABS_KEY_FILE?.trim();
  if (keyFile && fs.existsSync(keyFile)) {
    const key = fs.readFileSync(keyFile, "utf8").trim();
    if (key) return key;
  }

  throw new Error(
    "ELEVENLABS_API_KEY is missing. Set ELEVENLABS_API_KEY in environment or root .env (or ELEVENLABS_KEY_FILE)."
  );
}

function parseRubyMarkup(rawText) {
  const displayText = rawText.replace(/\{([^|{}]+)\|([^{}]+)\}/g, "$1").replace(/\s+/g, " ").trim();
  const ttsText = rawText.replace(/\{([^|{}]+)\|([^{}]+)\}/g, "$2").replace(/\s+/g, " ").trim();
  assert.ok(!displayText.includes("{") && !displayText.includes("}"), `Unclosed brace in displayText: ${rawText}`);
  assert.ok(!ttsText.includes("{") && !ttsText.includes("}"), `Unclosed brace in ttsText: ${rawText}`);
  return { displayText, ttsText };
}

function polishPcm16Mono(rawBuf) {
  const evenLen = rawBuf.length - (rawBuf.length % 2);
  const totalSamples = evenLen / 2;
  if (totalSamples === 0) {
    throw new Error("Empty PCM buffer returned from TTS");
  }

  const samples = new Int16Array(totalSamples);
  for (let i = 0; i < totalSamples; i++) {
    samples[i] = rawBuf.readInt16LE(i * 2);
  }

  const threshold = 160;
  let firstActive = 0;
  while (firstActive < totalSamples && Math.abs(samples[firstActive]) < threshold) {
    firstActive++;
  }
  let lastActive = totalSamples - 1;
  while (lastActive > firstActive && Math.abs(samples[lastActive]) < threshold) {
    lastActive--;
  }

  const leadPad = Math.round(0.022 * SAMPLE_RATE);
  const tailPad = Math.round(0.055 * SAMPLE_RATE);
  const startIdx = Math.max(0, firstActive - leadPad);
  const endIdx = Math.min(totalSamples, lastActive + tailPad + 1);
  const sliced = samples.slice(startIdx, Math.max(startIdx + 1, endIdx));

  const fadeSamples = Math.min(Math.round(0.01 * SAMPLE_RATE), Math.floor(sliced.length / 4));
  for (let i = 0; i < fadeSamples; i++) {
    const gain = 0.5 * (1 - Math.cos((Math.PI * i) / fadeSamples));
    sliced[i] = Math.round(sliced[i] * gain);
    const tailPos = sliced.length - 1 - i;
    sliced[tailPos] = Math.round(sliced[tailPos] * gain);
  }

  const outBuf = Buffer.allocUnsafe(sliced.length * 2);
  for (let i = 0; i < sliced.length; i++) {
    outBuf.writeInt16LE(sliced[i], i * 2);
  }
  return outBuf;
}

async function synthesizeLineElevenLabs({
  apiKey,
  lineId,
  voiceId,
  ttsText,
  modelId,
  languageCode,
  voiceSettings,
}) {
  fs.mkdirSync(CACHE_DIR, { recursive: true });
  const cachePayload = JSON.stringify({
    provider: "elevenlabs_with_timestamps_pcm48k_v2",
    modelId,
    languageCode,
    voiceId,
    voiceSettings,
    ttsText,
  });
  const sha1 = crypto.createHash("sha1").update(cachePayload, "utf8").digest("hex");
  const pcmCachePath = path.join(CACHE_DIR, `${sha1}.pcm`);
  const metaCachePath = path.join(CACHE_DIR, `${sha1}.meta.json`);

  if (fs.existsSync(pcmCachePath) && fs.existsSync(metaCachePath)) {
    const pcm = fs.readFileSync(pcmCachePath);
    const meta = JSON.parse(fs.readFileSync(metaCachePath, "utf8"));
    if (pcm.length >= 4800) {
      return { pcm, meta, cached: true, sha1 };
    }
  }

  const url = `https://api.elevenlabs.io/v1/text-to-speech/${encodeURIComponent(voiceId)}/with-timestamps?output_format=pcm_48000`;
  const body = JSON.stringify({
    text: ttsText,
    model_id: modelId,
    language_code: languageCode,
    voice_settings: voiceSettings,
  });

  let lastStatus = 0;
  let lastErrMsg = "";
  for (let attempt = 1; attempt <= 4; attempt++) {
    const res = await fetch(url, {
      method: "POST",
      headers: {
        "xi-api-key": apiKey,
        "content-type": "application/json",
      },
      body,
    });
    lastStatus = res.status;

    if (res.status === 200) {
      const json = await res.json();
      if (!json || typeof json.audio_base64 !== "string" || json.audio_base64.length === 0) {
        throw new Error(`ElevenLabs returned empty audio_base64 for ${lineId}`);
      }
      const rawPcm = Buffer.from(json.audio_base64, "base64");
      const polishedPcm = polishPcm16Mono(rawPcm);
      const durationSec = Number((polishedPcm.length / 2 / SAMPLE_RATE).toFixed(4));
      const meta = {
        lineId,
        sha1,
        voiceId,
        modelId,
        languageCode,
        sampleRate: SAMPLE_RATE,
        samples: polishedPcm.length / 2,
        durationSec,
        characterCount: ttsText.length,
        hasAlignment: Boolean(json.alignment),
        generatedAt: new Date().toISOString(),
      };
      fs.writeFileSync(pcmCachePath, polishedPcm);
      fs.writeFileSync(metaCachePath, JSON.stringify(meta, null, 2), "utf8");
      return { pcm: polishedPcm, meta, cached: false, sha1 };
    }

    const errText = await res.text().catch(() => "");
    lastErrMsg = errText.slice(0, 220).replace(/\bsk[-_][A-Za-z0-9_-]+/g, "[REDACTED]");
    if (res.status === 429 || res.status >= 500) {
      await new Promise((r) => setTimeout(r, 1200 * attempt));
      continue;
    }
    break;
  }

  throw new Error(`ElevenLabs TTS failed for ${lineId} (HTTP ${lastStatus}): ${lastErrMsg}`);
}

function writeWavMono16(filePath, floatSamples) {
  const numSamples = floatSamples.length;
  const dataSize = numSamples * 2;
  const header = Buffer.alloc(44);
  header.write("RIFF", 0);
  header.writeUInt32LE(36 + dataSize, 4);
  header.write("WAVE", 8);
  header.write("fmt ", 12);
  header.writeUInt32LE(16, 16);
  header.writeUInt16LE(1, 20);
  header.writeUInt16LE(1, 22);
  header.writeUInt32LE(SAMPLE_RATE, 24);
  header.writeUInt32LE(SAMPLE_RATE * 2, 28);
  header.writeUInt16LE(2, 32);
  header.writeUInt16LE(16, 34);
  header.write("data", 36);
  header.writeUInt32LE(dataSize, 40);

  const pcmBuf = Buffer.allocUnsafe(dataSize);
  let peak = 0;
  let sumSq = 0;
  for (let i = 0; i < numSamples; i++) {
    const clamped = Math.max(-0.98, Math.min(0.98, floatSamples[i]));
    const absV = Math.abs(clamped);
    if (absV > peak) peak = absV;
    sumSq += clamped * clamped;
    pcmBuf.writeInt16LE(Math.round(clamped * 32767), i * 2);
  }

  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, Buffer.concat([header, pcmBuf]));
  const rms = Math.sqrt(sumSq / Math.max(1, numSamples));
  return { bytes: 44 + dataSize, samples: numSamples, peak, rms };
}

function addToneSweep(mix, atSec, durSec, fStart, fEnd, amp = 0.08) {
  const startSample = Math.max(0, Math.round(atSec * SAMPLE_RATE));
  const len = Math.round(durSec * SAMPLE_RATE);
  let phase = 0;
  for (let i = 0; i < len; i++) {
    const idx = startSample + i;
    if (idx >= mix.length) break;
    const p = i / len;
    const freq = fStart + (fEnd - fStart) * p;
    phase += (2 * Math.PI * freq) / SAMPLE_RATE;
    const env = Math.sin(Math.PI * Math.pow(p, 0.72)) * Math.exp(-2.6 * p);
    mix[idx] += Math.sin(phase) * amp * env;
  }
}

function addClayBellNote(mix, atSec, durSec, freq, amp = 0.075) {
  const startSample = Math.max(0, Math.round(atSec * SAMPLE_RATE));
  const len = Math.round(durSec * SAMPLE_RATE);
  for (let i = 0; i < len; i++) {
    const idx = startSample + i;
    if (idx >= mix.length) break;
    const t = i / SAMPLE_RATE;
    const attack = Math.min(1, i / (0.008 * SAMPLE_RATE));
    const decay = Math.exp(-4.2 * (t / durSec) * 1.4);
    const wave =
      0.72 * Math.sin(2 * Math.PI * freq * t) +
      0.20 * Math.sin(2 * Math.PI * freq * 2.0 * t) * Math.exp(-3.0 * t) +
      0.08 * Math.sin(2 * Math.PI * freq * 2.98 * t) * Math.exp(-6.0 * t);
    mix[idx] += wave * amp * attack * decay;
  }
}

function addClayChimeArpeggio(mix, atSec, notesHz, stepSec = 0.09, noteDur = 0.65, amp = 0.068) {
  notesHz.forEach((hz, idx) => {
    addClayBellNote(mix, atSec + idx * stepSec, noteDur, hz, amp);
  });
}

function buildUiEvents(linesById) {
  const r3 = (n) => Number(n.toFixed(3));
  const L = (id) => {
    const found = linesById.get(id);
    assert.ok(found, `Missing line ${id}`);
    return found;
  };

  const l01 = L("L01");
  const l02 = L("L02");
  const l03 = L("L03");
  const l04 = L("L04");
  const l05 = L("L05");
  const l06 = L("L06");
  const l07 = L("L07");
  const l08 = L("L08");
  const l09 = L("L09");
  const l10 = L("L10");
  const l11 = L("L11");
  const l12 = L("L12");
  const l13 = L("L13");
  const l14 = L("L14");
  const l15 = L("L15");
  const l16 = L("L16");
  const l17 = L("L17");
  const l18 = L("L18");
  const l19 = L("L19");
  const l20 = L("L20");
  const l21 = L("L21");
  const l22 = L("L22");
  const l23 = L("L23");
  const l24 = L("L24");
  const l25 = L("L25");
  const l26 = L("L26");
  const l27 = L("L27");
  const l28 = L("L28");
  const l29 = L("L29");

  const allGroup = ["kong", "prae", "boss", "mind", "ton"];
  const pairKongPrae = ["kong", "prae"];
  const pairBossTon = ["boss", "ton"];

  const events = [
    // Scene 1: group_open
    {
      id: "ev_01_group_hello",
      at: r3(l01.start + 0.25),
      scene: "group_open",
      room: "group",
      participants: allGroup,
      sender: "kong",
      senderName: "ก้อง",
      kind: "text",
      type: "text",
      clock: "09:41",
      text: "ลองเปิด BC Ai Chat ธีมบ้านเชียงดูสิ มี 4 แท็บหลัก สะอาดตาสุดๆ 🏺✨",
      readSteps: [
        { at: r3(l01.start + 0.75), count: 1 },
        { at: r3(l01.start + 1.15), count: 2 },
        { at: r3(l01.start + 1.55), count: 3 },
        { at: r3(l01.start + 1.95), count: 4 },
      ],
    },
    {
      id: "ev_02_folder_chips",
      at: r3(l02.start + 0.28),
      scene: "group_open",
      room: "group",
      participants: allGroup,
      sender: "prae",
      senderName: "แพร",
      kind: "text",
      type: "text",
      clock: "09:41",
      text: "แถบโฟลเดอร์ ส่วนตัว • ครอบครัว • กลุ่ม เลื่อนลื่นมาก ไม่มีป๊อปอัปบังจอเลย!",
      readSteps: [
        { at: r3(l02.start + 0.85), count: 2 },
        { at: r3(l02.start + 1.45), count: 4 },
      ],
    },
    {
      id: "ev_03_sync_read4",
      at: r3(l03.start + 0.25),
      scene: "group_open",
      room: "group",
      participants: allGroup,
      sender: "boss",
      senderName: "บอส",
      kind: "text",
      type: "text",
      clock: "09:42",
      text: "ซิงค์ไวจริง! ส่งปุ๊บเด้งครบ 5 เครื่อง ขึ้น อ่านแล้ว 4 ทันใจ ⚡",
      readSteps: [{ at: r3(l03.start + 0.75), count: 4 }],
    },
    {
      id: "ev_04_sticker_wave",
      at: r3(l04.start + 0.35),
      scene: "group_open",
      room: "group",
      participants: allGroup,
      sender: "mind",
      senderName: "มายด์",
      kind: "sticker",
      type: "sticker",
      clock: "09:42",
      stickerId: "clay_wave",
      stickerCode: "clay_wave",
      label: "ทักทายจ้า!",
      text: "สติกเกอร์ดินเผาโบกมือทักทายทริปเขาใหญ่",
      readSteps: [{ at: r3(l04.start + 0.90), count: 4 }],
    },
    {
      id: "ev_05_sticker_cheers",
      at: r3(l05.start + 0.35),
      scene: "group_open",
      room: "group",
      participants: allGroup,
      sender: "ton",
      senderName: "ต้น",
      kind: "sticker",
      type: "sticker",
      clock: "09:42",
      stickerId: "clay_cheers",
      stickerCode: "clay_cheers",
      label: "ชนแก้วลุยเขาใหญ่!",
      text: "สติกเกอร์ดินเผาชนแก้วฉลองทริปเขาใหญ่",
      readSteps: [{ at: r3(l05.start + 0.90), count: 4 }],
    },

    // Scene 2: dm_kong_prae + Mind's personal notebook
    {
      id: "ev_06_mind_notebook",
      at: r3(l06.start),
      until: r3(l10.end + 0.26),
      scene: "dm_kong_prae",
      room: "notes",
      participants: ["mind"],
      phone: "mind",
      sender: "mind",
      senderName: "มายด์",
      kind: "notebook_focus",
      type: "notebook_focus",
      clock: "09:44",
      notes: [
        {
          title: "เช็กลิสต์จัดกระเป๋าทริปเขาใหญ่",
          items: [
            { done: true, text: "เสื้อกันหนาว & หมวกไหมพรม" },
            { done: true, text: "กล้องฟิล์ม & แบตเตอรี่สำรอง" },
            { done: false, text: "ขนมกองกลางไว้กินบนรถ" },
          ],
          badge: "สมุดบันทึก BC • เก็บถาวรไม่หมดอายุ",
        },
        {
          title: "ลิสต์หนัง & ซีรีส์ดูวันหยุด",
          items: [
            { done: true, text: "หนังอบอุ่นหัวใจดูริมเต็นท์" },
            { done: false, text: "รหัส Wi-Fi บ้านเก็บไว้ส่วนตัว" },
          ],
          badge: "ส่วนตัวเฉพาะฉัน",
        },
      ],
    },
    {
      id: "ev_06_dm_surprise",
      at: r3(l06.start + 0.26),
      scene: "dm_kong_prae",
      room: "dm_kong_prae",
      participants: pairKongPrae,
      sender: "prae",
      senderName: "แพร",
      kind: "text",
      type: "text",
      clock: "09:44",
      text: "ก้อง เสาร์นี้วันเกิดบอสพอดี แอบสั่งเค้กไปเซอร์ไพรส์กันไหม 🤫🎂",
      readSteps: [{ at: r3(l06.start + 0.85), count: 1 }],
    },
    {
      id: "ev_07_dm_request_pin",
      at: r3(l07.start + 0.26),
      scene: "dm_kong_prae",
      room: "dm_kong_prae",
      participants: pairKongPrae,
      sender: "kong",
      senderName: "ก้อง",
      kind: "text",
      type: "text",
      clock: "09:44",
      text: "เอาสิแพร! ส่งแผนมาแบบ [ลับส่วนตัว] ล็อกรหัส PIN เลย 🔐",
      readSteps: [{ at: r3(l07.start + 0.85), count: 1 }],
    },
    {
      id: "ev_08_secret_pin",
      at: r3(l08.start + 0.22),
      unlockAt: r3(l08.start + Math.min(2.05, l08.duration * 0.44)),
      scene: "dm_kong_prae",
      room: "dm_kong_prae",
      participants: pairKongPrae,
      sender: "prae",
      senderName: "แพร",
      kind: "secret_pin",
      type: "secret_pin",
      clock: "09:45",
      pin: "2580",
      previewLabel: "[ลับส่วนตัว] ล็อกรหัส PIN",
      unlockedText: "🎂 สั่งเค้กช็อกโกแลตลาวาร้านโปรดบอส ซ่อนไว้ท้ายรถก้อง ตอนสองทุ่มจุดเทียนเลย!",
      text: "[ลับส่วนตัว] สั่งเค้กช็อกโกแลตลาวาเซอร์ไพรส์บอส",
      readSteps: [{ at: r3(l08.start + 0.80), count: 1 }],
    },
    {
      id: "ev_09_unsend_vanish",
      at: r3(l09.start + 0.20),
      unsendAt: r3(l09.start + Math.min(2.15, l09.duration * 0.46)),
      scene: "dm_kong_prae",
      room: "dm_kong_prae",
      participants: pairKongPrae,
      sender: "kong",
      senderName: "ก้อง",
      kind: "unsend_demo",
      type: "unsend_demo",
      clock: "09:45",
      text: "อ้าวเผลอพิมพ์ชื่อร้านเค้กหน้าปากช่องผิดช่อง!",
    },

    // Scene 3: dm_boss_ton
    {
      id: "ev_11_dm_camp_query",
      at: r3(l11.start + 0.26),
      scene: "dm_boss_ton",
      room: "dm_boss_ton",
      participants: pairBossTon,
      sender: "boss",
      senderName: "บอส",
      kind: "text",
      type: "text",
      clock: "09:47",
      text: "ต้น จุดกางเต็นท์เขาใหญ่เป็นไงบ้าง ส่งมาให้ดูที ⛺",
      readSteps: [{ at: r3(l11.start + 0.85), count: 1 }],
    },
    {
      id: "ev_12_voice_note",
      at: r3(l12.start + 0.22),
      scene: "dm_boss_ton",
      room: "dm_boss_ton",
      participants: pairBossTon,
      sender: "ton",
      senderName: "ต้น",
      kind: "voice",
      type: "voice",
      clock: "09:47",
      durationSec: 12,
      waveform: [6, 12, 17, 11, 18, 9, 15, 19, 13, 8, 16, 11, 14, 7],
      caption: "ลมเย็นสบาย ลานหญ้าริมน้ำกว้างมาก",
      text: "ข้อความเสียงจากต้น",
      readSteps: [{ at: r3(l12.start + 0.80), count: 1 }],
    },
    {
      id: "ev_12_photo_4k",
      at: r3(l12.start + Math.min(1.65, l12.duration * 0.44)),
      scene: "dm_boss_ton",
      room: "dm_boss_ton",
      participants: pairBossTon,
      sender: "ton",
      senderName: "ต้น",
      kind: "photo",
      type: "photo",
      clock: "09:48",
      title: "วิวจุดกางเต็นท์ลำตะคอง_4K.jpg",
      resolution: "4K ต้นฉบับ • ไม่บีบอัด",
      permanentBadge: "เก็บถาวร • ไม่หมดอายุ",
      syncBadges: ["มือถือ", "คอม", "เว็บ"],
      text: "รูปภาพ 4K ต้นฉบับไม่บีบอัด",
      readSteps: [{ at: r3(l12.start + Math.min(2.25, l12.duration * 0.65)), count: 1 }],
    },
    {
      id: "ev_13_pdf_permanent",
      at: r3(l13.start + 0.26),
      scene: "dm_boss_ton",
      room: "dm_boss_ton",
      participants: pairBossTon,
      sender: "ton",
      senderName: "ต้น",
      kind: "file",
      type: "file",
      clock: "09:48",
      fileName: "แผนที่จุดกางเต็นท์เขาใหญ่.pdf",
      fileSize: "4.8 MB",
      mime: "PDF",
      permanentBadge: "เก็บถาวร • ไม่หมดอายุ",
      syncBadges: ["มือถือ", "คอม", "เว็บ"],
      text: "ไฟล์ PDF แผนที่จุดกางเต็นท์เขาใหญ่",
      readSteps: [{ at: r3(l13.start + 0.85), count: 1 }],
    },
    {
      id: "ev_14_sync_multi_device",
      at: r3(l14.start + 0.26),
      scene: "dm_boss_ton",
      room: "dm_boss_ton",
      participants: pairBossTon,
      sender: "boss",
      senderName: "บอส",
      kind: "text",
      type: "text",
      clock: "09:49",
      text: "เจ๋งเลย! เปิดดูต่อบนคอมและเว็บได้ทันที ซิงค์ครบทุกเครื่อง 💻📱",
      readSteps: [{ at: r3(l14.start + 0.85), count: 1 }],
    },

    // Scene 4: group_ai_poll
    {
      id: "ev_15_ai_mention",
      at: r3(l15.start + 0.28),
      scene: "group_ai_poll",
      room: "group",
      participants: allGroup,
      sender: "mind",
      senderName: "มายด์",
      kind: "ai_prompt",
      type: "ai_prompt",
      clock: "09:50",
      text: "@ai ช่วยจัดแพลนทริปเขาใหญ่ 2 วัน 1 คืน ให้แก๊งเพื่อน 5 คนหน่อยจ้า 🌲✨",
      readSteps: [{ at: r3(l15.start + 0.90), count: 4 }],
    },
    {
      id: "ev_16_ai_plan_reply",
      at: r3(l16.start + 0.14),
      scene: "group_ai_poll",
      room: "group",
      participants: allGroup,
      sender: "ai",
      senderName: "🤖 BC AI",
      kind: "ai_reply",
      type: "ai_reply",
      clock: "09:50",
      text: "แพลนทริปเขาใหญ่ 2 วัน 1 คืนพร้อมแล้วค่ะ:",
      highlights: [
        "วัน 1: แวะคาเฟ่วิวเขา • กางเต็นท์ดูดาวลำตะคอง",
        "วัน 2: ชมน้ำตกเหวสุวัต • แวะซื้อของฝากกลับบ้าน",
      ],
      directHint: "ทักแชท 1-ต่อ-1 กับ @bc.ai ได้ตลอดเวลา",
    },
    {
      id: "ev_17_ai_direct_tip",
      at: r3(l17.start + 0.16),
      scene: "group_ai_poll",
      room: "group",
      participants: allGroup,
      sender: "ai",
      senderName: "🤖 BC AI",
      kind: "ai_reply",
      type: "ai_reply",
      clock: "09:51",
      text: "อยากจัดลิสต์ของใช้ส่วนตัว ทักหา @bc.ai แบบตัวต่อตัวได้เลยนะคะ",
      highlights: ["ช่วยจัดเช็กลิสต์ของใช้ & แนะนำร้านอร่อยส่วนตัว"],
      directHint: "พร้อมดูแลทั้งในกลุ่มและแชท 1-ต่อ-1",
    },
    {
      id: "ev_18_poll_stay",
      at: r3(l18.start + 0.35),
      scene: "group_ai_poll",
      room: "group",
      participants: allGroup,
      sender: "kong",
      senderName: "ก้อง",
      kind: "poll",
      type: "poll",
      clock: "09:52",
      question: "คืนวันเสาร์พักโซนไหนดีที่เขาใหญ่?",
      options: [
        {
          id: "opt_camp",
          text: "⛺ ลานกางเต็นท์ดูดาวริมน้ำ",
          votesTimeline: [
            { at: r3(l18.start + 1.15), voters: ["kong"] },
            { at: r3(l19.start + 0.25), voters: ["kong", "ton"] },
            { at: r3(l19.start + 0.95), voters: ["kong", "ton", "boss"] },
            { at: r3(l19.start + 1.85), voters: ["kong", "ton", "boss", "mind"] },
          ],
        },
        {
          id: "opt_villa",
          text: "🏡 รีสอร์ทใกล้คาเฟ่วิวเขา",
          votesTimeline: [{ at: r3(l19.start + 1.40), voters: ["prae"] }],
        },
      ],
      text: "โพลโหวตที่พักเขาใหญ่",
      readSteps: [{ at: r3(l18.start + 1.00), count: 4 }],
    },
    {
      id: "ev_18_rsvp_card",
      at: r3(l18.start + Math.min(2.10, l18.duration * 0.55)),
      scene: "group_ai_poll",
      room: "group",
      participants: allGroup,
      sender: "kong",
      senderName: "ก้อง",
      kind: "rsvp",
      type: "rsvp",
      clock: "09:52",
      title: "นัดล้อหมุนทริปเขาใหญ่ 2 วัน 1 คืน",
      timeLabel: "เสาร์ 07:30 น.",
      location: "จุดนัดพบคาเฟ่ปากช่อง",
      rsvpTimeline: [
        { at: r3(l18.end - 0.35), going: ["kong"], maybe: [] },
        { at: r3(l19.start + 0.55), going: ["kong", "ton"], maybe: [] },
        { at: r3(l19.start + 1.25), going: ["kong", "ton", "prae"], maybe: [] },
        { at: r3(l19.start + 1.95), going: ["kong", "ton", "prae", "boss"], maybe: [] },
        { at: r3(l19.start + 2.55), going: ["kong", "ton", "prae", "boss", "mind"], maybe: [] },
      ],
      text: "การ์ดนัดหมายล้อหมุนเสาร์ 07:30 น.",
      readSteps: [{ at: r3(l18.end - 0.15), count: 4 }],
    },
    {
      id: "ev_20_album_notes",
      at: r3(l20.start + 0.28),
      scene: "group_ai_poll",
      room: "group",
      participants: allGroup,
      sender: "mind",
      senderName: "มายด์",
      kind: "album",
      type: "album",
      clock: "09:54",
      title: "อัลบั้มภาพทริปเขาใหญ่ & ร้านเด็ด",
      photoCount: 18,
      noteTitle: "ปักหมุดโน้ตกลุ่ม: พิกัดร้านอร่อยปากช่อง",
      permanentBadge: "เก็บถาวร • ไม่หมดอายุ",
      text: "อัลบั้มรูปทริปเขาใหญ่ & โน้ตกลุ่มถาวร",
      readSteps: [{ at: r3(l20.start + 0.90), count: 4 }],
    },

    // Scene 5: group_miniapp_theme
    {
      id: "ev_21_rich_split_bill",
      at: r3(l21.start + 0.30),
      scene: "group_miniapp_theme",
      room: "group",
      participants: allGroup,
      sender: "prae",
      senderName: "แพร",
      kind: "rich_card",
      type: "rich_card",
      cardType: "split_bill",
      clock: "09:55",
      title: "หารค่าข้าวกับเพื่อน • ทริปเขาใหญ่",
      subtitle: "ยอดรวม 1,850 บาท (หาร 5 คนเท่ากัน)",
      totalLabel: "คนละ 370 บาท",
      perPersonLabel: "ครบ 5/5 คน",
      items: [
        { label: "ชุดปิ้งย่าง & อาหารเย็น", amount: "1,150 ฿" },
        { label: "เครื่องดื่ม & ขนมคาเฟ่", amount: "450 ฿" },
        { label: "ค่าธรรมเนียมกางเต็นท์", amount: "250 ฿" },
      ],
      text: "การ์ดโต้ตอบหารค่าข้าวกับเพื่อน 1,850 บาท",
      readSteps: [{ at: r3(l21.start + 0.95), count: 4 }],
    },
    {
      id: "ev_22_rich_trip_planner",
      at: r3(l22.start + 0.35),
      scene: "group_miniapp_theme",
      room: "group",
      participants: allGroup,
      sender: "kong",
      senderName: "ก้อง",
      kind: "rich_card",
      type: "rich_card",
      cardType: "trip_planner",
      clock: "09:56",
      title: "จัดทริปเที่ยว • เขาใหญ่ 2 วัน 1 คืน",
      subtitle: "ตารางทริป & งบกองกลางโปร่งใส",
      totalLabel: "งบคนละ 370 ฿ เป๊ะ!",
      perPersonLabel: "พร้อมเดินทาง",
      items: [
        { label: "เสาร์ 07:30 น.", amount: "แวะคาเฟ่ปากช่อง" },
        { label: "เสาร์ 14:00 น.", amount: "กางเต็นท์ลำตะคอง" },
        { label: "อาทิตย์ 10:30 น.", amount: "น้ำตก & ของฝาก" },
      ],
      text: "การ์ดโต้ตอบจัดทริปเที่ยวเขาใหญ่",
      readSteps: [{ at: r3(l22.start + 0.95), count: 4 }],
    },
    {
      id: "ev_23_theme_indigo",
      at: r3(l23.start + Math.min(1.30, l23.duration * 0.30)),
      scene: "group_miniapp_theme",
      room: "group",
      participants: allGroup,
      sender: "boss",
      senderName: "บอส",
      kind: "theme_change",
      type: "theme_change",
      theme: "indigo_kram",
      roomTone: "ban_chiang_cream",
      label: "ครามสุโขทัย",
    },
    {
      id: "ev_23_theme_celadon",
      at: r3(l23.start + Math.min(2.35, l23.duration * 0.54)),
      scene: "group_miniapp_theme",
      room: "group",
      participants: allGroup,
      sender: "boss",
      senderName: "บอส",
      kind: "theme_change",
      type: "theme_change",
      theme: "jade_celadon",
      roomTone: "ban_chiang_cream",
      label: "หยกสังคโลก",
    },
    {
      id: "ev_23_theme_amber",
      at: r3(l23.start + Math.min(3.35, l23.duration * 0.76)),
      scene: "group_miniapp_theme",
      room: "group",
      participants: allGroup,
      sender: "boss",
      senderName: "บอส",
      kind: "theme_change",
      type: "theme_change",
      theme: "silk_amber",
      roomTone: "ban_chiang_cream",
      label: "ไหมทองอำพัน",
    },
    {
      id: "ev_24_tone_night",
      at: r3(l24.start + 0.15),
      scene: "group_miniapp_theme",
      room: "group",
      participants: allGroup,
      sender: "ton",
      senderName: "ต้น",
      kind: "theme_change",
      type: "theme_change",
      theme: "ban_chiang",
      roomTone: "terracotta_night",
      label: "โทนมืดดินเผา",
    },
    {
      id: "ev_24_tone_cream_morning",
      at: r3(l24.start + Math.max(2.20, l24.duration * 0.58)),
      scene: "group_miniapp_theme",
      room: "group",
      participants: allGroup,
      sender: "ton",
      senderName: "ต้น",
      kind: "theme_change",
      type: "theme_change",
      theme: "ban_chiang",
      roomTone: "ban_chiang_cream",
      label: "โทนครีมบ้านเชียง",
    },

    // Scene 6: recap_outro
    {
      id: "ev_25_recap_kong",
      at: r3(l25.start + 0.25),
      scene: "recap_outro",
      room: "group",
      participants: allGroup,
      sender: "kong",
      senderName: "ก้อง",
      kind: "text",
      type: "text",
      clock: "09:58",
      text: "แชทไว สะอาดตา + ยกเลิกไร้ร่องรอยได้จริง 👍",
      readSteps: [{ at: r3(l25.start + 0.85), count: 4 }],
    },
    {
      id: "ev_26_recap_prae",
      at: r3(l26.start + 0.25),
      scene: "recap_outro",
      room: "group",
      participants: allGroup,
      sender: "prae",
      senderName: "แพร",
      kind: "text",
      type: "text",
      clock: "09:58",
      text: "ล็อก PIN ลับ + การ์ดหารค่าข้าว โพล & นัดหมาย 💛",
      readSteps: [{ at: r3(l26.start + 0.85), count: 4 }],
    },
    {
      id: "ev_27_recap_boss",
      at: r3(l27.start + 0.25),
      scene: "recap_outro",
      room: "group",
      participants: allGroup,
      sender: "boss",
      senderName: "บอส",
      kind: "text",
      type: "text",
      clock: "09:59",
      text: "ซิงค์ครบ มือถือ คอม เว็บ + 7 ธีมไทย & โทนมืด ✨",
      readSteps: [{ at: r3(l27.start + 0.85), count: 4 }],
    },
    {
      id: "ev_28_recap_mind",
      at: r3(l28.start + 0.28),
      scene: "recap_outro",
      room: "group",
      participants: allGroup,
      sender: "mind",
      senderName: "มายด์",
      kind: "sticker",
      type: "sticker",
      clock: "09:59",
      stickerId: "clay_love",
      stickerCode: "clay_love",
      label: "รักเลย BC Ai Chat!",
      text: "ผู้ช่วย AI ส่วนตัว & สมุดบันทึก BC สุดน่ารัก",
      readSteps: [{ at: r3(l28.start + 0.85), count: 4 }],
    },
    {
      id: "ev_29_recap_ton",
      at: r3(l29.start + 0.28),
      scene: "recap_outro",
      room: "group",
      participants: allGroup,
      sender: "ton",
      senderName: "ต้น",
      kind: "sticker",
      type: "sticker",
      clock: "10:00",
      stickerId: "clay_ok",
      stickerCode: "clay_ok",
      label: "โอเคจัดไป!",
      text: "รูป 4K & ไฟล์ถาวรไม่หมดอายุ • BC Ai Chat",
      readSteps: [{ at: r3(l29.start + 0.85), count: 4 }],
    },
  ];

  events.sort((a, b) => a.at - b.at);
  return events;
}

function synthesizeMasterSfx(totalSamples, chapters, lines, uiEvents, outroStart) {
  const sfx = new Float32Array(totalSamples);

  // 1. Intro opening warm Thai pentatonic clay chime
  addClayChimeArpeggio(sfx, 0.18, [523.25, 587.33, 659.25, 783.99, 1046.5], 0.11, 0.95, 0.075);

  // 2. Gentle transition chime on each chapter start
  for (const ch of chapters) {
    if (ch.id === "intro") continue;
    if (ch.id === "outro") {
      addClayChimeArpeggio(sfx, outroStart + 0.08, [523.25, 659.25, 783.99, 1046.5], 0.10, 0.90, 0.072);
    } else if (ch.mode === "dm") {
      addClayChimeArpeggio(sfx, ch.start - 0.10, [587.33, 783.99], 0.09, 0.55, 0.052);
    } else {
      addClayChimeArpeggio(sfx, ch.start - 0.10, [523.25, 659.25, 783.99], 0.08, 0.55, 0.052);
    }
  }

  // 3. UI Event gentle pops, PIN unlock sparkle, Unsend air-whoosh, AI chime & theme shimmer
  for (const ev of uiEvents) {
    if (ev.kind === "notebook_focus") continue;
    if (ev.kind === "ai_reply") {
      addClayChimeArpeggio(sfx, ev.at - 0.04, [659.25, 783.99, 987.77], 0.065, 0.48, 0.055);
    } else if (ev.kind === "theme_change") {
      addClayChimeArpeggio(sfx, ev.at, [587.33, 739.99, 880.0], 0.06, 0.42, 0.048);
    } else if (ev.kind === "poll" || ev.kind === "rsvp" || ev.kind === "rich_card" || ev.kind === "album") {
      addToneSweep(sfx, ev.at, 0.055, 460, 740, 0.055);
      addClayBellNote(sfx, ev.at + 0.03, 0.28, 783.99, 0.042);
    } else {
      addToneSweep(sfx, ev.at, 0.045, 510, 770, 0.050);
    }

    if (typeof ev.unlockAt === "number") {
      addClayChimeArpeggio(sfx, ev.unlockAt, [659.25, 880.0], 0.07, 0.36, 0.055);
    }
    if (typeof ev.unsendAt === "number") {
      addToneSweep(sfx, ev.unsendAt, 0.11, 640, 230, 0.060);
    }
    if (Array.isArray(ev.options)) {
      for (const opt of ev.options) {
        for (const vt of opt.votesTimeline || []) {
          addToneSweep(sfx, vt.at, 0.032, 620, 820, 0.032);
        }
      }
    }
    if (Array.isArray(ev.rsvpTimeline)) {
      for (const rt of ev.rsvpTimeline) {
        addToneSweep(sfx, rt.at, 0.030, 660, 860, 0.030);
      }
    }
  }

  return sfx;
}

function formatSrtTimestamp(seconds) {
  const totalMs = Math.max(0, Math.round(seconds * 1000));
  const hrs = Math.floor(totalMs / 3600000);
  const mins = Math.floor((totalMs % 3600000) / 60000);
  const secs = Math.floor((totalMs % 60000) / 1000);
  const ms = totalMs % 1000;
  const pad2 = (n) => String(n).padStart(2, "0");
  const pad3 = (n) => String(n).padStart(3, "0");
  return `${pad2(hrs)}:${pad2(mins)}:${pad2(secs)},${pad3(ms)}`;
}

function formatYoutubeChapterTime(seconds) {
  const whole = Math.max(0, Math.floor(seconds));
  const mins = Math.floor(whole / 60);
  const secs = whole % 60;
  return `${mins}:${String(secs).padStart(2, "0")}`;
}

function generateSrt(lines) {
  return (
    lines
      .map((line, idx) => {
        const startStr = formatSrtTimestamp(line.start);
        const endStr = formatSrtTimestamp(line.end);
        return `${idx + 1}\n${startStr} --> ${endStr}\n[${line.speakerName}] ${line.displayText}\n`;
      })
      .join("\n") + "\n"
  );
}

function generateYoutubeMarkdown(timeline) {
  const totalMins = Math.floor(timeline.totalDuration / 60);
  const totalSecs = String(Math.round(timeline.totalDuration % 60)).padStart(2, "0");
  const chapterLines = timeline.chapters
    .map((ch) => `${formatYoutubeChapterTime(ch.start)} ${ch.title}`)
    .join("\n");

  return `# YouTube Metadata — BC Ai Chat (4K UHD • 5 มือถือคุยพร้อมกันจริง)

- **ความละเอียดวิดีโอ:** \`3840x2160\` (4K UHD • 30fps)
- **ความยาวรวม:** \`${totalMins}:${totalSecs}\` (\`${timeline.totalDuration.toFixed(2)}s\`, บทสนทนา \`${timeline.lines.length}\` บรรทัด)
- **เสียงพากย์:** ElevenLabs \`eleven_v4\` (\`language_code: "th"\`) แยกเสียง 6 คาแรกเตอร์ (ก้อง, แพร, บอส, มายด์, ต้น และ 🤖 BC AI ผู้ช่วยส่วนตัว) + เสียงเอฟเฟกต์ระฆังดินเผาต้นฉบับ

---

## 5 ตัวเลือกชื่อคลิป YouTube (Title Options)

1. **BC Ai Chat แอปแชทส่วนตัวคนไทย ธีมบ้านเชียง — ทดสอบ 5 มือถือคุยสดพร้อมกัน 4K! (ไฟล์ไม่หมดอายุ + ผู้ช่วย AI ส่วนตัว)**
2. **ลองของจริง BC Ai Chat แชทแก๊งเพื่อน & ครอบครัว ไร้ป๊อปอัปบังจอ ล็อกรหัส PIN ยกเลิกไร้ร่องรอย เก็บรูป 4K ถาวร!**
3. **5 มือถือแชทสดพร้อมกันบน BC Ai Chat! เรียก @ai จัดทริปเขาใหญ่ โพลโหวตสด หารค่าข้าวอัตโนมัติในหน้าแชทเดียว**
4. **เปิดตัว BC Ai Chat แชทส่วนตัว Mobile-First 7 ธีมไทยร่วมสมัย & โทนมืดดินเผาสบายตา ซิงค์ครบ มือถือ คอม เว็บ (4K)**
5. **เมื่อแก๊งเพื่อน 5 คนวางแผนเที่ยวเขาใหญ่ใน BC Ai Chat — จากแชทลับล็อก PIN สู่การ์ดโต้ตอบ & ผู้ช่วย AI ส่วนตัว!**

---

## คำอธิบายใต้คลิป (YouTube Description)

สัมผัสการทำงานจริงของ **BC Ai Chat** แอปแชทส่วนตัวสำหรับเพื่อนสนิท ครอบครัว และชีวิตประจำวันของคนไทย ถ่ายทอดผ่านหน้าจอมือถือทั้ง 5 เครื่องที่พูดคุยโต้ตอบกันแบบเรียลไทม์ระดับ **4K UHD** ในเอกลักษณ์ **ธีมบ้านเชียง** แสนอบอุ่น

### จุดเด่นและความสามารถครบจบใน BC Ai Chat
- **Mobile-First สะอาดตา ไร้ป๊อปอัปบังจอ:** จัดวางเพียง 4 แท็บหลัก (\`เพื่อน\`, \`แชท\`, \`สมุดบันทึก\`, \`ตั้งค่า\`) พร้อมแถบโฟลเดอร์เลื่อนแนวนอน (\`ส่วนตัว\`, \`ครอบครัว\`, \`กลุ่ม\`, \`ปักหมุด\`) และถาดเครื่องมือแบบ Inline ไม่เด้งป๊อปอัปซ้อนรกตา
- **ซิงค์สดเสี้ยววินาที & สติกเกอร์ต้นฉบับ:** ส่งข้อความและชุดสติกเกอร์ **อารมณ์ดีดินเผาไทย** เด้งพร้อมกันทุกเครื่อง แสดงสถานะ \`อ่านแล้ว\` แม่นยำ
- **ความเป็นส่วนตัวขั้นสุด:** ส่งข้อความ \`[ลับส่วนตัว]\` ล็อกรหัส **PIN** เปิดอ่านได้เฉพาะคนรู้รหัส พร้อมฟีเจอร์ **ยกเลิกข้อความแบบไร้ร่องรอย** ไม่ทิ้งป้ายแจ้งเตือนค้างให้สงสัย
- **สมุดบันทึก BC ส่วนตัว & คลังไฟล์ถาวรไม่หมดอายุ:** จดเช็กลิสต์ส่วนตัว ส่งข้อความเสียง รูปภาพชัดระดับ **4K ต้นฉบับไม่บีบอัด** และไฟล์ **PDF** เก็บถาวร ไม่ถูกลบทิ้งกลางคัน ซิงค์ดูต่อได้ทั้งบนมือถือ คอมพิวเตอร์ และหน้าเว็บ
- **🤖 ผู้ช่วย AI ส่วนตัว (\`@bc.ai\`):** พิมพ์เรียก \`@ai\` ในห้องกลุ่มเพื่อช่วยจัดแพลนทริป สรุปไอเดีย หรือทักแชทส่วนตัว 1-ต่อ-1 กับผู้ช่วย AI ส่วนตัวได้ตลอดเวลา
- **กิจกรรมกลุ่มครบมือ:** สร้าง **โพลโหวตสด**, ส่ง **การ์ดนัดหมาย RSVP**, แชร์ **อัลบั้มรูปทริป** และปักหมุด **โน้ตกลุ่มถาวร**
- **การ์ดโต้ตอบส่วนตัว:** คำนวณยอด **หารค่าข้าวกับเพื่อน** (\`1,850 บาท ÷ 5 = คนละ 370 บาท\`) และ **จัดทริปเที่ยว** ให้อัตโนมัติ โปร่งใสดูง่ายในใบเดียว
- **7 ธีมไทยร่วมสมัย & โทนมืดดินเผา:** สลับสีสันธีมไทย (\`บ้านเชียง\`, \`ครามสุโขทัย\`, \`หยกสังคโลก\`, \`ไหมทองอำพัน\` และอีกมากมาย) พร้อม **โทนมืดดินเผา** ที่ถนอมสายตาเวลาแชทตอนกลางคืน

---

## สารบัญช่วงเวลา (YouTube Chapters)

\`\`\`text
${chapterLines}
\`\`\`

---

## แท็กแนะนำ (Tags)

\`BC Ai Chat\`, \`แอปแชทคนไทย\`, \`แชทส่วนตัว\`, \`แชทครอบครัว\`, \`แชทแก๊งเพื่อน\`, \`ผู้ช่วย AI ส่วนตัว\`, \`ธีมบ้านเชียง\`, \`สมุดบันทึก BC\`, \`การ์ดโต้ตอบ\`, \`อารมณ์ดีดินเผาไทย\`, \`หารค่าข้าวกับเพื่อน\`, \`จัดทริปเที่ยว\`, \`เก็บไฟล์ถาวรไม่หมดอายุ\`, \`ส่งรูปไม่บีบอัด\`, \`แชทล็อกรหัส PIN\`, \`ยกเลิกข้อความไร้ร่องรอย\`, \`Mobile First UI\`, \`4K Demo\`
`;
}

async function main() {
  const apiKey = loadElevenLabsKey();
  const scriptRaw = fs.readFileSync(SCRIPT_PATH, "utf8");
  assertZeroForbiddenContent(scriptRaw, "video/script.json", apiKey);
  const script = JSON.parse(scriptRaw);

  const speakerMap = new Map();
  for (const p of script.phones) {
    speakerMap.set(p.id, p);
  }
  speakerMap.set(script.aiSpeaker.id, script.aiSpeaker);

  const sceneMap = new Map();
  for (const s of script.scenes) {
    sceneMap.set(s.id, s);
  }

  console.log(`[tts_generate] Synthesizing ${script.lines.length} Thai lines with ElevenLabs (${script.modelId}, lang=${script.languageCode}) ...`);

  const preparedJobs = script.lines.map((item, idx) => {
    const sp = speakerMap.get(item.speaker);
    assert.ok(sp, `Unknown speaker "${item.speaker}" at ${item.id}`);
    const sc = sceneMap.get(item.scene);
    assert.ok(sc, `Unknown scene "${item.scene}" at ${item.id}`);
    const { displayText, ttsText } = parseRubyMarkup(item.text);
    assertZeroForbiddenContent(displayText, `${item.id}.displayText`, apiKey);
    assertZeroForbiddenContent(ttsText, `${item.id}.ttsText`, apiKey);
    return { idx, item, sp, sc, displayText, ttsText };
  });

  const synthResults = new Array(preparedJobs.length);
  let nextJobIdx = 0;
  const workerCount = 3;

  async function worker() {
    while (true) {
      const current = nextJobIdx++;
      if (current >= preparedJobs.length) return;
      const job = preparedJobs[current];
      const res = await synthesizeLineElevenLabs({
        apiKey,
        lineId: job.item.id,
        voiceId: job.sp.voiceId,
        ttsText: job.ttsText,
        modelId: script.modelId,
        languageCode: script.languageCode,
        voiceSettings: script.voiceSettings,
      });
      synthResults[current] = res;
      console.log(
        `  [${job.item.id}] ${job.sp.name.padEnd(10)} ${res.meta.durationSec.toFixed(2)}s (${res.cached ? "cache" : "elevenlabs"})`
      );
    }
  }

  await Promise.all(Array.from({ length: workerCount }, () => worker()));

  const fps = script.fps || 30;
  const introDuration = Number(script.introDuration || 4.2);
  const outroDuration = Number(script.outroDuration || 5.5);
  const lineGapSec = Number(script.lineGapSec || 0.28);

  let cursor = introDuration;
  const timelineLines = [];
  const linesById = new Map();

  for (let i = 0; i < preparedJobs.length; i++) {
    const { item, sp, sc, displayText, ttsText } = preparedJobs[i];
    const { pcm } = synthResults[i];
    const duration = pcm.length / 2 / SAMPLE_RATE;
    const start = cursor;
    const end = start + duration;

    const defaultScreenMode = {
      kong: "chat",
      prae: "chat",
      boss: "chat",
      mind: "chat",
      ton: "chat",
    };
    const screenMode = item.screenMode ? { ...defaultScreenMode, ...item.screenMode } : defaultScreenMode;
    const activeTab = {
      kong: screenMode.kong === "notes" ? "notes" : "chats",
      prae: screenMode.prae === "notes" ? "notes" : "chats",
      boss: screenMode.boss === "notes" ? "notes" : "chats",
      mind: screenMode.mind === "notes" ? "notes" : "chats",
      ton: screenMode.ton === "notes" ? "notes" : "chats",
    };

    const lineRecord = {
      index: i,
      id: item.id,
      scene: item.scene,
      mode: sc.mode,
      dmPair: sc.dmPair || null,
      speaker: item.speaker,
      speakerName: sp.name,
      speakerFullName: sp.fullName,
      voiceId: sp.voiceId,
      start: Number(start.toFixed(4)),
      end: Number(end.toFixed(4)),
      duration: Number(duration.toFixed(4)),
      displayText,
      ttsText,
      rawText: item.text,
      theme: item.theme || "ban_chiang",
      roomTone: item.roomTone || "ban_chiang_cream",
      activeFolderChip: item.activeFolderChip || "group",
      featurePill: item.featurePill || sc.featurePill,
      screenMode,
      activeTab,
      inlineTray: item.inlineTray || null,
    };

    timelineLines.push(lineRecord);
    linesById.set(item.id, lineRecord);
    cursor = end + lineGapSec;
  }

  const outroStart = Number(cursor.toFixed(4));
  const rawTotalDuration = outroStart + outroDuration;
  const totalFrames = Math.ceil(rawTotalDuration * fps);
  const totalDuration = Number((totalFrames / fps).toFixed(4));

  const chapters = [
    {
      id: "intro",
      title: "เปิดตัว BC Ai Chat แชทส่วนตัวธีมบ้านเชียง",
      mode: "intro",
      dmPair: null,
      start: 0,
      end: Number(introDuration.toFixed(4)),
      headerBadge: script.scenes[0].headerBadge,
      featurePill: script.scenes[0].featurePill,
    },
  ];

  for (const sc of script.scenes) {
    if (sc.id === "intro") continue;
    const scLines = timelineLines.filter((l) => l.scene === sc.id);
    assert.ok(scLines.length > 0, `Scene ${sc.id} has no lines`);
    const chStart = scLines[0].start;
    const lastIdx = scLines[scLines.length - 1].index;
    const chEnd =
      lastIdx + 1 < timelineLines.length ? timelineLines[lastIdx + 1].start : outroStart;
    chapters.push({
      id: sc.id,
      title: sc.title,
      mode: sc.mode,
      dmPair: sc.dmPair || null,
      start: Number(chStart.toFixed(4)),
      end: Number(chEnd.toFixed(4)),
      headerBadge: sc.headerBadge,
      featurePill: sc.featurePill,
    });
  }

  chapters.push({
    id: "outro",
    title: "สรุป 8 ความสามารถเด่นของ BC Ai Chat",
    mode: "outro",
    dmPair: null,
    start: outroStart,
    end: totalDuration,
    headerBadge: "✨ สรุปครบ 8 ความสามารถเด่นของ BC Ai Chat",
    featurePill: "BC Ai Chat • แชทส่วนตัวของคนไทย",
  });

  const uiEvents = buildUiEvents(linesById);

  const totalSamples = Math.round(totalDuration * SAMPLE_RATE);
  const voiceFloat = new Float32Array(totalSamples);

  for (let i = 0; i < timelineLines.length; i++) {
    const line = timelineLines[i];
    const pcm = synthResults[i].pcm;
    const sampleOffset = Math.round(line.start * SAMPLE_RATE);
    const numSamples = pcm.length / 2;
    for (let s = 0; s < numSamples; s++) {
      const dst = sampleOffset + s;
      if (dst >= totalSamples) break;
      voiceFloat[dst] += (pcm.readInt16LE(s * 2) / 32768) * 0.88;
    }
  }

  const sfxFloat = synthesizeMasterSfx(totalSamples, chapters, timelineLines, uiEvents, outroStart);

  const voiceStats = writeWavMono16(VOICE_WAV_OUT, voiceFloat);
  const sfxStats = writeWavMono16(SFX_WAV_OUT, sfxFloat);

  const speakersObj = {};
  for (const p of script.phones) {
    speakersObj[p.id] = {
      id: p.id,
      userId: p.userId,
      name: p.name,
      fullName: p.fullName,
      bcId: p.bcId,
      persona: p.persona,
      color: p.avatarColor,
      avatarColor: p.avatarColor,
    };
  }
  speakersObj.ai = {
    id: script.aiSpeaker.id,
    userId: script.aiSpeaker.userId,
    name: script.aiSpeaker.name,
    fullName: script.aiSpeaker.fullName,
    bcId: script.aiSpeaker.bcId,
    persona: script.aiSpeaker.persona,
    color: script.aiSpeaker.avatarColor,
    avatarColor: script.aiSpeaker.avatarColor,
  };

  const timelineDoc = {
    title: script.title,
    subtitle: script.subtitle,
    fps,
    width: script.width || 3840,
    height: script.height || 2160,
    totalFrames,
    sampleRate: SAMPLE_RATE,
    introDuration,
    outroStart,
    outroDuration: Number((totalDuration - outroStart).toFixed(4)),
    totalDuration,
    lineGapSec,
    phones: script.phones,
    speakers: speakersObj,
    recapFeatures: script.recapFeatures,
    chapters,
    lines: timelineLines,
    uiEvents,
  };

  const timelineJson = JSON.stringify(timelineDoc, null, 2);
  const srtText = generateSrt(timelineLines);
  const youtubeMd = generateYoutubeMarkdown(timelineDoc);

  assertZeroForbiddenContent(timelineJson, "timeline.json", apiKey);
  assertZeroForbiddenContent(srtText, "subtitles_th.srt", apiKey);
  assertZeroForbiddenContent(youtubeMd, "youtube.md", apiKey);

  for (let i = 1; i < timelineLines.length; i++) {
    const prev = timelineLines[i - 1];
    const curr = timelineLines[i];
    const gap = curr.start - prev.end;
    assert.ok(
      gap >= 0.275,
      `Line overlap or insufficient gap between ${prev.id} and ${curr.id}: gap=${gap}`
    );
  }
  assert.equal(voiceStats.bytes, sfxStats.bytes, "voice_master.wav and sfx_master.wav byte sizes must match");
  assert.ok(voiceStats.rms > 0.005, "voice_master.wav RMS must be audible");
  assert.ok(sfxStats.rms > 0.0005, "sfx_master.wav RMS must be audible");

  fs.mkdirSync(DATA_DIR, { recursive: true });
  fs.mkdirSync(OUTPUT_DIR, { recursive: true });
  fs.writeFileSync(TIMELINE_OUT, timelineJson, "utf8");
  fs.writeFileSync(SRT_OUT, srtText, "utf8");
  fs.writeFileSync(YOUTUBE_OUT, youtubeMd, "utf8");

  console.log(`\n[tts_generate] SUCCESS!`);
  console.log(`  Lines          : ${timelineLines.length}`);
  console.log(`  Intro          : 0.00s -> ${introDuration.toFixed(2)}s`);
  console.log(`  Outro          : ${outroStart.toFixed(2)}s -> ${totalDuration.toFixed(2)}s`);
  console.log(`  Total Duration : ${totalDuration.toFixed(2)}s (${(totalDuration / 60).toFixed(2)} min, ${totalFrames} frames @ ${fps}fps)`);
  console.log(`  Voice Master   : ${VOICE_WAV_OUT} (${voiceStats.bytes} bytes, peak=${voiceStats.peak.toFixed(3)}, rms=${voiceStats.rms.toFixed(4)})`);
  console.log(`  SFX Master     : ${SFX_WAV_OUT} (${sfxStats.bytes} bytes, peak=${sfxStats.peak.toFixed(3)}, rms=${sfxStats.rms.toFixed(4)})`);
  console.log(`  Timeline JSON  : ${TIMELINE_OUT}`);
  console.log(`  Subtitles SRT  : ${SRT_OUT}`);
  console.log(`  YouTube MD     : ${YOUTUBE_OUT}`);
}

main().catch((err) => {
  console.error("[tts_generate] FAILED:", err.message || err);
  process.exit(1);
});
