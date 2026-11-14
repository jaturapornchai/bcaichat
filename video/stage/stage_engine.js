/* BC Ai Chat — 4K 5-Phone Deterministic Stage Engine
 * Pure synchronous rendering from timeline time `t` (seconds) for parallel 4K frame capture.
 * Public API:
 *   window.initTimeline(data)
 *   window.renderAtTime(seconds)
 *   window.renderThumbnail()
 *   window.getStageState()
 */
(function () {
  "use strict";

  const THEMES = {
    ban_chiang: {
      id: "ban_chiang",
      name: "บ้านเชียง (ดินเผาไทย)",
      shortName: "บ้านเชียง",
      primary: "#812920",
      deep: "#681F18",
      ring: "#A04035",
      ochre: "#83280E",
      gold: "#D4A373",
      surface: "#FBF9F8",
      panel: "#F6F3F2",
      sand: "#E4DFD1",
      card: "#FFFFFF",
      border: "#DCC0BC",
      soft: "#FFDAD5",
      text: "#1B1C1C",
      muted: "#615E53",
      bubbleSent: "#FADBD4",
      bubbleSentText: "#2B1410",
      bubbleRecv: "#FFFFFF",
    },
    silk_amber: {
      id: "silk_amber",
      name: "ไหมทองอำพัน",
      shortName: "ไหมทองอำพัน",
      primary: "#B45309",
      deep: "#92400E",
      ring: "#D97706",
      ochre: "#78350F",
      gold: "#F59E0B",
      surface: "#FFFDF9",
      panel: "#FAF5EE",
      sand: "#EFE6D5",
      card: "#FFFFFF",
      border: "#E6D0B3",
      soft: "#FEF3C7",
      text: "#1F1A14",
      muted: "#6B5E4E",
      bubbleSent: "#FDE68A",
      bubbleSentText: "#451A03",
      bubbleRecv: "#FFFFFF",
    },
    indigo_kram: {
      id: "indigo_kram",
      name: "ครามสุโขทัย",
      shortName: "ครามสุโขทัย",
      primary: "#1E40AF",
      deep: "#1E3A8A",
      ring: "#3B82F6",
      ochre: "#1D4ED8",
      gold: "#93C5FD",
      surface: "#F8FAFC",
      panel: "#F1F5F9",
      sand: "#E2E8F0",
      card: "#FFFFFF",
      border: "#CBD5E1",
      soft: "#DBEAFE",
      text: "#0F172A",
      muted: "#475569",
      bubbleSent: "#DBEAFE",
      bubbleSentText: "#172554",
      bubbleRecv: "#FFFFFF",
    },
    jade_celadon: {
      id: "jade_celadon",
      name: "หยกสังคโลก",
      shortName: "หยกสังคโลก",
      primary: "#13795B",
      deep: "#0F5132",
      ring: "#198754",
      ochre: "#115E59",
      gold: "#6EE7B7",
      surface: "#F7FBF9",
      panel: "#EEF6F3",
      sand: "#DCECE5",
      card: "#FFFFFF",
      border: "#BFDCD1",
      soft: "#D1FAE5",
      text: "#10211B",
      muted: "#496459",
      bubbleSent: "#D1FAE5",
      bubbleSentText: "#064E3B",
      bubbleRecv: "#FFFFFF",
    },
    lotus_rose: {
      id: "lotus_rose",
      name: "บัวหลวงชมพู",
      shortName: "บัวหลวงชมพู",
      primary: "#BE185D",
      deep: "#9D174D",
      ring: "#EC4899",
      ochre: "#831843",
      gold: "#F9A8D4",
      surface: "#FFF9FB",
      panel: "#FDF2F7",
      sand: "#F5DFE9",
      card: "#FFFFFF",
      border: "#F3C6DA",
      soft: "#FCE7F3",
      text: "#24121B",
      muted: "#6B4E5C",
      bubbleSent: "#FCE7F3",
      bubbleSentText: "#500724",
      bubbleRecv: "#FFFFFF",
    },
    spice_cinnamon: {
      id: "spice_cinnamon",
      name: "อบเชยเครื่องเทศ",
      shortName: "อบเชย",
      primary: "#C2410C",
      deep: "#9A3412",
      ring: "#EA580C",
      ochre: "#7C2D12",
      gold: "#FDBA74",
      surface: "#FFFAF7",
      panel: "#FBF3EE",
      sand: "#EFE1D6",
      card: "#FFFFFF",
      border: "#ECCABB",
      soft: "#FFEDD5",
      text: "#221610",
      muted: "#6B5548",
      bubbleSent: "#FED7AA",
      bubbleSentText: "#431407",
      bubbleRecv: "#FFFFFF",
    },
    royal_amethyst: {
      id: "royal_amethyst",
      name: "มณีม่วงไทย",
      shortName: "มณีม่วงไทย",
      primary: "#6D28D9",
      deep: "#5B21B6",
      ring: "#8B5CF6",
      ochre: "#4C1D95",
      gold: "#C4B5FD",
      surface: "#FAF9FD",
      panel: "#F3F0FA",
      sand: "#E6E0F4",
      card: "#FFFFFF",
      border: "#D5CBEB",
      soft: "#EDE9FE",
      text: "#181326",
      muted: "#584F70",
      bubbleSent: "#EDE9FE",
      bubbleSentText: "#2E1065",
      bubbleRecv: "#FFFFFF",
    },
  };

  const ROOM_TONE_LABELS = {
    ban_chiang_cream: "ครีมดินเผา",
    terracotta_night: "รัตติกาลดินเผา (มืด)",
    ivory_white: "ขาวงาช้าง",
  };

  const DEFAULT_PHONES = [
    {
      id: "kong",
      userId: "user_demo1",
      name: "ก้อง",
      fullName: "ก้อง (Demo 1)",
      bcId: "@kong.bc",
      persona: "สายเที่ยว & ถ่ายรูป",
      avatarColor: "#812920",
    },
    {
      id: "prae",
      userId: "user_demo2",
      name: "แพร",
      fullName: "แพร (Demo 2)",
      bcId: "@prae.bc",
      persona: "สายคาเฟ่ & ชวนกินข้าว",
      avatarColor: "#B45309",
    },
    {
      id: "boss",
      userId: "user_demo3",
      name: "บอส",
      fullName: "บอส (Demo 3)",
      bcId: "@boss.bc",
      persona: "ครอบครัว & แกดเจ็ต",
      avatarColor: "#13795B",
    },
    {
      id: "mind",
      userId: "user_demo4",
      name: "มายด์",
      fullName: "มายด์ (Demo 4)",
      bcId: "@mind.bc",
      persona: "สายดูหนัง & ซีรีส์",
      avatarColor: "#1E40AF",
    },
    {
      id: "ton",
      userId: "user_demo5",
      name: "ต้น",
      fullName: "ต้น (Demo 5)",
      bcId: "@ton.bc",
      persona: "สายวิ่ง & แคมป์ปิ้ง",
      avatarColor: "#6D28D9",
    },
  ];

  const DEFAULT_SPEAKERS = {
    kong: { id: "kong", name: "ก้อง", fullName: "ก้อง • @kong.bc", color: "#812920" },
    prae: { id: "prae", name: "แพร", fullName: "แพร • @prae.bc", color: "#B45309" },
    boss: { id: "boss", name: "บอส", fullName: "บอส • @boss.bc", color: "#13795B" },
    mind: { id: "mind", name: "มายด์", fullName: "มายด์ • @mind.bc", color: "#1E40AF" },
    ton: { id: "ton", name: "ต้น", fullName: "ต้น • @ton.bc", color: "#6D28D9" },
    ai: { id: "ai", name: "🤖 BC AI", fullName: "🤖 BC AI ผู้ช่วยส่วนตัว", color: "#4F46E5" },
  };

  const FOLDERS = [
    { id: "all", label: "ทั้งหมด" },
    { id: "personal", label: "ส่วนตัว" },
    { id: "family", label: "ครอบครัว" },
    { id: "group", label: "กลุ่ม" },
    { id: "pinned", label: "ปักหมุด" },
    { id: "unread", label: "ยังไม่อ่าน" },
    { id: "archived", label: "เก็บถาวร" },
  ];

  const STICKERS = {
    clay_wave: { label: "ทักทายจ้า!", accent: "#812920", bg: "#FADBD4", motif: "wave" },
    clay_cheers: { label: "ลุยเลยเพื่อน!", accent: "#B45309", bg: "#FEF3C7", motif: "cheers" },
    clay_love: { label: "ส่งใจให้เลย", accent: "#BE185D", bg: "#FCE7F3", motif: "heart" },
    clay_ok: { label: "โอเคพร้อม!", accent: "#13795B", bg: "#D1FAE5", motif: "check" },
    pottery_hello: { label: "สวัสดีครับ", accent: "#812920", bg: "#FADBD4", motif: "wave" },
    pottery_thanks: { label: "ขอบคุณครับ", accent: "#92400E", bg: "#FEF3C7", motif: "cheers" },
    pottery_roger: { label: "รับทราบ", accent: "#13795B", bg: "#D1FAE5", motif: "check" },
    pottery_great: { label: "ยอดเยี่ยม", accent: "#1E40AF", bg: "#DBEAFE", motif: "star" },
    pottery_fighting: { label: "สู้ๆ นะ", accent: "#C2410C", bg: "#FFEDD5", motif: "flame" },
    pottery_urgent: { label: "ด่วนจี๋", accent: "#9D174D", bg: "#FCE7F3", motif: "bolt" },
    pottery_sorry: { label: "ขออภัยครับ", accent: "#5B21B6", bg: "#EDE9FE", motif: "spark" },
    pottery_congrats: { label: "ยินดีด้วย", accent: "#83280E", bg: "#F5EFEA", motif: "heart" },
  };

  const DEFAULT_RECAP_FEATURES = [
    {
      title: "แชทกลุ่ม & 1-ต่อ-1 ซิงค์สด",
      desc: "สถานะอ่านแล้วขึ้นทันทีทุกเครื่อง พร้อมโฟลเดอร์เลื่อนแนวนอน 4 แท็บ Mobile-First",
    },
    {
      title: "ข้อความลับล็อกรหัส PIN",
      desc: "ซ่อนเนื้อหาสำคัญด้วย PIN 4 หลัก เปิดอ่านได้เฉพาะคนที่รู้รหัสเท่านั้น",
    },
    {
      title: "ยกเลิกส่งไร้ร่องรอย 100%",
      desc: "ลบข้อความที่ส่งผิดออกทันที สะอาดตา ไม่ทิ้งร่องรอยข้อความกวนใจ",
    },
    {
      title: "สมุดบันทึก BC & ไฟล์ถาวร",
      desc: "เก็บรูป HD ข้อความเสียง และไฟล์ PDF ถาวร ไม่หมดอายุ ซิงค์มือถือ-คอม-เว็บ",
    },
    {
      title: "🤖 BC AI ผู้ช่วยส่วนตัว",
      desc: "เรียก @ai ช่วยวางแผนทริปในกลุ่ม หรือทักคุยส่วนตัว 1-1 ได้ตลอด 24 ชม.",
    },
    {
      title: "โพลโหวตสด & นัดหมาย RSVP",
      desc: "โหวตที่พัก-ร้านอาหาร และกดยืนยันนัดหมายเห็นยอดอัปเดตพร้อมกันทุกจอ",
    },
    {
      title: "การ์ดโต้ตอบ & หารค่าข้าว",
      desc: "คำนวณยอดหารบิลและจัดทริปผ่านถาด Inline ในห้องแชท ไร้ป๊อปอัปบังจอ",
    },
    {
      title: "7 ธีมไทย & โทนมืดดินเผา",
      desc: "บ้านเชียงเป็นค่าเริ่มต้น พร้อมสลับ 7 ธีมไทยและโทนรัตติกาลดินเผาสบายตา",
    },
  ];

  // Built-in Demo Timeline for standalone preview & mock Playwright verification
  const BUILTIN_SHOWCASE_TIMELINE = {
    fps: 30,
    width: 3840,
    height: 2160,
    introDuration: 4.2,
    outroStart: 43.0,
    totalDuration: 49.0,
    phones: DEFAULT_PHONES,
    speakers: DEFAULT_SPEAKERS,
    chapters: [
      {
        id: "intro",
        title: "เปิดตัว BC Ai Chat",
        mode: "intro",
        dmPair: null,
        start: 0,
        end: 4.2,
        headerBadge: "✨ เปิดตัว BC Ai Chat 4K",
        featurePill: "แชทส่วนตัว แก๊งเพื่อน & ผู้ช่วย AI ครบจบในธีมบ้านเชียง",
      },
      {
        id: "group_open",
        title: "แชทกลุ่ม 5 เครื่อง & สติกเกอร์",
        mode: "group",
        dmPair: null,
        start: 4.2,
        end: 11.5,
        headerBadge: "👨‍👩‍👧‍👦 แชทกลุ่ม 5 เครื่องพร้อมกัน",
        featurePill: "4 แท็บ Mobile-First • แถบโฟลเดอร์ • อ่านแล้ว 4 สด",
      },
      {
        id: "dm_kong_prae",
        title: "แชทส่วนตัว ก้อง ↔ แพร + PIN + ยกเลิกไร้ร่องรอย",
        mode: "dm",
        dmPair: ["kong", "prae"],
        start: 11.5,
        end: 20.0,
        headerBadge: "🔒 แชทส่วนตัว 1-ต่อ-1 ก้อง ↔ แพร",
        featurePill: "ข้อความลับ PIN • ยกเลิกส่งไร้ร่องรอย • สมุดบันทึก BC",
      },
      {
        id: "dm_boss_ton",
        title: "แชทส่วนตัว บอส ↔ ต้น + เสียง + ไฟล์ถาวร",
        mode: "dm",
        dmPair: ["boss", "ton"],
        start: 20.0,
        end: 27.0,
        headerBadge: "🔒 แชทส่วนตัว 1-ต่อ-1 บอส ↔ ต้น",
        featurePill: "ข้อความเสียง • รูป HD • PDF เก็บถาวร ไม่หมดอายุ",
      },
      {
        id: "group_ai_poll",
        title: "BC AI ผู้ช่วย & โพลโหวต + RSVP",
        mode: "group",
        dmPair: null,
        start: 27.0,
        end: 35.5,
        headerBadge: "🤖 แชทกลุ่ม + BC AI & โพลโหวตสด",
        featurePill: "เรียก @ai วางทริป • โพลโหวตสด • การ์ดนัดหมาย RSVP",
      },
      {
        id: "group_miniapp_theme",
        title: "การ์ดหารค่าข้าว & 7 ธีมไทย",
        mode: "group",
        dmPair: null,
        start: 35.5,
        end: 43.0,
        headerBadge: "🎨 การ์ดโต้ตอบ & 7 ธีมไทยร่วมสมัย",
        featurePill: "หารค่าข้าวอัจฉริยะ • 7 ธีมไทย • โทนมืดดินเผา",
      },
      {
        id: "recap_outro",
        title: "สรุป 8 จุดเด่น BC Ai Chat",
        mode: "outro",
        dmPair: null,
        start: 43.0,
        end: 49.0,
        headerBadge: "✨ สรุป 8 ความสามารถ BC Ai Chat",
        featurePill: "ส่วนตัว ปลอดภัย ใช้ง่ายทั้งมือถือ คอม และเว็บ",
      },
    ],
    lines: [
      {
        index: 0,
        id: "l1",
        scene: "group_open",
        mode: "group",
        speaker: "kong",
        speakerName: "ก้อง",
        start: 4.4,
        end: 7.8,
        displayText: "เสาร์นี้ไปเขาใหญ่กันไหมทุกคน ลองคุยใน BC Ai Chat ธีมบ้านเชียงลื่นมาก!",
        theme: "ban_chiang",
        roomTone: "ban_chiang_cream",
        activeFolderChip: "group",
        featurePill: "4 แท็บ Mobile-First • แถบโฟลเดอร์เลื่อนแนวนอน",
      },
      {
        index: 1,
        id: "l2",
        scene: "group_open",
        mode: "group",
        speaker: "prae",
        speakerName: "แพร",
        start: 8.0,
        end: 11.2,
        displayText: "ดีเลย! ขึ้นอ่านแล้ว 4 ครบทุกคน ส่งสติกเกอร์ดินเผาไทยให้กำลังใจหน่อย",
        theme: "ban_chiang",
        roomTone: "ban_chiang_cream",
        activeFolderChip: "all",
        featurePill: "อ่านแล้ว 4 แบบเรียลไทม์ • สติกเกอร์อารมณ์ดีดินเผาไทย",
      },
      {
        index: 2,
        id: "l3",
        scene: "dm_kong_prae",
        mode: "dm",
        dmPair: ["kong", "prae"],
        speaker: "prae",
        speakerName: "แพร",
        start: 11.7,
        end: 15.4,
        displayText: "ก้อง ทักแชทส่วนตัวแป๊บ! แพรส่งรหัสเค้กวันเกิดบอสแบบล็อก PIN ให้นะ",
        screenMode: { mind: "notes" },
        featurePill: "ข้อความลับล็อก PIN 4 หลัก • มายด์เปิดสมุดบันทึก BC",
      },
      {
        index: 3,
        id: "l4",
        scene: "dm_kong_prae",
        mode: "dm",
        dmPair: ["kong", "prae"],
        speaker: "kong",
        speakerName: "ก้อง",
        start: 15.7,
        end: 19.7,
        displayText: "โอ๊ยส่งผิดคำ กดยกเลิกส่งไร้ร่องรอยได้เลย ส่วนมายด์กำลังจดเช็กลิสต์ในสมุดบันทึก BC",
        screenMode: { mind: "notes" },
        featurePill: "ยกเลิกส่งไร้ร่องรอย 100% • สมุดบันทึก BC ส่วนตัว",
      },
      {
        index: 4,
        id: "l5",
        scene: "dm_boss_ton",
        mode: "dm",
        dmPair: ["boss", "ton"],
        speaker: "ton",
        speakerName: "ต้น",
        start: 20.3,
        end: 26.6,
        displayText: "บอส ต้นส่งข้อความเสียง รูปจุดกางเต็นท์ 4K และไฟล์ PDF ไปให้ เก็บถาวรไม่หมดอายุเลย!",
        featurePill: "ข้อความเสียง • รูป 4K & PDF เก็บถาวร ไม่หมดอายุ",
      },
      {
        index: 5,
        id: "l6",
        scene: "group_ai_poll",
        mode: "group",
        speaker: "mind",
        speakerName: "มายด์",
        start: 27.2,
        end: 30.2,
        displayText: "กลับมาห้องกลุ่มแล้ว! เรียก @ai ช่วยจัดแพลนทริปเขาใหญ่ 2 วัน 1 คืนให้หน่อย",
        featurePill: "เรียก @ai ผู้ช่วยส่วนตัวในกลุ่ม & 1-1",
      },
      {
        index: 6,
        id: "l7",
        scene: "group_ai_poll",
        mode: "group",
        speaker: "ai",
        speakerName: "🤖 BC AI",
        start: 30.4,
        end: 33.4,
        displayText: "จัดให้เลยครับ! วันแรกแวะคาเฟ่วิวเขา-กางเต็นท์ และทักแชท 1-1 กับ BC AI ได้เสมอครับ",
        featurePill: "🤖 BC AI ตอบไวในห้องกลุ่ม + แชท 1-1 ได้ตลอดเวลา",
      },
      {
        index: 7,
        id: "l8",
        scene: "group_ai_poll",
        mode: "group",
        speaker: "kong",
        speakerName: "ก้อง",
        start: 33.6,
        end: 35.3,
        displayText: "ทุกคนกดโหวตโพลที่พักกับยืนยัน RSVP พร้อมกันได้เลย!",
        featurePill: "โพลโหวตสด & การ์ดนัดหมาย RSVP อัปเดตพร้อมกัน 5 จอ",
      },
      {
        index: 8,
        id: "l9",
        scene: "group_miniapp_theme",
        mode: "group",
        speaker: "prae",
        speakerName: "แพร",
        start: 35.7,
        end: 39.0,
        displayText: "ส่งการ์ดหารค่าข้าวกับเพื่อน 1,850 บาท ตกคนละ 370 บาท กดยืนยันในแชทได้เลย",
        inlineTray: { phone: "prae", type: "split_bill" },
        featurePill: "การ์ดโต้ตอบหารค่าข้าว & มินิแอปในห้องแชท",
      },
      {
        index: 9,
        id: "l10",
        scene: "group_miniapp_theme",
        mode: "group",
        speaker: "boss",
        speakerName: "บอส",
        start: 39.2,
        end: 42.7,
        displayText: "แถมสลับได้ 7 ธีมไทยร่วมสมัย ทั้งครามสุโขทัย หยกสังคโลก และโทนมืดดินเผา!",
        inlineTray: { phone: "boss", type: "theme_picker" },
        featurePill: "7 ธีมไทยร่วมสมัย & โทนมืดดินเผาสบายตา",
      },
      {
        index: 10,
        id: "l11",
        scene: "recap_outro",
        mode: "outro",
        speaker: "kong",
        speakerName: "ก้อง",
        start: 43.2,
        end: 48.6,
        displayText: "BC Ai Chat ครบจบทั้งแชทส่วนตัว แก๊งเพื่อน ไฟล์ไม่หมดอายุ และผู้ช่วย AI ในแอปเดียว!",
        featurePill: "สรุป 8 จุดเด่น BC Ai Chat",
      },
    ],
    uiEvents: [
      {
        id: "ev_g1",
        at: 4.5,
        room: "group",
        participants: ["kong", "prae", "boss", "mind", "ton"],
        sender: "kong",
        senderName: "ก้อง",
        kind: "text",
        clock: "09:41",
        text: "เสาร์นี้ไปเขาใหญ่กันไหมทุกคน ลองคุยใน BC Ai Chat ธีมบ้านเชียงลื่นมาก!",
        readSteps: [
          { at: 4.8, count: 1 },
          { at: 5.5, count: 2 },
          { at: 6.2, count: 4 },
        ],
      },
      {
        id: "ev_g2",
        at: 8.1,
        room: "group",
        participants: ["kong", "prae", "boss", "mind", "ton"],
        sender: "prae",
        senderName: "แพร",
        kind: "sticker",
        stickerId: "clay_cheers",
        label: "ลุยเลยเพื่อน!",
        clock: "09:41",
        readSteps: [
          { at: 8.5, count: 2 },
          { at: 9.2, count: 4 },
        ],
      },
      {
        id: "ev_dm1_pin",
        at: 12.1,
        room: "dm_kong_prae",
        participants: ["kong", "prae"],
        sender: "prae",
        senderName: "แพร",
        kind: "secret_pin",
        pin: "2580",
        unlockAt: 14.2,
        previewLabel: "[ลับส่วนตัว] ล็อกรหัส PIN",
        unlockedText: "นัดรับเค้กเซอร์ไพรส์บอสร้านหน้าปากซอย 17:30 น. ห้ามบอสรู้นะ!",
        clock: "09:42",
        readSteps: [{ at: 12.6, count: 1 }],
      },
      {
        id: "ev_dm1_unsend",
        at: 15.8,
        room: "dm_kong_prae",
        participants: ["kong", "prae"],
        sender: "kong",
        senderName: "ก้อง",
        kind: "unsend_demo",
        unsendAt: 17.6,
        text: "อ้าวพิมพ์ผิด ส่งสลิปร้านผิดแชท!",
        clock: "09:42",
      },
      {
        id: "ev_dm1_ok",
        at: 18.2,
        room: "dm_kong_prae",
        participants: ["kong", "prae"],
        sender: "kong",
        senderName: "ก้อง",
        kind: "sticker",
        stickerId: "clay_ok",
        label: "โอเคพร้อม!",
        clock: "09:42",
        readSteps: [{ at: 18.6, count: 1 }],
      },
      {
        id: "ev_notes_mind",
        at: 11.7,
        until: 20.0,
        room: "notes",
        phone: "mind",
        kind: "notebook_focus",
        notes: [
          {
            title: "เช็กลิสต์ทริปเขาใหญ่ & ของขวัญบอส",
            items: [
              { done: true, text: "เตรียมกล้องฟิล์ม & พาวเวอร์แบงก์" },
              { done: true, text: "สั่งกล่องของขวัญเซอร์ไพรส์บอส" },
              { done: false, text: "ปักหมุดคาเฟ่วิวเขาวันเสาร์" },
            ],
            badge: "สมุดบันทึก BC • เก็บถาวร",
          },
        ],
      },
      {
        id: "ev_dm2_voice",
        at: 20.5,
        room: "dm_boss_ton",
        participants: ["boss", "ton"],
        sender: "ton",
        senderName: "ต้น",
        kind: "voice",
        durationSec: 12,
        waveform: [4, 10, 16, 12, 18, 8, 14, 17, 9, 13, 15, 7, 11, 16, 8, 5],
        caption: "รีวิวโซนลานกางเต็นท์วิวหมอกตอนเช้า",
        clock: "09:43",
        readSteps: [{ at: 21.0, count: 1 }],
      },
      {
        id: "ev_dm2_photo",
        at: 22.5,
        room: "dm_boss_ton",
        participants: ["boss", "ton"],
        sender: "ton",
        senderName: "ต้น",
        kind: "photo",
        title: "วิวจุดกางเต็นท์ผากล้วยไม้.jpg",
        resolution: "4K ต้นฉบับ • ไม่บีบอัด",
        permanentBadge: "เก็บถาวร • ไม่หมดอายุ",
        syncBadges: ["มือถือ", "คอม", "เว็บ"],
        clock: "09:43",
      },
      {
        id: "ev_dm2_pdf",
        at: 24.4,
        room: "dm_boss_ton",
        participants: ["boss", "ton"],
        sender: "ton",
        senderName: "ต้น",
        kind: "file",
        fileName: "แผนที่จุดกางเต็นท์เขาใหญ่.pdf",
        fileSize: "4.8 MB",
        mime: "PDF",
        permanentBadge: "เก็บถาวร • ไม่หมดอายุ",
        syncBadges: ["มือถือ", "คอม", "เว็บ"],
        clock: "09:43",
        readSteps: [{ at: 25.0, count: 1 }],
      },
      {
        id: "ev_g_aiprompt",
        at: 27.4,
        room: "group",
        participants: ["kong", "prae", "boss", "mind", "ton"],
        sender: "mind",
        senderName: "มายด์",
        kind: "ai_prompt",
        text: "@ai ช่วยจัดแพลนทริปเขาใหญ่ 2 วัน 1 คืน พร้อมจุดแวะคาเฟ่ให้หน่อย!",
        clock: "09:44",
      },
      {
        id: "ev_g_aireply",
        at: 30.4,
        room: "group",
        participants: ["kong", "prae", "boss", "mind", "ton"],
        sender: "ai",
        senderName: "🤖 BC AI",
        kind: "ai_reply",
        text: "แพลนเขาใหญ่ 2 วัน 1 คืนพร้อมแล้วครับ:",
        highlights: [
          "วัน 1: คาเฟ่วิวภูเขา • กางเต็นท์รับลมเย็น",
          "วัน 2: น้ำตกเหวสุวัต • แวะซื้อของฝากก่อนกลับ",
        ],
        directHint: "ทักแชท 1-1 กับ @bc.ai ได้ตลอดเวลา",
        clock: "09:44",
      },
      {
        id: "ev_g_poll",
        at: 33.4,
        room: "group",
        participants: ["kong", "prae", "boss", "mind", "ton"],
        sender: "kong",
        senderName: "ก้อง",
        kind: "poll",
        question: "ทริปนี้พักโซนไหนดี?",
        clock: "09:45",
        options: [
          {
            id: "opt1",
            text: "ลานกางเต็นท์วิวหมอก",
            votesTimeline: [
              { at: 33.5, voters: ["kong"] },
              { at: 34.0, voters: ["kong", "ton"] },
              { at: 34.5, voters: ["kong", "ton", "mind"] },
            ],
          },
          {
            id: "opt2",
            text: "รีสอร์ทโฮมสเตย์ใกล้คาเฟ่",
            votesTimeline: [
              { at: 34.2, voters: ["prae"] },
              { at: 34.8, voters: ["prae", "boss"] },
            ],
          },
        ],
      },
      {
        id: "ev_g_rsvp",
        at: 34.1,
        room: "group",
        participants: ["kong", "prae", "boss", "mind", "ton"],
        sender: "kong",
        senderName: "ก้อง",
        kind: "rsvp",
        title: "นัดออกเดินทางทริปเขาใหญ่",
        timeLabel: "เสาร์นี้ 07:30 น.",
        location: "จุดนัดพบปั๊มริมทาง",
        clock: "09:45",
        rsvpTimeline: [
          { at: 34.1, going: ["kong"], maybe: [] },
          { at: 34.6, going: ["kong", "prae", "ton"], maybe: [] },
          { at: 35.1, going: ["kong", "prae", "boss", "mind", "ton"], maybe: [] },
        ],
      },
      {
        id: "ev_g_split",
        at: 36.1,
        room: "group",
        participants: ["kong", "prae", "boss", "mind", "ton"],
        sender: "prae",
        senderName: "แพร",
        kind: "rich_card",
        cardType: "split_bill",
        title: "หารค่าข้าวกับเพื่อน • มื้อเย็น",
        subtitle: "ยอดรวม 1,850 บาท (5 คน)",
        totalLabel: "คนละ 370 ฿",
        perPersonLabel: "จ่ายแล้ว 4/5 คน",
        items: [
          { label: "ก้อง • ปลาทับทิมทอด", amount: "370 ฿ ✓" },
          { label: "แพร • ต้มยำกุ้งน้ำข้น", amount: "370 ฿ ✓" },
          { label: "บอส/มายด์/ต้น", amount: "คนละ 370 ฿" },
        ],
        clock: "09:46",
      },
      {
        id: "ev_theme_kram",
        at: 39.5,
        kind: "theme_change",
        theme: "indigo_kram",
        roomTone: "ban_chiang_cream",
        label: "ครามสุโขทัย",
      },
      {
        id: "ev_theme_jade",
        at: 40.5,
        kind: "theme_change",
        theme: "jade_celadon",
        roomTone: "ban_chiang_cream",
        label: "หยกสังคโลก",
      },
      {
        id: "ev_theme_night",
        at: 41.5,
        kind: "theme_change",
        theme: "ban_chiang",
        roomTone: "terracotta_night",
        label: "รัตติกาลดินเผา",
      },
    ],
    recapFeatures: DEFAULT_RECAP_FEATURES,
  };

  let state = {
    timeline: BUILTIN_SHOWCASE_TIMELINE,
    explicitlyInitialized: false,
    currentTime: 0,
    activeTheme: "ban_chiang",
    activeRoomTone: "ban_chiang_cream",
    mode: "intro",
    activeSpeaker: null,
    dmPair: null,
    isThumbnail: false,
  };

  const dom = {
    root: null,
    phonesRow: null,
    arcOverlay: null,
    dmArcBanner: null,
    aiBanner: null,
    introOverlay: null,
    outroOverlay: null,
    subtitleInner: null,
    modePill: null,
    featurePill: null,
    themeChipLabel: null,
    chapterLabel: null,
    timeLabel: null,
    progressFill: null,
    phoneEls: {},
  };

  function escapeHtml(raw) {
    if (raw === null || raw === undefined) return "";
    return String(raw)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#39;");
  }

  function stripDisplayMarkup(text) {
    if (!text) return "";
    return String(text).replace(/\{([^|{}]+)\|([^}]+)\}/g, "$1");
  }

  function normalizeActorId(raw) {
    if (!raw) return "";
    const s = String(raw).toLowerCase().trim();
    const map = {
      user_demo1: "kong",
      demo1: "kong",
      user_demo2: "prae",
      demo2: "prae",
      user_demo3: "boss",
      demo3: "boss",
      user_demo4: "mind",
      demo4: "mind",
      user_demo5: "ton",
      demo5: "ton",
      user_ai: "ai",
      bc_ai: "ai",
    };
    return map[s] || s;
  }

  function normalizeRoomId(raw) {
    if (!raw) return "group";
    const s = String(raw).toLowerCase().trim();
    if (s === "conv_group_demo5" || s === "group_demo5" || s === "all") return "group";
    return s;
  }

  function formatMmSs(sec) {
    const s = Math.max(0, Math.floor(sec));
    const m = Math.floor(s / 60);
    const r = s % 60;
    return `${String(m).padStart(2, "0")}:${String(r).padStart(2, "0")}`;
  }

  function getTimelinePhones() {
    const phones = state.timeline && Array.isArray(state.timeline.phones) && state.timeline.phones.length === 5
      ? state.timeline.phones
      : DEFAULT_PHONES;
    return phones.map((p, idx) => ({
      ...DEFAULT_PHONES[idx],
      ...p,
      id: normalizeActorId(p.id || DEFAULT_PHONES[idx].id),
    }));
  }

  function getSpeakerMeta(speakerId) {
    const id = normalizeActorId(speakerId);
    const custom = state.timeline && state.timeline.speakers && state.timeline.speakers[id];
    const phone = getTimelinePhones().find((p) => p.id === id);
    const def = DEFAULT_SPEAKERS[id];
    return {
      id,
      name: (custom && custom.name) || (phone && phone.name) || (def && def.name) || id,
      fullName:
        (custom && custom.fullName) ||
        (phone && `${phone.name} • ${phone.bcId}`) ||
        (def && def.fullName) ||
        id,
      color: (custom && custom.color) || (custom && custom.avatarColor) || (phone && phone.avatarColor) || (def && def.color) || "#812920",
    };
  }

  function applyTheme(themeId, roomToneId) {
    const tId = themeId && THEMES[themeId] ? themeId : "ban_chiang";
    const rId = roomToneId && ROOM_TONE_LABELS[roomToneId] ? roomToneId : "ban_chiang_cream";
    const pal = THEMES[tId];
    const rootStyle = document.documentElement.style;
    rootStyle.setProperty("--bc-primary", pal.primary);
    rootStyle.setProperty("--bc-deep", pal.deep);
    rootStyle.setProperty("--bc-ring", pal.ring);
    rootStyle.setProperty("--bc-ochre", pal.ochre);
    rootStyle.setProperty("--bc-gold", pal.gold);
    rootStyle.setProperty("--bc-surface", pal.surface);
    rootStyle.setProperty("--bc-panel", pal.panel);
    rootStyle.setProperty("--bc-sand", pal.sand);
    rootStyle.setProperty("--bc-card", pal.card);
    rootStyle.setProperty("--bc-border", pal.border);
    rootStyle.setProperty("--bc-soft", pal.soft);
    rootStyle.setProperty("--bc-text", pal.text);
    rootStyle.setProperty("--bc-muted", pal.muted);
    rootStyle.setProperty("--bc-bubble-sent", pal.bubbleSent);
    rootStyle.setProperty("--bc-bubble-sent-text", pal.bubbleSentText);
    rootStyle.setProperty("--bc-bubble-recv", pal.bubbleRecv);

    if (rId === "ivory_white") {
      rootStyle.setProperty("--room-bg", "#FBF9F8");
    } else {
      rootStyle.setProperty("--room-bg", "#F5EFEA");
    }

    if (dom.root) {
      dom.root.dataset.theme = tId;
      dom.root.dataset.roomTone = rId;
    }
    if (dom.themeChipLabel) {
      const toneTxt = rId === "terracotta_night" ? " • โทนมืด" : "";
      dom.themeChipLabel.textContent = `ธีม: ${pal.shortName}${toneTxt}`;
    }
    state.activeTheme = tId;
    state.activeRoomTone = rId;
  }

  function buildPhonesDom() {
    if (!dom.phonesRow) return;
    const phones = getTimelinePhones();
    dom.phonesRow.innerHTML = "";
    dom.phoneEls = {};

    phones.forEach((p, idx) => {
      const slot = document.createElement("div");
      slot.className = "phone-slot";
      slot.dataset.phoneId = p.id;
      slot.dataset.slotIndex = String(idx);

      slot.innerHTML = `
        <div class="speaker-badge" data-role="speaker-badge">
          <span>🔊 ${escapeHtml(p.name)} กำลังพูด</span>
          <span class="eq-bars" data-role="eq-bars">
            <span class="eq-bar"></span>
            <span class="eq-bar"></span>
            <span class="eq-bar"></span>
            <span class="eq-bar"></span>
          </span>
        </div>
        <div class="phone-frame">
          <div class="phone-screen">
            <div class="phone-statusbar">
              <span class="status-clock">9:41</span>
              <div class="dynamic-island">
                <span class="island-lens"></span>
                <span class="island-dot"></span>
              </div>
              <div class="status-icons">
                <span>5G</span>
                <span>▮▮▮</span>
                <span>🔋</span>
              </div>
            </div>

            <div class="phone-appbar" data-role="appbar">
              <div class="appbar-left">
                <span class="appbar-back">‹</span>
                <div class="room-avatar" data-role="room-avatar" style="background:${escapeHtml(p.avatarColor)}">ก</div>
                <div class="appbar-title-wrap">
                  <div class="appbar-title" data-role="room-title">แก๊งเพื่อนสนิท 5 คน + BC AI</div>
                  <div class="appbar-sub" data-role="room-sub">ออนไลน์พร้อมกัน 5 เครื่อง</div>
                </div>
              </div>
              <div class="appbar-actions">
                <span class="appbar-icon-pill" data-role="room-pill">กลุ่ม</span>
              </div>
            </div>

            <div class="folder-strip" data-role="folder-strip">
              <div class="folder-strip-inner" data-role="folder-strip-inner"></div>
            </div>

            <div class="phone-chat-stream" data-role="chat-stream"></div>

            <div class="notes-screen" data-role="notes-screen" style="display:none;"></div>

            <div class="inline-tray" data-role="inline-tray" style="display:none;"></div>

            <div class="phone-composer" data-role="composer">
              <span class="comp-tool-btn">+</span>
              <span class="comp-tool-btn">☺</span>
              <div class="comp-input" data-role="comp-input">พิมพ์ข้อความ...</div>
              <span class="comp-send-btn">➤</span>
            </div>

            <nav class="phone-bottom-tabs" aria-label="แท็บมือถือ">
              <div class="bottom-tab" data-tab="friends"><span>👥</span><span>เพื่อน</span></div>
              <div class="bottom-tab is-active" data-tab="chats"><span>💬</span><span>แชท</span></div>
              <div class="bottom-tab" data-tab="notes"><span>📓</span><span>สมุดบันทึก</span></div>
              <div class="bottom-tab" data-tab="settings"><span>⚙️</span><span>ตั้งค่า</span></div>
            </nav>
          </div>
        </div>
        <div class="phone-nameplate">
          <span class="nameplate-dot" style="background:${escapeHtml(p.avatarColor)}"></span>
          <span>${escapeHtml(p.name)}</span>
          <span class="nameplate-handle">${escapeHtml(p.bcId)} • ${escapeHtml(p.persona)}</span>
        </div>
      `;

      dom.phonesRow.appendChild(slot);
      dom.phoneEls[p.id] = {
        slot,
        speakerBadge: slot.querySelector('[data-role="speaker-badge"]'),
        eqBars: Array.from(slot.querySelectorAll('[data-role="eq-bars"] .eq-bar')),
        roomAvatar: slot.querySelector('[data-role="room-avatar"]'),
        roomTitle: slot.querySelector('[data-role="room-title"]'),
        roomSub: slot.querySelector('[data-role="room-sub"]'),
        roomPill: slot.querySelector('[data-role="room-pill"]'),
        folderStrip: slot.querySelector('[data-role="folder-strip"]'),
        folderStripInner: slot.querySelector('[data-role="folder-strip-inner"]'),
        chatStream: slot.querySelector('[data-role="chat-stream"]'),
        notesScreen: slot.querySelector('[data-role="notes-screen"]'),
        inlineTray: slot.querySelector('[data-role="inline-tray"]'),
        composer: slot.querySelector('[data-role="composer"]'),
        compInput: slot.querySelector('[data-role="comp-input"]'),
        tabs: Array.from(slot.querySelectorAll(".bottom-tab")),
      };
    });
  }

  function renderStickerSvg(stickerId, labelOverride) {
    const def = STICKERS[stickerId] || STICKERS.clay_wave;
    const label = labelOverride || def.label;
    let innerMotif = `<path d="M18 39C23 33 29 45 35 39C40 34 44 41 47 38" stroke="${def.accent}" stroke-width="3.2" stroke-linecap="round"/>`;
    if (def.motif === "cheers") {
      innerMotif = `<path d="M22 42L27 25L35 28L30 44ZM42 42L37 25L29 28L34 44Z" fill="${def.accent}" fill-opacity="0.2" stroke="${def.accent}" stroke-width="2.2" stroke-linejoin="round"/>`;
    } else if (def.motif === "heart") {
      innerMotif = `<path d="M32 46C32 46 19 37 19 29C19 24.5 22.5 21.5 26.5 21.5C29.2 21.5 31 23 32 25C33 23 34.8 21.5 37.5 21.5C41.5 21.5 45 24.5 45 29C45 37 32 46 32 46Z" fill="${def.accent}" fill-opacity="0.24" stroke="${def.accent}" stroke-width="2.4"/>`;
    } else if (def.motif === "check") {
      innerMotif = `<path d="M21 35L29 43L44 25" stroke="${def.accent}" stroke-width="3.8" stroke-linecap="round" stroke-linejoin="round"/>`;
    } else if (def.motif === "star") {
      innerMotif = `<path d="M32 18L36 27L46 28L39 35L41 45L32 40L23 45L25 35L18 28L28 27Z" fill="${def.accent}" fill-opacity="0.22" stroke="${def.accent}" stroke-width="2.3" stroke-linejoin="round"/>`;
    } else if (def.motif === "flame") {
      innerMotif = `<path d="M33 17C38 25 44 29 44 37C44 43.6 38.6 48 32 48C25.4 48 20 43.6 20 37C20 31 24 27 28 24C28 29 31 30 33 17Z" fill="${def.accent}" fill-opacity="0.22" stroke="${def.accent}" stroke-width="2.4"/>`;
    } else if (def.motif === "bolt") {
      innerMotif = `<path d="M35 17L22 34H32L29 47L43 29H33L35 17Z" fill="${def.accent}" fill-opacity="0.24" stroke="${def.accent}" stroke-width="2.4" stroke-linejoin="round"/>`;
    }

    return `
      <div class="sticker-card" style="background:${def.bg};border-color:${def.accent};color:${def.accent};">
        <svg width="46" height="46" viewBox="0 0 64 64" fill="none" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">
          <circle cx="32" cy="32" r="27" fill="#FFFFFF" stroke="${def.accent}" stroke-width="2.6"/>
          <path d="M12 22C20 16 28 28 36 22C44 16 48 24 52 22" stroke="${def.accent}" stroke-opacity="0.45" stroke-width="2.2" stroke-linecap="round"/>
          ${innerMotif}
        </svg>
        <div class="sticker-label">${escapeHtml(label)}</div>
        <div class="sticker-series">อารมณ์ดีดินเผาไทย</div>
      </div>
    `;
  }

  function renderScenicSvg() {
    return `
      <svg width="100%" height="92" viewBox="0 0 210 92" preserveAspectRatio="xMidYMid slice" xmlns="http://www.w3.org/2000/svg">
        <defs>
          <linearGradient id="skyG" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stop-color="#F59E0B"/>
            <stop offset="55%" stop-color="#FADBD4"/>
            <stop offset="100%" stop-color="#E4DFD1"/>
          </linearGradient>
        </defs>
        <rect width="210" height="92" fill="url(#skyG)"/>
        <circle cx="158" cy="28" r="14" fill="#FEF3C7"/>
        <path d="M0 74 Q42 42 96 66 T210 58 L210 92 L0 92 Z" fill="#812920" fill-opacity="0.32"/>
        <path d="M0 82 Q55 55 120 76 T210 70 L210 92 L0 92 Z" fill="#13795B" fill-opacity="0.72"/>
        <path d="M62 76 L76 54 L90 76 Z" fill="#D4A373" stroke="#681F18" stroke-width="1.5"/>
        <path d="M76 54 L82 76" stroke="#681F18" stroke-width="1.2"/>
        <path d="M12 88 Q35 80 58 88 T104 88" stroke="#FBF9F8" stroke-opacity="0.55" stroke-width="1.4" fill="none"/>
      </svg>
    `;
  }

  function renderFolderStrip(phoneEl, activeFolderId) {
    const idx = Math.max(
      0,
      FOLDERS.findIndex((f) => f.id === activeFolderId)
    );
    const shiftPx = idx > 3 ? -(idx - 3) * 46 : 0;
    phoneEl.folderStripInner.style.transform = `translateX(${shiftPx}px)`;
    phoneEl.folderStripInner.innerHTML = FOLDERS.map(
      (f) => `<span class="folder-chip ${f.id === activeFolderId ? "is-active" : ""}">${escapeHtml(f.label)}</span>`
    ).join("");
  }

  function renderInlineTray(phoneEl, traySpec) {
    if (!traySpec) {
      phoneEl.inlineTray.style.display = "none";
      phoneEl.inlineTray.innerHTML = "";
      return;
    }

    const type = typeof traySpec === "string" ? traySpec : traySpec.type || "theme_picker";
    phoneEl.inlineTray.style.display = "flex";

    if (type === "theme_picker") {
      const themeList = [
        { ...THEMES.ban_chiang, pillName: "บ้านเชียง" },
        { ...THEMES.indigo_kram, pillName: "ครามไทย" },
        { ...THEMES.jade_celadon, pillName: "หยกเขียว" },
        { ...THEMES.silk_amber, pillName: "ไหมทอง" },
        { ...THEMES.lotus_rose, pillName: "บัวชมพู" },
        { ...THEMES.spice_cinnamon, pillName: "อบเชย" },
        { ...THEMES.royal_amethyst, pillName: "มณีม่วง" },
      ];
      const toneTag =
        state.activeRoomTone === "terracotta_night" ? "🌙 รัตติกาลดินเผา" : "☀️ ครีมดินเผา";
      phoneEl.inlineTray.innerHTML = `
        <div class="tray-head">
          <span>🎨 7 ธีมไทย &amp; 3 โทนห้อง (Inline)</span>
          <span>${toneTag}</span>
        </div>
        <div class="theme-swatches-grid">
          ${themeList
            .map(
              (th) => `
              <div class="theme-swatch-pill ${th.id === state.activeTheme ? "is-selected" : ""}">
                <span class="swatch-circle" style="background:${th.primary}"></span>
                <span>${escapeHtml(th.pillName)}</span>
              </div>
            `
            )
            .join("")}
        </div>
      `;
    } else if (type === "split_bill") {
      phoneEl.inlineTray.innerHTML = `
        <div class="tray-head">
          <span>💳 การ์ดโต้ตอบ • หารค่าข้าวกับเพื่อน</span>
          <span>5 คน</span>
        </div>
        <div style="font-size:9.5px;display:flex;justify-content:space-between;align-items:center;">
          <span>ยอดบิล: <strong>1,850 ฿</strong> ÷ 5</span>
          <span style="padding:2px 8px;border-radius:999px;background:var(--bc-primary);color:#fff;font-weight:800;">คนละ 370 ฿</span>
        </div>
      `;
    } else if (type === "poll_builder") {
      phoneEl.inlineTray.innerHTML = `
        <div class="tray-head">
          <span>📊 สร้างโพลโหวตสดในห้อง</span>
          <span>Inline</span>
        </div>
        <div style="font-size:9.5px;opacity:0.88;">• ลานกางเต็นท์วิวหมอก  • รีสอร์ทใกล้คาเฟ่</div>
      `;
    } else if (type === "sticker") {
      phoneEl.inlineTray.innerHTML = `
        <div class="tray-head">
          <span>😊 สติกเกอร์อารมณ์ดีดินเผาไทย</span>
          <span>พร้อมส่ง</span>
        </div>
      `;
    } else {
      phoneEl.inlineTray.innerHTML = `
        <div class="tray-head">
          <span>✨ เครื่องมือในห้องแชท</span>
          <span>ไร้ป๊อปอัป</span>
        </div>
      `;
    }
  }

  function getEventTime(ev) {
    if (typeof ev.at === "number") return ev.at;
    if (typeof ev.t === "number") return ev.t;
    if (typeof ev.time === "number") return ev.time;
    return 0;
  }

  function getEventKind(ev) {
    return (ev.kind || ev.type || ev.msgType || "text").toLowerCase();
  }

  function getReadCountAt(ev, t, unlockOverrides) {
    if (Array.isArray(ev.readSteps) && ev.readSteps.length > 0) {
      let count = 0;
      for (const st of ev.readSteps) {
        if (st && typeof st.at === "number" && st.at <= t) {
          count = st.count ?? count;
        }
      }
      return count;
    }
    if (typeof ev.readCount === "number") return ev.readCount;
    if (unlockOverrides && typeof unlockOverrides.readCount === "number") {
      return unlockOverrides.readCount;
    }
    return null;
  }

  function renderMessageBubbleHtml(ev, phoneId, t, aux) {
    const kind = getEventKind(ev);
    const evTime = getEventTime(ev);
    const senderId = normalizeActorId(ev.sender);
    const isMe = senderId === phoneId;
    const isAi = senderId === "ai" || kind === "ai_reply";
    const senderMeta = getSpeakerMeta(senderId);

    // Handle unsend without trace!
    const explicitUnsendAt = aux.unsendMap[ev.id];
    const unsendAt = typeof ev.unsendAt === "number" ? ev.unsendAt : explicitUnsendAt;
    let unsendStyle = "";
    let showUnsendHint = false;
    if (typeof unsendAt === "number") {
      if (t >= unsendAt + 0.42) {
        return ""; // Vanished completely without trace!
      }
      if (t >= unsendAt) {
        const p = Math.min(1, (t - unsendAt) / 0.42);
        unsendStyle = `opacity:${(1 - p).toFixed(3)};transform:scale(${(1 - 0.16 * p).toFixed(3)});transform-origin:${isMe ? "right" : "left"} center;`;
      } else if (t >= unsendAt - 0.75 && isMe) {
        showUnsendHint = true;
      }
    }

    // Entrance micro motion (deterministic)
    let enterStyle = "";
    const age = t - evTime;
    if (age >= 0 && age < 0.28 && !unsendStyle) {
      const p = age / 0.28;
      const dy = (1 - p) * 10;
      enterStyle = `opacity:${(0.3 + 0.7 * p).toFixed(3)};transform:translateY(${dy.toFixed(1)}px);`;
    }

    const rowStyle = unsendStyle || enterStyle;
    const clock = ev.clock || "09:41";
    const readCount = getReadCountAt(ev, t);
    const readHtml =
      isMe && readCount !== null
        ? `<span class="read-receipt">${readCount > 0 ? `อ่านแล้ว ${readCount}` : "ส่งแล้ว"}</span>`
        : "";

    let bodyHtml = "";
    let bubbleExtraClass = "";

    if (kind === "sticker") {
      bubbleExtraClass = "is-sticker-only";
      bodyHtml = renderStickerSvg(ev.stickerId || ev.stickerCode || "clay_wave", ev.label || ev.text);
    } else if (kind === "secret_pin") {
      const unlockAt =
        typeof ev.unlockAt === "number"
          ? ev.unlockAt
          : typeof aux.unlockMap[ev.id] === "number"
            ? aux.unlockMap[ev.id]
            : Infinity;
      const pinCode = String(ev.pin || "2580");
      if (t < unlockAt) {
        const typingWindow = unlockAt - 0.85;
        const filledCount =
          t >= typingWindow
            ? Math.min(4, Math.floor(((t - typingWindow) / 0.85) * 4) + 1)
            : 0;
        const dots = [0, 1, 2, 3]
          .map(
            (i) =>
              `<span class="pin-dot ${i < filledCount ? "is-filled" : ""}">${i < filledCount ? "•" : ""}</span>`
          )
          .join("");
        bodyHtml = `
          <div class="secret-card">
            <span class="secret-pill">🔒 ${escapeHtml(ev.previewLabel || "[ลับส่วนตัว] ล็อกรหัส PIN")}</span>
            <div class="secret-blur-box">
              <div class="secret-blurred-text">ข้อความลับส่วนตัวเข้ารหัส PIN 4 หลัก</div>
            </div>
            <div class="secret-pin-dots">
              ${dots}
              <span style="font-size:8.5px;font-weight:700;color:var(--bc-primary);">${
                filledCount > 0 ? "กำลังใส่ PIN..." : "กดใส่ PIN เพื่อเปิดอ่าน"
              }</span>
            </div>
          </div>
        `;
      } else {
        bodyHtml = `
          <div class="secret-card">
            <span class="secret-pill is-unlocked">🔓 ปลดล็อก PIN (${escapeHtml(pinCode)}) แล้ว</span>
            <div class="secret-unlocked-text">${escapeHtml(ev.unlockedText || ev.text)}</div>
          </div>
        `;
      }
    } else if (kind === "voice" || kind === "audio") {
      const dur = Number(ev.durationSec || ev.audio_duration_sec || 12);
      const elapsed = Math.max(0, Math.min(dur, t - evTime));
      const remaining = Math.max(0, Math.ceil(dur - elapsed));
      const isPlaying = t - evTime < dur;
      const wave = Array.isArray(ev.waveform) && ev.waveform.length ? ev.waveform : [5, 11, 16, 10, 17, 9, 14, 18, 12, 8, 15, 10];
      const barsHtml = wave
        .slice(0, 14)
        .map((baseH, idx) => {
          const anim = isPlaying ? Math.abs(Math.sin(t * 7.2 + idx * 0.85)) * 7 : 0;
          const h = Math.max(4, Math.min(20, Math.round(baseH * 0.85 + anim)));
          return `<span class="voice-bar" style="height:${h}px;opacity:${isPlaying ? 1 : 0.72}"></span>`;
        })
        .join("");
      bodyHtml = `
        <div class="voice-card">
          <div class="voice-top">
            <span class="voice-play-btn">${isPlaying ? "❚❚" : "▶"}</span>
            <div class="voice-bars">${barsHtml}</div>
            <span class="voice-time">${formatMmSs(isPlaying ? remaining : dur)}</span>
          </div>
          ${ev.caption ? `<div class="voice-caption">🎙️ ${escapeHtml(ev.caption)}</div>` : ""}
        </div>
      `;
    } else if (kind === "photo" || kind === "image") {
      const syncs = Array.isArray(ev.syncBadges) ? ev.syncBadges : ["มือถือ", "คอม", "เว็บ"];
      bodyHtml = `
        <div class="media-card">
          <div class="photo-preview">
            ${renderScenicSvg()}
            <span class="photo-res-tag">${escapeHtml(ev.resolution || "4K ต้นฉบับ • ไม่บีบอัด")}</span>
          </div>
          <div style="font-size:10px;font-weight:700;">🖼️ ${escapeHtml(ev.title || "ภาพความละเอียดสูง")}</div>
          <div class="perm-badge-row">
            <span class="perm-badge">🛡️ ${escapeHtml(ev.permanentBadge || "เก็บถาวร • ไม่หมดอายุ")}</span>
            ${syncs.map((s) => `<span class="sync-badge">${escapeHtml(s)}</span>`).join("")}
          </div>
        </div>
      `;
    } else if (kind === "file") {
      const syncs = Array.isArray(ev.syncBadges) ? ev.syncBadges : ["มือถือ", "คอม", "เว็บ"];
      bodyHtml = `
        <div class="media-card">
          <div class="file-row">
            <div class="file-pdf-badge">${escapeHtml(ev.mime || "PDF")}</div>
            <div class="file-info">
              <div class="file-name">${escapeHtml(ev.fileName || "เอกสาร.pdf")}</div>
              <div class="file-size">${escapeHtml(ev.fileSize || "4.8 MB")} • คลังถาวร MinIO</div>
            </div>
          </div>
          <div class="perm-badge-row">
            <span class="perm-badge">🛡️ ${escapeHtml(ev.permanentBadge || "เก็บถาวร • ไม่หมดอายุ")}</span>
            ${syncs.map((s) => `<span class="sync-badge">${escapeHtml(s)}</span>`).join("")}
          </div>
        </div>
      `;
    } else if (kind === "ai_reply") {
      bubbleExtraClass = "is-ai";
      const hls = Array.isArray(ev.highlights) ? ev.highlights : [];
      bodyHtml = `
        <div class="ai-reply-card">
          <div style="font-weight:700;">${escapeHtml(ev.text || "สรุปจาก BC AI ผู้ช่วยส่วนตัว")}</div>
          ${
            hls.length
              ? `<div class="ai-highlights">${hls
                  .map((item) => `<div class="ai-hl-item">• ${escapeHtml(item)}</div>`)
                  .join("")}</div>`
              : ""
          }
          ${
            ev.directHint
              ? `<div class="ai-direct-hint">💬 ${escapeHtml(ev.directHint)}</div>`
              : ""
          }
        </div>
      `;
    } else if (kind === "poll") {
      const opts = Array.isArray(ev.options) ? ev.options : [];
      const resolvedOpts = opts.map((opt) => {
        let voters = Array.isArray(opt.voters) ? opt.voters.slice() : [];
        if (Array.isArray(opt.votesTimeline)) {
          for (const vt of opt.votesTimeline) {
            if (vt && typeof vt.at === "number" && vt.at <= t) {
              voters = Array.isArray(vt.voters) ? vt.voters.map(normalizeActorId) : voters;
            }
          }
        }
        return { id: opt.id, text: opt.text, voters };
      });
      const totalVotes = resolvedOpts.reduce((acc, o) => acc + o.voters.length, 0);
      bodyHtml = `
        <div class="poll-card">
          <div class="poll-inner">
            <div class="card-kicker">
              <span>📊 โพลโหวตสด</span>
              <span>${totalVotes}/5 คน</span>
            </div>
            <div class="card-question">${escapeHtml(ev.question || "เลือกตัวเลือก")}</div>
            ${resolvedOpts
              .map((o) => {
                const pct = totalVotes > 0 ? Math.round((o.voters.length / totalVotes) * 100) : 0;
                const picked = o.voters.includes(phoneId);
                return `
                  <div class="poll-opt ${picked ? "is-picked" : ""}">
                    <div class="poll-opt-fill" style="width:${pct}%"></div>
                    <div class="poll-opt-row">
                      <span>${picked ? "✓ " : ""}${escapeHtml(o.text)}</span>
                      <span>${o.voters.length} (${pct}%)</span>
                    </div>
                  </div>
                `;
              })
              .join("")}
          </div>
        </div>
      `;
    } else if (kind === "rsvp" || kind === "event") {
      let going = [];
      let maybe = [];
      if (Array.isArray(ev.rsvpTimeline)) {
        for (const rt of ev.rsvpTimeline) {
          if (rt && typeof rt.at === "number" && rt.at <= t) {
            going = Array.isArray(rt.going) ? rt.going.map(normalizeActorId) : [];
            maybe = Array.isArray(rt.maybe) ? rt.maybe.map(normalizeActorId) : [];
          }
        }
      }
      const isGoing = going.includes(phoneId);
      const isMaybe = maybe.includes(phoneId);
      bodyHtml = `
        <div class="rsvp-card">
          <div class="rsvp-inner">
            <div class="card-kicker">
              <span>📅 นัดหมาย &amp; RSVP</span>
              <span>อัปเดตสด</span>
            </div>
            <div class="card-question">${escapeHtml(ev.title || "นัดหมายกลุ่ม")}</div>
            <div style="font-size:9px;opacity:0.8;">🕒 ${escapeHtml(ev.timeLabel || "")} • 📍 ${escapeHtml(ev.location || "")}</div>
            <div class="rsvp-btns">
              <div class="rsvp-btn ${isGoing ? "is-going" : ""}">เข้าร่วม (${going.length})</div>
              <div class="rsvp-btn ${isMaybe ? "is-maybe" : ""}">อาจจะ (${maybe.length})</div>
            </div>
          </div>
        </div>
      `;
    } else if (kind === "album") {
      bodyHtml = `
        <div class="album-card">
          <div class="album-inner">
            <div class="card-kicker">
              <span>📸 อัลบั้ม &amp; โน้ตกลุ่ม</span>
              <span>${escapeHtml(ev.photoCount || 12)} รูป</span>
            </div>
            <div class="card-question">${escapeHtml(ev.title || "อัลบั้มรูปทริป")}</div>
            <div class="album-grid">
              <div class="album-tile">⛰️</div>
              <div class="album-tile">⛺</div>
              <div class="album-tile">☕</div>
            </div>
            ${ev.noteTitle ? `<div style="font-size:9px;font-weight:700;">📝 ${escapeHtml(ev.noteTitle)}</div>` : ""}
            <span class="perm-badge">🛡️ ${escapeHtml(ev.permanentBadge || "เก็บถาวร • ไม่หมดอายุ")}</span>
          </div>
        </div>
      `;
    } else if (kind === "rich_card") {
      const items = Array.isArray(ev.items) ? ev.items : [];
      const cardIcon = ev.cardType === "trip_planner" ? "🗺️" : "💳";
      bodyHtml = `
        <div class="rich-card">
          <div class="rich-card-head">
            <span>${cardIcon} ${escapeHtml(ev.title || "การ์ดโต้ตอบ")}</span>
            <span>${escapeHtml(ev.perPersonLabel || "")}</span>
          </div>
          <div class="rich-card-body">
            ${ev.subtitle ? `<div style="font-size:9.5px;opacity:0.85;">${escapeHtml(ev.subtitle)}</div>` : ""}
            ${ev.totalLabel ? `<div class="rich-highlight">${escapeHtml(ev.totalLabel)}</div>` : ""}
            ${items
              .slice(0, 3)
              .map(
                (it) => `
                <div class="rich-item-row">
                  <span>${escapeHtml(it.label)}</span>
                  <strong>${escapeHtml(it.amount)}</strong>
                </div>
              `
              )
              .join("")}
          </div>
        </div>
      `;
    } else {
      const txt = stripDisplayMarkup(ev.text || ev.content || "");
      const highlighted = escapeHtml(txt).replace(
        /(@ai|@bc\.ai)/gi,
        '<strong style="color:#4F46E5;background:#EEF2FF;padding:0 4px;border-radius:4px;">$1</strong>'
      );
      bodyHtml = `<div>${highlighted}</div>`;
      if (showUnsendHint) {
        bodyHtml += `<div class="unsend-hint-tag">💨 กดค้าง • ยกเลิกส่งไร้ร่องรอย</div>`;
      }
    }

    const avatarChar = isAi ? "🤖" : escapeHtml(senderMeta.name.charAt(0));
    const avatarBg = isAi ? "linear-gradient(135deg,#4F46E5,#6D28D9)" : escapeHtml(senderMeta.color);

    return `
      <div class="msg-row ${isMe ? "is-me" : "is-other"}" style="${rowStyle}">
        ${
          !isMe
            ? `<div class="msg-avatar" style="background:${avatarBg}">${avatarChar}</div>`
            : ""
        }
        <div class="msg-col">
          ${
            !isMe
              ? `<div class="msg-sender-row">
                   <span class="msg-sender-name ${isAi ? "is-ai" : ""}">${escapeHtml(ev.senderName || senderMeta.name)}</span>
                   ${isAi ? `<span class="ai-tag">BC AI</span>` : ""}
                 </div>`
              : ""
          }
          <div class="msg-bubble-line">
            <div class="msg-bubble ${isAi ? "is-ai" : ""} ${bubbleExtraClass}">${bodyHtml}</div>
            <div class="msg-meta">
              ${readHtml}
              <span>${escapeHtml(clock)}</span>
            </div>
          </div>
        </div>
      </div>
    `;
  }

  function renderNotesScreen(phoneEl, phoneObj, noteEvent) {
    const notes =
      noteEvent && Array.isArray(noteEvent.notes) && noteEvent.notes.length
        ? noteEvent.notes
        : [
            {
              title: "เช็กลิสต์ทริปเขาใหญ่ & ของขวัญบอส",
              items: [
                { done: true, text: "เตรียมกล้องฟิล์ม & พาวเวอร์แบงก์" },
                { done: true, text: "สั่งกล่องของขวัญเซอร์ไพรส์บอส" },
                { done: false, text: "ปักหมุดคาเฟ่วิวเขาวันเสาร์" },
              ],
              badge: "สมุดบันทึก BC • ซิงค์ทุกเครื่อง",
            },
          ];

    phoneEl.notesScreen.innerHTML = `
      <div class="notes-header-card">
        <div>
          <div style="font-size:12px;font-weight:800;">📓 สมุดบันทึก BC</div>
          <div style="font-size:9px;opacity:0.86;">คลังบันทึกส่วนตัวของ ${escapeHtml(phoneObj.name)}</div>
        </div>
        <span style="padding:3px 8px;border-radius:999px;background:rgba(255,255,255,0.2);font-size:8.5px;font-weight:700;">เก็บถาวร</span>
      </div>
      ${notes
        .map(
          (n) => `
        <div class="note-card">
          <div class="note-card-title">
            <span>📌 ${escapeHtml(n.title)}</span>
          </div>
          ${(n.items || [])
            .map(
              (it) => `
            <div class="note-check-item">
              <span style="color:${it.done ? "#13795B" : "var(--bc-muted)"};font-weight:800;">${
                it.done ? "☑" : "☐"
              }</span>
              <span style="${it.done ? "text-decoration:line-through;opacity:0.65;" : "font-weight:600;"}">${escapeHtml(
                it.text
              )}</span>
            </div>
          `
            )
            .join("")}
          ${
            n.body
              ? `<div style="font-size:9.5px;color:var(--bc-muted);line-height:1.4;">${escapeHtml(n.body)}</div>`
              : ""
          }
          <div style="margin-top:2px;">
            <span class="perm-badge">🛡️ ${escapeHtml(n.badge || "สมุดบันทึก BC • ไม่หมดอายุ")}</span>
          </div>
        </div>
      `
        )
        .join("")}
      <div class="note-card" style="background:var(--bc-panel);">
        <div style="font-size:10px;font-weight:700;color:var(--bc-primary);">📎 ไฟล์แนบในสมุดบันทึก</div>
        <div style="font-size:9px;color:var(--bc-muted);">แผนที่คาเฟ่เขาใหญ่.pdf • ซิงค์มือถือ คอม เว็บ</div>
      </div>
    `;
  }

  function renderDmArcOverlay(dmPair, t) {
    if (!dom.arcOverlay || !dom.dmArcBanner) return;
    if (!Array.isArray(dmPair) || dmPair.length !== 2) {
      dom.arcOverlay.innerHTML = "";
      dom.dmArcBanner.style.display = "none";
      return;
    }

    const phones = getTimelinePhones();
    const idxA = phones.findIndex((p) => p.id === normalizeActorId(dmPair[0]));
    const idxB = phones.findIndex((p) => p.id === normalizeActorId(dmPair[1]));
    if (idxA < 0 || idxB < 0) {
      dom.arcOverlay.innerHTML = "";
      dom.dmArcBanner.style.display = "none";
      return;
    }

    const leftIdx = Math.min(idxA, idxB);
    const rightIdx = Math.max(idxA, idxB);
    const phoneA = phones[leftIdx];
    const phoneB = phones[rightIdx];

    // Phone centers: left padding 36 + idx * (344 + 32) + 172
    const x1 = 36 + leftIdx * 376 + 172;
    const x2 = 36 + rightIdx * 376 + 172;
    const yEnd = 70;
    const midX = (x1 + x2) / 2;
    const ctrlY = -14;

    // Deterministic pulse traveler along quadratic Bezier
    const u = (Math.sin(t * 2.4) + 1) / 2;
    const omt = 1 - u;
    const px = omt * omt * x1 + 2 * omt * u * midX + u * u * x2;
    const py = omt * omt * yEnd + 2 * omt * u * ctrlY + u * u * yEnd;

    dom.arcOverlay.innerHTML = `
      <defs>
        <linearGradient id="dmArcGrad" x1="0%" y1="0%" x2="100%" y2="0%">
          <stop offset="0%" stop-color="#D4A373"/>
          <stop offset="50%" stop-color="#812920"/>
          <stop offset="100%" stop-color="#D4A373"/>
        </linearGradient>
        <filter id="dmGlow" x="-20%" y="-20%" width="140%" height="140%">
          <feGaussianBlur stdDeviation="4" result="blur"/>
          <feMerge>
            <feMergeNode in="blur"/>
            <feMergeNode in="SourceGraphic"/>
          </feMerge>
        </filter>
      </defs>
      <path d="M ${x1} ${yEnd} Q ${midX} ${ctrlY} ${x2} ${yEnd}"
            stroke="url(#dmArcGrad)" stroke-width="5" stroke-dasharray="10 6"
            stroke-linecap="round" fill="none" filter="url(#dmGlow)"/>
      <circle cx="${x1}" cy="${yEnd}" r="6" fill="#D4A373" stroke="#FFFFFF" stroke-width="2"/>
      <circle cx="${x2}" cy="${yEnd}" r="6" fill="#D4A373" stroke="#FFFFFF" stroke-width="2"/>
      <circle cx="${px.toFixed(1)}" cy="${py.toFixed(1)}" r="7.5" fill="#FDE68A" stroke="#812920" stroke-width="2.5" filter="url(#dmGlow)"/>
    `;

    dom.dmArcBanner.style.display = "inline-flex";
    dom.dmArcBanner.style.left = `${midX}px`;
    dom.dmArcBanner.innerHTML = `<span>🔒 แชทส่วนตัว 1-ต่อ-1 • ${escapeHtml(phoneA.name)} ↔ ${escapeHtml(phoneB.name)}</span>`;
  }

  function renderIntroOverlay(t, introDuration) {
    if (!dom.introOverlay) return;
    if (t >= introDuration || introDuration <= 0) {
      dom.introOverlay.style.display = "none";
      return;
    }

    const p = Math.max(0, Math.min(1, t / introDuration));
    let opacity = 1;
    let scale = 1;
    if (p < 0.14) {
      const k = p / 0.14;
      opacity = k;
      scale = 0.94 + 0.06 * k;
    } else if (p > 0.78) {
      const k = (p - 0.78) / 0.22;
      opacity = 1 - k;
      scale = 1 - 0.06 * k;
    }

    const phones = getTimelinePhones();
    dom.introOverlay.style.display = "flex";
    dom.introOverlay.style.opacity = opacity.toFixed(3);
    dom.introOverlay.innerHTML = `
      <div class="intro-card" style="transform:scale(${scale.toFixed(4)})">
        <div class="intro-kicker">✨ 4K 5-Phone Interactive Showcase • ปลอดลิขสิทธิ์ 100%</div>
        <h2 class="intro-title">BC Ai Chat</h2>
        <div class="intro-subtitle">แชทส่วนตัว แก๊งเพื่อน ครอบครัว &amp; ผู้ช่วย AI — ครบจบในธีมบ้านเชียง</div>
        <div class="intro-cast-row">
          ${phones
            .map(
              (ph) => `
            <span class="cast-pill">
              <span class="nameplate-dot" style="background:${escapeHtml(ph.avatarColor)}"></span>
              <span>${escapeHtml(ph.name)}</span>
              <span style="opacity:0.65;font-size:13px;">${escapeHtml(ph.bcId)}</span>
            </span>
          `
            )
            .join("")}
          <span class="cast-pill" style="background:#EEF2FF;border-color:#A5B4FC;color:#312E81;">
            <span>🤖 BC AI ผู้ช่วยส่วนตัว</span>
          </span>
        </div>
        <div class="intro-tags">
          <span class="intro-tag">🔒 แชทลับล็อก PIN</span>
          <span class="intro-tag">💨 ยกเลิกส่งไร้ร่องรอย</span>
          <span class="intro-tag">🛡️ ไฟล์ &amp; รูป HD ไม่หมดอายุ</span>
          <span class="intro-tag">📊 โพลสด &amp; RSVP</span>
          <span class="intro-tag">🎨 7 ธีมไทย &amp; โทนมืด</span>
        </div>
      </div>
    `;
  }

  function renderOutroOverlay(t, outroStart, totalDuration) {
    if (!dom.outroOverlay) return;
    if (t < outroStart) {
      dom.outroOverlay.style.display = "none";
      return;
    }

    const span = Math.max(1, totalDuration - outroStart);
    const p = Math.max(0, Math.min(1, (t - outroStart) / span));
    const opacity = Math.min(1, p / 0.14);
    const activeIdx = Math.min(7, Math.floor(p * 8));

    const rawFeatures =
      Array.isArray(state.timeline.recapFeatures) && state.timeline.recapFeatures.length === 8
        ? state.timeline.recapFeatures
        : DEFAULT_RECAP_FEATURES;

    const features = rawFeatures.map((f, idx) =>
      typeof f === "string"
        ? { title: f, desc: DEFAULT_RECAP_FEATURES[idx]?.desc || "" }
        : { title: f.title || DEFAULT_RECAP_FEATURES[idx].title, desc: f.desc || "" }
    );

    dom.outroOverlay.style.display = "flex";
    dom.outroOverlay.style.opacity = opacity.toFixed(3);
    dom.outroOverlay.innerHTML = `
      <div class="outro-card">
        <div class="outro-header">
          <div class="outro-title">สรุป 8 จุดเด่นของ BC Ai Chat — แอปแชทส่วนตัวของคนไทย</div>
          <div class="outro-badge">ธีมบ้านเชียง • ปลอดลิขสิทธิ์ 100%</div>
        </div>
        <div class="outro-grid">
          ${features
            .map(
              (ft, idx) => `
            <div class="recap-item ${idx === activeIdx ? "is-highlighted" : ""}">
              <div class="recap-num-row">
                <span class="recap-num">${idx + 1}</span>
                <span class="recap-title">${escapeHtml(ft.title)}</span>
              </div>
              <div class="recap-desc">${escapeHtml(ft.desc)}</div>
            </div>
          `
            )
            .join("")}
        </div>
        <div class="outro-footer">
          <span>📱 มือถือ (Android / iOS) • 💻 เดสก์ท็อป (Windows / macOS) • 🌐 เว็บแอป</span>
          <span>🤖 พร้อม 🤖 BC AI ผู้ช่วยส่วนตัวในแชทกลุ่มและ 1-ต่อ-1</span>
        </div>
      </div>
    `;
  }

  function renderSubtitleBar(activeLine, mode) {
    if (!dom.subtitleInner) return;
    if (!activeLine) {
      const msg =
        mode === "intro"
          ? "BC Ai Chat — แชทส่วนตัว แก๊งเพื่อน และผู้ช่วย AI บน 5 มือถือจริงพร้อมกัน"
          : "BC Ai Chat — ครบจบในธีมบ้านเชียง สบายตา ปลอดภัย ไร้ป๊อปอัป";
      dom.subtitleInner.innerHTML = `<div class="subtitle-idle">${escapeHtml(msg)}</div>`;
      return;
    }

    const sp = getSpeakerMeta(activeLine.speaker);
    const cleanText = stripDisplayMarkup(
      activeLine.displayText || activeLine.text || activeLine.subtitle || ""
    );
    const isCompact = cleanText.length > 66;

    dom.subtitleInner.innerHTML = `
      <div class="subtitle-speaker-badge" style="background:${escapeHtml(sp.color)}">
        <span class="subtitle-speaker-dot"></span>
        <span>${escapeHtml(activeLine.speakerName || sp.name)}</span>
      </div>
      <div class="subtitle-text ${isCompact ? "is-compact" : ""}">${escapeHtml(cleanText)}</div>
    `;
  }

  function computeTimelineState(t) {
    const tl = state.timeline || BUILTIN_SHOWCASE_TIMELINE;
    const introDuration = typeof tl.introDuration === "number" ? tl.introDuration : 4.2;
    const totalDuration = typeof tl.totalDuration === "number" ? tl.totalDuration : 49.0;
    const outroStart = typeof tl.outroStart === "number" ? tl.outroStart : Math.max(introDuration, totalDuration - 5.5);

    const lines = Array.isArray(tl.lines) ? tl.lines : [];
    const chapters = Array.isArray(tl.chapters) ? tl.chapters : [];
    const events = Array.isArray(tl.uiEvents) ? tl.uiEvents : [];

    // Find active line and latest context line
    let activeLine = null;
    let contextLine = null;
    for (const l of lines) {
      const st = typeof l.start === "number" ? l.start : l.startTime ?? 0;
      const en = typeof l.end === "number" ? l.end : l.endTime ?? st + 3;
      if (st <= t) {
        contextLine = l;
      }
      if (st <= t && t <= en) {
        activeLine = l;
      }
    }

    // Active chapter
    let activeChapter = null;
    let activeChapterIdx = 0;
    for (let i = 0; i < chapters.length; i++) {
      const ch = chapters[i];
      if (ch.start <= t && (t < ch.end || i === chapters.length - 1)) {
        activeChapter = ch;
        activeChapterIdx = i;
        break;
      }
    }

    // Determine mode & dmPair
    let mode = "group";
    let dmPair = null;
    if (t < introDuration) {
      mode = "intro";
    } else if (t >= outroStart) {
      mode = "outro";
    } else if (contextLine && contextLine.mode) {
      mode = contextLine.mode;
      dmPair = contextLine.dmPair || null;
    } else if (activeChapter) {
      mode = activeChapter.mode || "group";
      dmPair = activeChapter.dmPair || null;
    }

    if (mode === "dm" && (!Array.isArray(dmPair) || dmPair.length !== 2)) {
      if (activeChapter && Array.isArray(activeChapter.dmPair)) {
        dmPair = activeChapter.dmPair;
      }
    }

    // Determine theme & roomTone by latest timestamp <= t across lines & theme_change events
    let themeId = "ban_chiang";
    let themeTime = -1;
    let roomToneId = "ban_chiang_cream";
    let roomToneTime = -1;

    for (const l of lines) {
      const st = typeof l.start === "number" ? l.start : 0;
      if (st <= t) {
        if (l.theme && st >= themeTime) {
          themeId = l.theme;
          themeTime = st;
        }
        if (l.roomTone && st >= roomToneTime) {
          roomToneId = l.roomTone;
          roomToneTime = st;
        }
      }
    }

    for (const ev of events) {
      const et = getEventTime(ev);
      if (et <= t && getEventKind(ev) === "theme_change") {
        if (ev.theme && et >= themeTime) {
          themeId = ev.theme;
          themeTime = et;
        }
        if (ev.roomTone && et >= roomToneTime) {
          roomToneId = ev.roomTone;
          roomToneTime = et;
        }
      }
    }

    // Collect auxiliary override maps up to time t (unlock_pin, unsend, notebook_focus)
    const unlockMap = {};
    const unsendMap = {};
    const notebookByPhone = {};

    for (const ev of events) {
      const et = getEventTime(ev);
      if (et > t) continue;
      const kind = getEventKind(ev);
      if (kind === "unlock_pin" && ev.msgId) {
        unlockMap[ev.msgId] = et;
      } else if (kind === "unsend" && ev.msgId) {
        unsendMap[ev.msgId] = et;
      } else if (kind === "notebook_focus") {
        const target = normalizeActorId(ev.phone || ev.phoneId || "mind");
        if (!ev.until || t < ev.until) {
          notebookByPhone[target] = ev;
        }
      }
    }

    return {
      t,
      introDuration,
      outroStart,
      totalDuration,
      activeLine,
      contextLine,
      activeChapter,
      activeChapterIdx,
      chaptersCount: chapters.length || 6,
      mode,
      dmPair: dmPair ? dmPair.map(normalizeActorId) : null,
      themeId,
      roomToneId,
      events,
      aux: { unlockMap, unsendMap, notebookByPhone },
    };
  }

  function renderAtTime(rawSeconds) {
    const tl = state.timeline || BUILTIN_SHOWCASE_TIMELINE;
    const maxT = typeof tl.totalDuration === "number" ? tl.totalDuration : 49.0;
    const t = Math.max(0, Math.min(maxT, Number(rawSeconds) || 0));
    state.currentTime = t;

    const cs = computeTimelineState(t);
    state.mode = cs.mode;
    state.dmPair = cs.dmPair;
    state.activeSpeaker = cs.activeLine ? normalizeActorId(cs.activeLine.speaker) : null;

    applyTheme(cs.themeId, cs.roomToneId);

    // Top Header Pills & Progress
    if (dom.modePill) {
      dom.modePill.classList.remove("is-dm", "is-ai");
      if (cs.mode === "dm" && cs.dmPair) {
        const a = getSpeakerMeta(cs.dmPair[0]).name;
        const b = getSpeakerMeta(cs.dmPair[1]).name;
        dom.modePill.textContent = `🔒 แชทส่วนตัว 1-ต่อ-1 ${a} ↔ ${b}`;
        dom.modePill.classList.add("is-dm");
      } else if (state.activeSpeaker === "ai") {
        dom.modePill.textContent = "🤖 BC AI ผู้ช่วยส่วนตัวกำลังตอบสด";
        dom.modePill.classList.add("is-ai");
      } else if (cs.mode === "outro") {
        dom.modePill.textContent = "✨ สรุป 8 ความสามารถ BC Ai Chat";
      } else if (cs.mode === "intro") {
        dom.modePill.textContent = "✨ เปิดตัว BC Ai Chat 4K";
      } else {
        dom.modePill.textContent = "👨‍👩‍👧‍👦 แชทกลุ่ม 5 เครื่องพร้อมกัน";
      }
    }

    if (dom.featurePill) {
      const fp =
        (cs.activeLine && (cs.activeLine.featurePill || cs.activeLine.feature)) ||
        (cs.contextLine && (cs.contextLine.featurePill || cs.contextLine.feature)) ||
        (cs.activeChapter && cs.activeChapter.featurePill) ||
        "ธีมบ้านเชียง • 4 แท็บ Mobile-First";
      dom.featurePill.textContent = `✨ ${fp}`;
    }

    if (dom.chapterLabel) {
      dom.chapterLabel.textContent = `ฉาก ${Math.min(cs.activeChapterIdx + 1, cs.chaptersCount)}/${cs.chaptersCount}`;
    }
    if (dom.timeLabel) {
      dom.timeLabel.textContent = `${formatMmSs(t)} / ${formatMmSs(cs.totalDuration)}`;
    }
    if (dom.progressFill) {
      const pct = cs.totalDuration > 0 ? (t / cs.totalDuration) * 100 : 0;
      dom.progressFill.style.width = `${pct.toFixed(2)}%`;
    }

    // AI Copilot Banner
    if (dom.aiBanner) {
      if (state.activeSpeaker === "ai" && cs.mode !== "intro" && cs.mode !== "outro") {
        const bars = [0, 1, 2, 3, 4, 5]
          .map((i) => {
            const h = 6 + Math.round(Math.abs(Math.sin(t * 8.5 + i * 0.9)) * 12);
            return `<span class="ai-wave-bar" style="height:${h}px"></span>`;
          })
          .join("");
        dom.aiBanner.style.display = "inline-flex";
        dom.aiBanner.innerHTML = `
          <span>🤖 BC AI ผู้ช่วยส่วนตัวกำลังตอบคำถาม...</span>
          <span class="ai-wave-bars">${bars}</span>
        `;
      } else {
        dom.aiBanner.style.display = "none";
      }
    }

    // DM Arc Overlay
    if (cs.mode === "dm" && cs.dmPair) {
      renderDmArcOverlay(cs.dmPair, t);
    } else {
      renderDmArcOverlay(null, t);
    }

    // Update All 5 Phones
    const phones = getTimelinePhones();
    const dmRoomId = cs.mode === "dm" && cs.dmPair ? `dm_${cs.dmPair[0]}_${cs.dmPair[1]}` : null;
    const altDmRoomId = cs.mode === "dm" && cs.dmPair ? `dm_${cs.dmPair[1]}_${cs.dmPair[0]}` : null;

    phones.forEach((phone) => {
      const el = dom.phoneEls[phone.id];
      if (!el) return;

      const isSpeaking = state.activeSpeaker === phone.id && cs.mode !== "intro" && cs.mode !== "outro";
      const isInDm = cs.mode === "dm" && cs.dmPair && cs.dmPair.includes(phone.id);
      const isDimmed = cs.mode === "dm" && !isInDm;

      el.slot.classList.toggle("is-speaking", isSpeaking);
      el.slot.classList.toggle("is-dm-active", Boolean(isInDm));
      el.slot.classList.toggle("is-dimmed", isDimmed);

      // Deterministic EQ bar heights when speaking
      if (isSpeaking) {
        el.eqBars.forEach((bar, idx) => {
          const h = 4 + Math.round(Math.abs(Math.sin(t * 10 + idx * 1.1)) * 10);
          bar.style.height = `${h}px`;
        });
      }

      // Screen Mode: chat vs notes
      const lineScreenMode =
        cs.contextLine && cs.contextLine.screenMode && cs.contextLine.screenMode[phone.id];
      const noteEv = cs.aux.notebookByPhone[phone.id];
      const showNotes = lineScreenMode === "notes" || Boolean(noteEv);

      // Update Bottom Tabs active highlight
      el.tabs.forEach((tabEl) => {
        const tabId = tabEl.dataset.tab;
        const active = showNotes ? tabId === "notes" : tabId === "chats";
        tabEl.classList.toggle("is-active", active);
      });

      // Determine active room for this phone
      const activeRoom = isInDm ? dmRoomId : "group";

      // Update AppBar header per phone perspective
      if (showNotes) {
        el.roomAvatar.textContent = "📓";
        el.roomAvatar.style.background = "var(--bc-primary)";
        el.roomTitle.textContent = "สมุดบันทึก BC ส่วนตัว";
        el.roomSub.textContent = `${phone.name} • คลังบันทึกถาวร`;
        el.roomPill.textContent = "ส่วนตัว";
      } else if (isInDm && cs.dmPair) {
        const partnerId = cs.dmPair[0] === phone.id ? cs.dmPair[1] : cs.dmPair[0];
        const partner = getSpeakerMeta(partnerId);
        el.roomAvatar.textContent = partner.name.charAt(0);
        el.roomAvatar.style.background = partner.color;
        el.roomTitle.textContent = partner.name;
        el.roomSub.textContent = "🔒 แชทส่วนตัว 1-ต่อ-1";
        el.roomPill.textContent = "1-ต่อ-1";
      } else {
        el.roomAvatar.textContent = "ก";
        el.roomAvatar.style.background = "linear-gradient(135deg, var(--bc-primary), var(--bc-deep))";
        el.roomTitle.textContent = "แก๊งเพื่อนสนิท 5 คน + BC AI";
        el.roomSub.textContent = "5 สมาชิก + 🤖 BC AI";
        el.roomPill.textContent = "กลุ่ม";
      }

      // Folder Strip
      const activeFolder =
        (cs.contextLine && cs.contextLine.activeFolderChip) || (isInDm ? "personal" : "group");
      renderFolderStrip(el, activeFolder);

      if (showNotes) {
        el.folderStrip.style.display = "none";
        el.chatStream.style.display = "none";
        el.composer.style.display = "none";
        el.inlineTray.style.display = "none";
        el.notesScreen.style.display = "flex";
        renderNotesScreen(el, phone, noteEv);
      } else {
        el.folderStrip.style.display = "flex";
        el.notesScreen.style.display = "none";
        el.chatStream.style.display = "flex";
        el.composer.style.display = "flex";

        // Filter messages belonging to this room with ev.at <= t
        const roomEvents = cs.events.filter((ev) => {
          const et = getEventTime(ev);
          if (et > t) return false;
          const kind = getEventKind(ev);
          if (
            kind === "theme_change" ||
            kind === "unlock_pin" ||
            kind === "unsend" ||
            kind === "notebook_focus" ||
            kind === "typing" ||
            kind === "inline_tray"
          ) {
            return false;
          }
          const evRoom = normalizeRoomId(ev.room || ev.roomId);
          if (isInDm) {
            return evRoom === dmRoomId || evRoom === altDmRoomId;
          }
          return evRoom === "group" || !ev.room;
        });

        // Show recent messages cleanly
        const visibleMsgs = roomEvents.slice(-7);
        const bubblesHtml = visibleMsgs
          .map((ev) => renderMessageBubbleHtml(ev, phone.id, t, cs.aux))
          .filter(Boolean)
          .join("");

        // Typing indicator right before next message appears (0.6s window)
        let typingHtml = "";
        const upcoming = cs.events.find((ev) => {
          const et = getEventTime(ev);
          const evRoom = normalizeRoomId(ev.room || ev.roomId);
          const sameRoom = isInDm ? evRoom === dmRoomId || evRoom === altDmRoomId : evRoom === "group";
          return (
            sameRoom &&
            et > t &&
            et - t <= 0.65 &&
            getEventKind(ev) !== "theme_change" &&
            normalizeActorId(ev.sender) !== phone.id
          );
        });
        if (upcoming) {
          const sp = getSpeakerMeta(upcoming.sender);
          typingHtml = `
            <div class="typing-row">
              <span>${escapeHtml(sp.name)} กำลังพิมพ์</span>
              <span class="typing-dots">
                <span class="typing-dot" style="opacity:${(0.35 + 0.65 * Math.abs(Math.sin(t * 9))).toFixed(2)}"></span>
                <span class="typing-dot" style="opacity:${(0.35 + 0.65 * Math.abs(Math.sin(t * 9 + 1))).toFixed(2)}"></span>
                <span class="typing-dot" style="opacity:${(0.35 + 0.65 * Math.abs(Math.sin(t * 9 + 2))).toFixed(2)}"></span>
              </span>
            </div>
          `;
        }

        el.chatStream.innerHTML = `
          <div class="room-date-divider">${isInDm ? "แชทส่วนตัว • เข้ารหัสปลอดภัย" : "วันนี้ • แก๊งเพื่อน 5 คน + BC AI"}</div>
          ${bubblesHtml}
          ${typingHtml}
        `;
        el.chatStream.scrollTop = el.chatStream.scrollHeight;

        // Composer typing draft when this phone is about to send within 0.65s
        const ownUpcoming = cs.events.find((ev) => {
          const et = getEventTime(ev);
          const evRoom = normalizeRoomId(ev.room || ev.roomId);
          const sameRoom = isInDm ? evRoom === dmRoomId || evRoom === altDmRoomId : evRoom === "group";
          return (
            sameRoom &&
            et > t &&
            et - t <= 0.65 &&
            normalizeActorId(ev.sender) === phone.id &&
            ev.text
          );
        });
        if (ownUpcoming) {
          const rawDraft = stripDisplayMarkup(ownUpcoming.text);
          const chars = Math.max(4, Math.floor(rawDraft.length * (1 - (ownUpcoming.at - t) / 0.65)));
          el.compInput.textContent = rawDraft.slice(0, chars);
          el.compInput.style.color = "var(--bc-text)";
        } else {
          el.compInput.textContent = "พิมพ์ข้อความ...";
          el.compInput.style.color = "";
        }

        // Inline Tray (zero popups!)
        let trayForPhone = null;
        if (cs.activeLine && cs.activeLine.inlineTray) {
          const tr = cs.activeLine.inlineTray;
          if (typeof tr === "string" && phone.id === state.activeSpeaker) {
            trayForPhone = tr;
          } else if (typeof tr === "object" && normalizeActorId(tr.phone || tr.phoneId) === phone.id) {
            trayForPhone = tr;
          }
        }
        renderInlineTray(el, trayForPhone);
      }
    });

    // Intro / Outro Overlays
    renderIntroOverlay(t, cs.introDuration);
    renderOutroOverlay(t, cs.outroStart, cs.totalDuration);

    // Subtitle Bar
    renderSubtitleBar(cs.activeLine, cs.mode);
  }

  function renderThumbnail() {
    state.isThumbnail = true;
    document.body.classList.add("mode-thumbnail");
    const tl = state.timeline || BUILTIN_SHOWCASE_TIMELINE;
    const events = Array.isArray(tl.uiEvents) ? tl.uiEvents : [];
    const lines = Array.isArray(tl.lines) ? tl.lines : [];

    // Pick a vibrant group-chat timestamp (e.g., right after AI reply / poll / split_bill)
    const richEvent =
      events.find((e) => getEventKind(e) === "rich_card") ||
      events.find((e) => getEventKind(e) === "poll") ||
      events.find((e) => getEventKind(e) === "ai_reply");
    const groupLine = lines.find(
      (l) => l.scene === "group_ai_poll" || l.scene === "group_miniapp_theme"
    );

    let targetT = 37.5;
    if (richEvent && typeof getEventTime(richEvent) === "number") {
      targetT = getEventTime(richEvent) + 0.5;
    } else if (groupLine) {
      targetT = (groupLine.start || 0) + 1.0;
    } else {
      const introD = typeof tl.introDuration === "number" ? tl.introDuration : 4.2;
      const outroS = typeof tl.outroStart === "number" ? tl.outroStart : 43.0;
      targetT = (introD + outroS) / 2;
    }

    renderAtTime(targetT);
    // Lock iconic Ban Chiang theme + clear overlays for crisp 4K YouTube Thumbnail
    applyTheme("ban_chiang", "ban_chiang_cream");
    if (dom.dmArcBanner) dom.dmArcBanner.style.display = "none";
    if (dom.aiBanner) dom.aiBanner.style.display = "none";
    if (dom.arcOverlay) dom.arcOverlay.innerHTML = "";
    Object.values(dom.phoneEls).forEach((el) => {
      el.slot.classList.remove("is-dimmed");
      el.slot.classList.remove("is-speaking");
    });
  }

  function initTimeline(data) {
    if (data && typeof data === "object") {
      state.timeline = data;
      state.explicitlyInitialized = true;
    }
    buildPhonesDom();

    const params = new URLSearchParams(window.location.search);
    if (params.get("thumbnail") === "1") {
      renderThumbnail();
    } else {
      const startT = Number(params.get("t")) || 0;
      renderAtTime(startT);
    }

    return {
      fps: state.timeline.fps || 30,
      width: state.timeline.width || 3840,
      height: state.timeline.height || 2160,
      introDuration: state.timeline.introDuration || 4.2,
      outroStart: state.timeline.outroStart || 43.0,
      totalDuration: state.timeline.totalDuration || 49.0,
      linesCount: (state.timeline.lines || []).length,
      eventsCount: (state.timeline.uiEvents || []).length,
    };
  }

  function getStageState() {
    return {
      currentTime: state.currentTime,
      activeTheme: state.activeTheme,
      activeRoomTone: state.activeRoomTone,
      mode: state.mode,
      activeSpeaker: state.activeSpeaker,
      dmPair: state.dmPair,
      isThumbnail: state.isThumbnail,
      scrollWidth: document.documentElement.scrollWidth,
      scrollHeight: document.documentElement.scrollHeight,
    };
  }

  async function bootstrap() {
    dom.root = document.getElementById("stage-root");
    dom.phonesRow = document.getElementById("phones-row");
    dom.arcOverlay = document.getElementById("stage-arc-overlay");
    dom.dmArcBanner = document.getElementById("dm-arc-banner");
    dom.aiBanner = document.getElementById("ai-copilot-banner");
    dom.introOverlay = document.getElementById("intro-overlay");
    dom.outroOverlay = document.getElementById("outro-overlay");
    dom.subtitleInner = document.getElementById("subtitle-inner");
    dom.modePill = document.getElementById("mode-pill");
    dom.featurePill = document.getElementById("feature-pill");
    dom.themeChipLabel = document.getElementById("theme-chip-label");
    dom.chapterLabel = document.getElementById("chapter-label");
    dom.timeLabel = document.getElementById("time-label");
    dom.progressFill = document.getElementById("progress-fill");

    // Initialize immediately with built-in timeline so page is ready without flicker
    buildPhonesDom();
    const params = new URLSearchParams(window.location.search);
    if (params.get("thumbnail") === "1") {
      renderThumbnail();
    } else {
      renderAtTime(Number(params.get("t")) || 0);
    }

    // Auto-load timeline.json ONLY when served over HTTP/HTTPS (never fails on file://)
    if (window.location.protocol === "http:" || window.location.protocol === "https:") {
      const explicitUrl = params.get("timeline");
      const inStageDir = window.location.pathname.includes("/stage/");
      const candidates = explicitUrl
        ? [explicitUrl]
        : inStageDir
          ? ["../data/timeline.json", "./data/timeline.json"]
          : ["./data/timeline.json", "../data/timeline.json"];
      for (const url of candidates) {
        if (state.explicitlyInitialized) break;
        try {
          const resp = await fetch(url, { cache: "no-store" });
          if (resp.ok && !state.explicitlyInitialized) {
            const loaded = await resp.json();
            if (loaded && Array.isArray(loaded.lines)) {
              state.timeline = loaded;
              buildPhonesDom();
              if (params.get("thumbnail") === "1") {
                renderThumbnail();
              } else {
                renderAtTime(Number(params.get("t")) || 0);
              }
              break;
            }
          }
        } catch {
          // Silent fallback to built-in demo timeline or explicit initTimeline()
        }
      }
    }
  }

  window.initTimeline = initTimeline;
  window.renderAtTime = renderAtTime;
  window.renderThumbnail = renderThumbnail;
  window.getStageState = getStageState;

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", bootstrap);
  } else {
    void bootstrap();
  }
})();
