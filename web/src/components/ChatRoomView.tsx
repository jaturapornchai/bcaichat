"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import {
  AlertTriangle,
  Archive,
  ArrowLeft,
  BarChart3,
  BellOff,
  Bot,
  Calendar,
  Check,
  CheckCheck,
  Eraser,
  Eye,
  EyeOff,
  FileText,
  FolderOpen,
  Image as ImageIcon,
  Layers,
  Lock,
  Mic,
  Palette,
  Paperclip,
  Pin,
  Reply,
  Search,
  Send,
  Shield,
  Smile,
  Sparkles,
  Square,
  StickyNote,
  Unlock,
  Users,
  Wand2,
  X,
} from "lucide-react";
import { api, formatFileSize, formatThaiTime, getTabToken, resolveMediaUrl } from "@/lib/api";
import { playChime } from "@/lib/sound";
import {
  ORIGINAL_THAI_STICKERS,
  REACTION_EMOJIS,
  ROOM_TONES,
} from "@/lib/themes";
import type {
  AiAssistResult,
  AiSummaryResult,
  ChatMessage,
  Conversation,
  FriendItem,
  MiniAppItem,
  RoomToneId,
  UserProfile,
} from "@/lib/types";
import { RoomSideModal, type SidePanelTab } from "./RoomSideModal";
import { StickerArt, UserAvatar } from "./StickerArt";

const MINIAPP_SLUG_MAP: Record<string, string> = {
  ai_companion: "ai",
  split_bill: "split",
  trip_planner: "trip",
  gift_wishlist: "wishlist",
  hangout_invite: "hangout",
  ai_copilot: "ai",
  leave_approval: "leave",
  quick_quotation: "quotation",
  expense_claim: "expense",
  crm_queue: "booking",
};

export function resolveMiniAppIframeUrl(app: MiniAppItem, convId: string): string {
  let path = "";
  if (app.entry_url) {
    try {
      const parsed = new URL(app.entry_url, "http://127.0.0.1:8096");
      if (parsed.pathname.startsWith("/miniapp/")) {
        path = parsed.pathname;
      }
    } catch {
      // Fallback to slug map below
    }
  }
  if (!path) {
    const slug = MINIAPP_SLUG_MAP[app.app_code] || "ai";
    path = `/miniapp/${encodeURIComponent(slug)}`;
  }
  return `${path}?token=${encodeURIComponent(getTabToken())}&conv_id=${encodeURIComponent(convId)}`;
}

interface ChatRoomViewProps {
  conversation: Conversation;
  messages: ChatMessage[];
  currentUser: UserProfile;
  friends: FriendItem[];
  miniApps: MiniAppItem[];
  roomTone: RoomToneId;
  onChangeRoomTone: (tone: RoomToneId) => void;
  onConversationUpdated: () => Promise<void>;
  onRefreshMessages: () => Promise<void>;
  onOpenMiniApp: (app: MiniAppItem) => void;
  runningMiniApp?: MiniAppItem | null;
  onCloseMiniApp?: () => void;
  onBackMobile?: () => void;
  onNotify: (msg: string) => void;
}

export function ChatRoomView({
  conversation,
  messages,
  currentUser,
  friends,
  miniApps,
  roomTone,
  onChangeRoomTone,
  onConversationUpdated,
  onRefreshMessages,
  onOpenMiniApp,
  runningMiniApp,
  onCloseMiniApp,
  onBackMobile,
  onNotify,
}: ChatRoomViewProps) {
  const [draft, setDraft] = useState("");
  const [sending, setSending] = useState(false);
  const [uploading, setUploading] = useState(false);
  const [replyTarget, setReplyTarget] = useState<ChatMessage | null>(null);
  const [showStickerPicker, setShowStickerPicker] = useState(false);
  const [showToneMenu, setShowToneMenu] = useState(false);
  const [showRoomSearch, setShowRoomSearch] = useState(false);
  const [roomSearchQuery, setRoomSearchQuery] = useState("");

  // Confidentiality & security
  const [isConfidential, setIsConfidential] = useState(false);
  const [confidentialPin, setConfidentialPin] = useState("1234");
  const [unlockedIds, setUnlockedIds] = useState<Record<string, boolean>>({});
  const [pinPromptMsgId, setPinPromptMsgId] = useState<string | null>(null);
  const [pinAttempt, setPinAttempt] = useState("");
  const [showWatermark, setShowWatermark] = useState(true);

  // Priority urgent topic
  const [isUrgent, setIsUrgent] = useState(false);

  // @Mention autocomplete
  const [mentionQuery, setMentionQuery] = useState<string | null>(null);
  const [selectedMentions, setSelectedMentions] = useState<string[]>([]);

  // Voice recording
  const [isRecording, setIsRecording] = useState(false);
  const [recordSeconds, setRecordSeconds] = useState(0);
  const mediaRecorderRef = useRef<MediaRecorder | null>(null);
  const recordChunksRef = useRef<Blob[]>([]);
  const recordTimerRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const recordStartRef = useRef<number>(0);

  // Inline side panels & inline AI / Card trays
  const [sideTab, setSideTab] = useState<SidePanelTab | null>(null);
  const [aiModalMode, setAiModalMode] = useState<"summary" | "assist" | null>(null);
  const [aiLoading, setAiLoading] = useState(false);
  const [aiSummary, setAiSummary] = useState<AiSummaryResult | null>(null);
  const [aiAssist, setAiAssist] = useState<AiAssistResult | null>(null);
  const [assistMode, setAssistMode] = useState<
    "polish" | "formal" | "suggest_reply" | "translate_en" | "action_plan"
  >("suggest_reply");

  // Inline Rich Card composer
  const [showCardModal, setShowCardModal] = useState(false);
  const [cardTitle, setCardTitle] = useState("แชร์ทริป / หารค่าข้าว");
  const [cardHeading, setCardHeading] = useState("มื้อเย็นหมูกระทะกับแก๊งเสาร์นี้");
  const [cardSubtitle, setCardSubtitle] = useState("เจอกัน 18:00 น. ร้านเดิม");
  const [cardAmount, setCardAmount] = useState("คนละ 299 บาท");

  const scrollEndRef = useRef<HTMLDivElement | null>(null);
  const inputRef = useRef<HTMLInputElement | null>(null);
  const toneOption = ROOM_TONES[roomTone] || ROOM_TONES.ban_chiang_cream;

  useEffect(() => {
    scrollEndRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages.length, conversation.id]);

  useEffect(() => {
    setReplyTarget(null);
    setShowStickerPicker(false);
    setRoomSearchQuery("");
    setShowRoomSearch(false);
    setMentionQuery(null);
    setShowCardModal(false);
    setAiModalMode(null);
    setShowToneMenu(false);
  }, [conversation.id]);

  const mentionCandidates = useMemo(() => {
    const base = [
      { id: "all", label: "@all", name: "แจ้งเตือนทุกคนในห้อง" },
      { id: "user_ai", label: "@bc.ai", name: "🤖 BC AI ผู้ช่วยส่วนตัว (@ai)" },
      ...conversation.members
        .filter((m) => m.id !== "user_ai")
        .map((m) => ({
          id: m.id,
          label: m.bc_id.startsWith("@") ? m.bc_id : `@${m.bc_id}`,
          name: m.display_name,
        })),
    ];
    if (mentionQuery === null) return [];
    const q = mentionQuery.toLowerCase();
    return base.filter(
      (c) => c.label.toLowerCase().includes(q) || c.name.toLowerCase().includes(q)
    );
  }, [conversation.members, mentionQuery]);

  const filteredMessages = useMemo(() => {
    const q = roomSearchQuery.trim().toLowerCase();
    if (!q) return messages;
    return messages.filter(
      (m) =>
        m.content.toLowerCase().includes(q) ||
        m.sender_name.toLowerCase().includes(q) ||
        m.attachment?.file_name?.toLowerCase().includes(q)
    );
  }, [messages, roomSearchQuery]);

  const handleDraftChange = (value: string) => {
    setDraft(value);
    const match = value.match(/(?:^|\s)@([^\s]*)$/);
    if (match) {
      setMentionQuery(match[1] || "");
    } else {
      setMentionQuery(null);
    }
  };

  const insertMention = (candidate: { id: string; label: string }) => {
    const updated = draft.replace(/@([^\s]*)$/, `${candidate.label} `);
    setDraft(updated);
    setSelectedMentions((prev) =>
      prev.includes(candidate.id) ? prev : [...prev, candidate.id]
    );
    setMentionQuery(null);
    inputRef.current?.focus();
  };

  const handleSendText = async (e?: React.FormEvent) => {
    e?.preventDefault();
    const text = draft.trim();
    if (!text || sending) return;
    setSending(true);
    setDraft("");
    setMentionQuery(null);
    const mentionsToSend = [...selectedMentions];
    setSelectedMentions([]);

    try {
      const sent = await api.sendMessage(conversation.id, {
        type: "text",
        content: text,
        reply_to_id: replyTarget?.id,
        is_confidential: isConfidential,
        confidential_pin: isConfidential && confidentialPin.trim() ? confidentialPin.trim() : undefined,
        priority: isUrgent ? "urgent" : "normal",
        task_status: isUrgent ? "open" : undefined,
        mentions: mentionsToSend.length > 0 ? mentionsToSend : undefined,
      });
      if (isConfidential) {
        setUnlockedIds((prev) => ({ ...prev, [sent.id]: true }));
      }
      setReplyTarget(null);
      setIsUrgent(false);
      playChime("sent");
      await onRefreshMessages();
      await onConversationUpdated();
    } catch (err) {
      setDraft(text);
      onNotify(err instanceof Error ? err.message : "ส่งข้อความไม่สำเร็จ");
    } finally {
      setSending(false);
    }
  };

  const handleSendSticker = async (code: string, label: string) => {
    setShowStickerPicker(false);
    try {
      await api.sendMessage(conversation.id, {
        type: "sticker",
        content: label,
        sticker_code: code,
        reply_to_id: replyTarget?.id,
        is_confidential: isConfidential,
      });
      setReplyTarget(null);
      playChime("sent");
      await onRefreshMessages();
      await onConversationUpdated();
    } catch (err) {
      onNotify(err instanceof Error ? err.message : "ส่งสติกเกอร์ไม่สำเร็จ");
    }
  };

  const handleFileUpload = async (file: File) => {
    setUploading(true);
    try {
      const att = await api.uploadFile(file, file.name, conversation.id);
      const isImg = att.mime_type.startsWith("image/");
      const isAudio = att.mime_type.startsWith("audio/");
      await api.sendMessage(conversation.id, {
        type: isImg ? "image" : isAudio ? "audio" : "file",
        content: file.name,
        attachment: att,
        reply_to_id: replyTarget?.id,
        is_confidential: isConfidential,
        confidential_pin: isConfidential && confidentialPin.trim() ? confidentialPin.trim() : undefined,
      });
      setReplyTarget(null);
      playChime("sent");
      await onRefreshMessages();
      await onConversationUpdated();
    } catch (err) {
      onNotify(err instanceof Error ? err.message : "อัปโหลดไฟล์ไม่สำเร็จ");
    } finally {
      setUploading(false);
    }
  };

  const handleToggleRecording = async () => {
    if (isRecording) {
      mediaRecorderRef.current?.stop();
      return;
    }
    try {
      if (typeof navigator === "undefined" || !navigator.mediaDevices?.getUserMedia) {
        throw new Error("เบราว์เซอร์ไม่รองรับการอัดเสียงไมโครโฟน");
      }
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      const recorder = new MediaRecorder(stream);
      recordChunksRef.current = [];
      recordStartRef.current = Date.now();
      setRecordSeconds(0);

      recorder.ondataavailable = (ev) => {
        if (ev.data.size > 0) recordChunksRef.current.push(ev.data);
      };
      recorder.onstop = async () => {
        stream.getTracks().forEach((t) => t.stop());
        if (recordTimerRef.current) clearInterval(recordTimerRef.current);
        setIsRecording(false);
        const dur = Math.max(1, Math.round((Date.now() - recordStartRef.current) / 1000));
        const blob = new Blob(recordChunksRef.current, { type: recorder.mimeType || "audio/webm" });
        if (blob.size > 0) {
          setUploading(true);
          try {
            const att = await api.uploadFile(
              blob,
              `voice_${Date.now()}.webm`,
              conversation.id
            );
            await api.sendMessage(conversation.id, {
              type: "audio",
              content: `ข้อความเสียง (${dur} วินาที)`,
              attachment: att,
              audio_duration_sec: dur,
              is_confidential: isConfidential,
            });
            await onRefreshMessages();
          } finally {
            setUploading(false);
          }
        }
      };

      mediaRecorderRef.current = recorder;
      recorder.start();
      setIsRecording(true);
      recordTimerRef.current = setInterval(() => {
        setRecordSeconds(Math.round((Date.now() - recordStartRef.current) / 1000));
      }, 500);
    } catch (err) {
      onNotify(err instanceof Error ? err.message : "ไม่สามารถเปิดไมโครโฟนได้");
    }
  };

  const handleSendRichCard = async (e: React.FormEvent) => {
    e.preventDefault();
    try {
      await api.sendMessage(conversation.id, {
        type: "rich_card",
        content: `[การ์ดโต้ตอบ] ${cardTitle} — ${cardAmount}`,
        card_payload: {
          app_code: "custom_rich_card",
          title: cardTitle,
          color_hex: "#812920",
          heading: cardHeading,
          subtitle: cardSubtitle,
          highlight_value: cardAmount,
          status: "รอเพื่อนตอบ",
          status_label: "รอเพื่อนตอบ",
        },
      });
      setShowCardModal(false);
      await onRefreshMessages();
      onNotify("ส่งการ์ดโต้ตอบเข้าห้องแชทแล้ว");
    } catch (err) {
      onNotify(err instanceof Error ? err.message : "ส่งการ์ดไม่สำเร็จ");
    }
  };

  const handleOpenAiSummary = async (postToChat = false) => {
    setSideTab(null);
    setShowCardModal(false);
    setAiModalMode("summary");
    setAiLoading(true);
    try {
      const res = await api.summarizeChat(conversation.id, postToChat);
      setAiSummary(res);
      if (postToChat) await onRefreshMessages();
    } catch (err) {
      onNotify(err instanceof Error ? err.message : "สรุปแชทไม่สำเร็จ");
    } finally {
      setAiLoading(false);
    }
  };

  const handleOpenAiAssist = async (
    mode: "polish" | "formal" | "suggest_reply" | "translate_en" | "action_plan"
  ) => {
    setSideTab(null);
    setShowCardModal(false);
    setAssistMode(mode);
    setAiModalMode("assist");
    setAiLoading(true);
    try {
      const res = await api.assistAi({
        conversation_id: conversation.id,
        prompt: draft.trim() || undefined,
        mode,
      });
      setAiAssist(res);
    } catch (err) {
      onNotify(err instanceof Error ? err.message : "เรียกผู้ช่วย AI ไม่สำเร็จ");
    } finally {
      setAiLoading(false);
    }
  };

  const handleReact = async (msgId: string, emoji: string) => {
    try {
      playChime("react");
      await api.reactMessage(msgId, emoji);
      await onRefreshMessages();
    } catch (err) {
      onNotify(err instanceof Error ? err.message : "ส่งความรู้สึกไม่สำเร็จ");
    }
  };

  const handleVotePoll = async (msgId: string, optionIds: string[]) => {
    try {
      await api.votePoll(msgId, optionIds);
      await onRefreshMessages();
    } catch (err) {
      onNotify(err instanceof Error ? err.message : "โหวตไม่สำเร็จ");
    }
  };

  const handleClosePoll = async (msgId: string) => {
    try {
      await api.closePoll(msgId);
      await onRefreshMessages();
    } catch (err) {
      onNotify(err instanceof Error ? err.message : "ปิดโพลไม่สำเร็จ");
    }
  };

  const handleRsvpEvent = async (
    msgId: string,
    status: "going" | "maybe" | "not_going"
  ) => {
    try {
      await api.rsvpEvent(msgId, status);
      await onRefreshMessages();
    } catch (err) {
      onNotify(err instanceof Error ? err.message : "ตอบรับนัดหมายไม่สำเร็จ");
    }
  };

  const tryUnlockConfidential = (msg: ChatMessage) => {
    if (!msg.confidential_pin) {
      setUnlockedIds((prev) => ({ ...prev, [msg.id]: true }));
      return;
    }
    if (pinAttempt.trim() === msg.confidential_pin) {
      setUnlockedIds((prev) => ({ ...prev, [msg.id]: true }));
      setPinPromptMsgId(null);
      setPinAttempt("");
    } else {
      onNotify("รหัส PIN ไม่ถูกต้อง");
    }
  };

  const toggleSideTab = (tab: SidePanelTab) => {
    onCloseMiniApp?.();
    setShowCardModal(false);
    setAiModalMode(null);
    setSideTab((prev) => (prev === tab ? null : tab));
  };

  const isDarkRoom = toneOption.isDark;

  const toolButtons: Array<{
    id: SidePanelTab;
    label: string;
    testId: string;
    icon: React.ReactNode;
  }> = [
    { id: "albums", label: "อัลบั้ม", testId: "room-btn-albums", icon: <ImageIcon className="h-3.5 w-3.5" /> },
    { id: "notes", label: "โน้ต", testId: "room-btn-notes", icon: <StickyNote className="h-3.5 w-3.5" /> },
    { id: "polls", label: "โพล", testId: "room-btn-polls", icon: <BarChart3 className="h-3.5 w-3.5" /> },
    { id: "events", label: "นัดหมาย", testId: "room-btn-events", icon: <Calendar className="h-3.5 w-3.5" /> },
    { id: "vault", label: "คลังไฟล์", testId: "room-btn-vault", icon: <FolderOpen className="h-3.5 w-3.5" /> },
    { id: "members", label: "สมาชิก", testId: "room-btn-members", icon: <Users className="h-3.5 w-3.5" /> },
  ];

  return (
    <div className="flex h-full min-h-0 flex-col bg-[var(--bc-card)]">
      {/* Compact Top Room Header */}
      <header className="shrink-0 border-b border-[var(--bc-border)] bg-[var(--bc-card)]">
        {/* Row 1: Back + Avatar + Title + Quick Icons */}
        <div className="flex items-center justify-between gap-2 px-3 py-2">
          <div className="flex min-w-0 items-center gap-2">
            {onBackMobile && (
              <button
                type="button"
                data-testid="mobile-back-btn"
                aria-label="กลับหน้ารายการแชท"
                onClick={onBackMobile}
                className="inline-flex h-8 w-8 shrink-0 items-center justify-center rounded-xl border border-[var(--bc-border)] bg-[var(--bc-panel)] text-sm font-bold text-[var(--bc-text)] md:hidden"
              >
                ←
              </button>
            )}
            <UserAvatar
              name={conversation.name}
              avatarUrl={conversation.avatar_url}
              size={34}
              isAi={conversation.members.some((m) => m.id === "user_ai") && conversation.type === "direct"}
              isOfficial={conversation.type === "official"}
            />
            <div className="min-w-0">
              <div className="flex items-center gap-1">
                <h2
                  data-testid="active-room-title"
                  className="truncate text-sm font-bold leading-tight text-[var(--bc-text)] sm:text-base"
                >
                  {conversation.name}
                </h2>
                {conversation.is_muted && (
                  <span title="ปิดเสียงห้องนี้">
                    <BellOff className="h-3.5 w-3.5 shrink-0 text-[var(--bc-muted)]" />
                  </span>
                )}
                {conversation.is_archived && (
                  <span title="เก็บถาวร">
                    <Archive className="h-3.5 w-3.5 shrink-0 text-[var(--bc-muted)]" />
                  </span>
                )}
              </div>
              <p className="truncate text-[11px] text-[var(--bc-muted)]">
                {conversation.type === "group"
                  ? `กลุ่มแชท • สมาชิก ${conversation.member_count} คน`
                  : conversation.type === "official"
                    ? "ข่าวสาร BC Ai Chat"
                    : "แชทส่วนตัว 1-1"}
              </p>
            </div>
          </div>

          <div className="flex shrink-0 items-center gap-1">
            <button
              type="button"
              onClick={() => setShowRoomSearch((v) => !v)}
              title="ค้นหาในห้อง"
              aria-label="ค้นหาในห้อง"
              className={`inline-flex h-8 w-8 items-center justify-center rounded-xl border text-xs font-semibold ${
                showRoomSearch
                  ? "border-[var(--bc-primary)] bg-[var(--bc-soft)] text-[var(--bc-primary)]"
                  : "border-[var(--bc-border)] bg-[var(--bc-panel)] text-[var(--bc-text)] hover:bg-[var(--bc-soft)]"
              }`}
            >
              <Search className="h-3.5 w-3.5" />
            </button>

            <button
              type="button"
              onClick={() => setShowToneMenu((v) => !v)}
              title="สลับโทนพื้นหลังห้องแชท"
              aria-label="สลับโทนพื้นหลังห้องแชท"
              className={`inline-flex h-8 w-8 items-center justify-center rounded-xl border text-xs font-semibold ${
                showToneMenu
                  ? "border-[var(--bc-primary)] bg-[var(--bc-soft)] text-[var(--bc-primary)]"
                  : "border-[var(--bc-border)] bg-[var(--bc-panel)] text-[var(--bc-primary)] hover:bg-[var(--bc-soft)]"
              }`}
            >
              <Palette className="h-3.5 w-3.5" />
            </button>

            <button
              type="button"
              data-testid="btn-ai-summarize"
              onClick={() => void handleOpenAiSummary(false)}
              className="inline-flex h-8 items-center gap-1 rounded-xl bg-[var(--bc-primary)] px-2.5 text-xs font-bold text-white shadow-2xs hover:brightness-95"
            >
              <Sparkles className="h-3.5 w-3.5" />
              <span className="sm:hidden">สรุป</span>
              <span className="hidden sm:inline">AI สรุปแชท</span>
            </button>
          </div>
        </div>

        {/* Row 2: Compact Horizontally Scrollable Room Tool Pills */}
        <div className="flex items-center gap-1.5 overflow-x-auto whitespace-nowrap border-t border-[var(--bc-border)]/50 px-3 py-1.5">
          {toolButtons.map((tb) => {
            const active = sideTab === tb.id;
            return (
              <button
                key={tb.id}
                type="button"
                data-testid={tb.testId}
                onClick={() => toggleSideTab(tb.id)}
                className={`inline-flex h-7 shrink-0 items-center gap-1 rounded-full border px-2.5 text-[11px] font-semibold transition ${
                  active
                    ? "border-[var(--bc-primary)] bg-[var(--bc-primary)] text-white"
                    : "border-[var(--bc-border)] bg-[var(--bc-panel)] text-[var(--bc-text)] hover:bg-[var(--bc-soft)]"
                }`}
              >
                {tb.icon}
                <span>{tb.label}</span>
              </button>
            );
          })}
        </div>
      </header>

      {/* Inline Tone & Watermark Strip */}
      {showToneMenu && (
        <div className="flex shrink-0 flex-wrap items-center justify-between gap-2 border-b border-[var(--bc-border)] bg-[var(--bc-panel)] px-3 py-2 text-xs">
          <div className="flex items-center gap-1.5 overflow-x-auto whitespace-nowrap">
            {Object.values(ROOM_TONES).map((t) => (
              <button
                key={t.id}
                type="button"
                onClick={() => {
                  onChangeRoomTone(t.id);
                  setShowToneMenu(false);
                }}
                className={`inline-flex shrink-0 items-center gap-1.5 rounded-full border px-2.5 py-1 text-[11px] font-semibold ${
                  roomTone === t.id
                    ? "border-[var(--bc-primary)] bg-[var(--bc-soft)] text-[var(--bc-primary)]"
                    : "border-[var(--bc-border)] bg-[var(--bc-card)] text-[var(--bc-text)]"
                }`}
              >
                <span
                  style={{ backgroundColor: t.swatch }}
                  className="h-3 w-3 rounded-full border border-[var(--bc-border)]"
                />
                <span>{t.label}</span>
                {roomTone === t.id && <Check className="h-3 w-3" />}
              </button>
            ))}
          </div>
          <div className="flex shrink-0 items-center gap-1.5">
            <button
              type="button"
              onClick={() => setShowWatermark((v) => !v)}
              className={`inline-flex items-center gap-1 rounded-full border px-2.5 py-1 text-[11px] font-semibold ${
                showWatermark
                  ? "border-[var(--bc-primary)] bg-[var(--bc-soft)] text-[var(--bc-primary)]"
                  : "border-[var(--bc-border)] bg-[var(--bc-card)] text-[var(--bc-muted)]"
              }`}
            >
              <Shield className="h-3 w-3" />
              <span>ลายน้ำ: {showWatermark ? "เปิด" : "ปิด"}</span>
            </button>
            <button
              type="button"
              onClick={() => setShowToneMenu(false)}
              aria-label="ปิดแถบโทนสี"
              className="rounded-lg p-1 text-[var(--bc-muted)] hover:bg-[var(--bc-card)]"
            >
              <X className="h-3.5 w-3.5" />
            </button>
          </div>
        </div>
      )}

      {/* Optional Room Search Bar */}
      {showRoomSearch && (
        <div className="flex shrink-0 items-center gap-2 border-b border-[var(--bc-border)] bg-[var(--bc-panel)] px-3.5 py-2">
          <Search className="h-4 w-4 text-[var(--bc-muted)]" />
          <input
            type="text"
            value={roomSearchQuery}
            onChange={(e) => setRoomSearchQuery(e.target.value)}
            placeholder="ค้นหาข้อความหรือชื่อไฟล์ในห้องนี้..."
            className="min-w-0 flex-1 bg-transparent text-xs text-[var(--bc-text)] outline-none"
          />
          {roomSearchQuery && (
            <button
              type="button"
              onClick={() => setRoomSearchQuery("")}
              className="text-xs text-[var(--bc-muted)]"
            >
              ล้าง
            </button>
          )}
        </div>
      )}

      {/* Pinned Announcement Banner */}
      {conversation.pinned_message && !sideTab && !runningMiniApp && (
        <div className="flex shrink-0 items-center justify-between gap-2 border-b border-[var(--bc-border)] bg-[var(--bc-soft)]/70 px-3.5 py-1.5 text-xs">
          <div className="flex min-w-0 items-center gap-1.5">
            <Pin className="h-3.5 w-3.5 shrink-0 text-[var(--bc-primary)]" />
            <span className="shrink-0 font-bold text-[var(--bc-deep)]">
              ปักหมุด ({conversation.pinned_message.sender_name}):
            </span>
            <span className="truncate text-[var(--bc-text)]">
              {conversation.pinned_message.content}
            </span>
          </div>
          <button
            type="button"
            onClick={async () => {
              await api.pinMessage(conversation.id, null);
              await onConversationUpdated();
            }}
            className="shrink-0 text-[11px] font-semibold text-[var(--bc-primary)] hover:underline"
          >
            เลิกปักหมุด
          </button>
        </div>
      )}

      {/* Inline Workspace: Mini-App OR Room Tools Panel OR Message Stream */}
      {runningMiniApp ? (
        <div
          data-testid="inline-miniapp-runner"
          className="flex min-h-0 flex-1 flex-col bg-[var(--bc-surface)]"
        >
          <div className="flex shrink-0 items-center justify-between gap-2 border-b border-[var(--bc-border)] bg-[var(--bc-card)] px-3 py-2">
            <button
              type="button"
              onClick={onCloseMiniApp}
              className="inline-flex items-center gap-1 rounded-xl border border-[var(--bc-border)] bg-[var(--bc-panel)] px-2.5 py-1 text-xs font-bold text-[var(--bc-primary)]"
            >
              <ArrowLeft className="h-3.5 w-3.5" />
              <span>กลับไปแชท</span>
            </button>
            <span className="truncate text-sm font-bold text-[var(--bc-text)]">
              {runningMiniApp.title}
            </span>
          </div>
          <iframe
            title={runningMiniApp.title}
            src={resolveMiniAppIframeUrl(runningMiniApp, conversation.id)}
            className="w-full flex-1 border-0"
          />
        </div>
      ) : sideTab ? (
        <RoomSideModal
          openTab={sideTab}
          onClose={() => setSideTab(null)}
          onSwitchTab={setSideTab}
          conversation={conversation}
          messages={messages}
          currentUser={currentUser}
          friends={friends}
          onConversationUpdated={onConversationUpdated}
          onRefreshMessages={onRefreshMessages}
          onVotePoll={handleVotePoll}
          onClosePoll={handleClosePoll}
          onRsvpEvent={handleRsvpEvent}
          onNotify={onNotify}
        />
      ) : (
        <>
          {/* Message Stream */}
          <div
            style={{ backgroundColor: toneOption.bg }}
            className={`relative min-h-0 flex-1 overflow-y-auto px-3 py-3 sm:px-5 sm:py-4 ${
              isDarkRoom ? "bc-room-spiral-dark" : "bc-room-spiral-light"
            }`}
          >
            {/* Subtle Personal Watermark Overlay */}
            {showWatermark && (
              <div
                aria-hidden="true"
                className="pointer-events-none sticky top-3 z-0 flex h-0 justify-end overflow-visible opacity-20 select-none"
              >
                <div
                  className={`rotate-[-12deg] rounded-lg border px-2 py-0.5 text-[10px] font-semibold ${
                    isDarkRoom
                      ? "border-amber-200/30 text-amber-200"
                      : "border-[var(--bc-primary)]/30 text-[var(--bc-primary)]"
                  }`}
                >
                  BC PERSONAL • {currentUser.display_name} ({currentUser.bc_id})
                </div>
              </div>
            )}

            <div className="relative z-10 space-y-3">
              {filteredMessages.length === 0 ? (
                <div
                  className={`mx-auto max-w-md rounded-2xl border p-6 text-center text-xs ${
                    isDarkRoom
                      ? "border-stone-700 bg-stone-900/70 text-stone-300"
                      : "border-[var(--bc-border)] bg-white/90 text-[var(--bc-muted)]"
                  }`}
                >
                  ยังไม่มีข้อความในห้องนี้ เริ่มพิมพ์ทักทายหรือเรียก{" "}
                  <strong className="text-[var(--bc-primary)]">@ai</strong> ได้เลยครับ
                </div>
              ) : (
                filteredMessages.map((msg) => {
                  if (msg.type === "system") {
                    return (
                      <div key={msg.id} className="flex justify-center py-1">
                        <span
                          className={`rounded-full px-3 py-1 text-[11px] font-medium ${
                            isDarkRoom
                              ? "bg-stone-800/90 text-stone-200"
                              : "bg-[var(--bc-sand)]/90 text-[var(--bc-text)]"
                          }`}
                        >
                          {msg.content}
                        </span>
                      </div>
                    );
                  }

                  const isMe = msg.sender_id === currentUser.id;
                  const isAi = msg.sender_id === "user_ai";
                  const isLocked =
                    msg.is_confidential &&
                    !unlockedIds[msg.id] &&
                    !msg.is_unsent &&
                    Boolean(msg.confidential_pin);
                  const reactionEntries = Object.entries(msg.reactions || {}).filter(
                    ([, uids]) => uids && uids.length > 0
                  );
                  const canDeleteAny = isMe || currentUser.role === "admin";

                  return (
                    <div
                      key={msg.id}
                      data-testid={`message-item-${msg.id}`}
                      className={`flex items-end gap-2 ${isMe ? "justify-end" : "justify-start"}`}
                    >
                      {!isMe && (
                        <UserAvatar
                          name={msg.sender_name}
                          avatarUrl={msg.sender_avatar}
                          size={32}
                          isAi={isAi}
                        />
                      )}

                      <div className={`flex max-w-[84%] flex-col ${isMe ? "items-end" : "items-start"} sm:max-w-[70%]`}>
                        {!isMe && (
                          <div className="mb-0.5 flex items-center gap-1.5 px-1">
                            <span
                              className={`text-[11px] font-bold ${
                                isAi
                                  ? "text-indigo-500"
                                  : isDarkRoom
                                    ? "text-amber-200"
                                    : "text-[var(--bc-primary)]"
                              }`}
                            >
                              {msg.sender_name}
                            </span>
                            {isAi && (
                              <span className="rounded bg-indigo-600 px-1.5 py-0.2 text-[9px] font-bold text-white">
                                BC AI
                              </span>
                            )}
                          </div>
                        )}

                        {/* Bubble */}
                        <div
                          style={
                            msg.is_unsent
                              ? undefined
                              : isMe
                                ? {
                                    backgroundColor: "var(--bc-bubble-sent)",
                                    color: "var(--bc-bubble-sent-text)",
                                  }
                                : isAi
                                  ? {
                                      backgroundColor: "#EEF2FF",
                                      color: "#1E1B4B",
                                    }
                                  : {
                                      backgroundColor: "var(--bc-bubble-recv)",
                                      color: "#1B1C1C",
                                    }
                          }
                          className={`group relative rounded-2xl px-3.5 py-2.5 shadow-2xs ${
                            msg.is_unsent
                              ? "border border-dashed border-[var(--bc-border)] bg-white/70 text-xs italic text-[var(--bc-muted)]"
                              : isMe
                                ? "rounded-br-sm border border-[var(--bc-border)]"
                                : "rounded-bl-sm border border-[var(--bc-border)]"
                          }`}
                        >
                          {/* Confidential / Urgent Badges */}
                          {!msg.is_unsent && (msg.is_confidential || msg.priority === "urgent") && (
                            <div className="mb-1.5 flex flex-wrap items-center gap-1.5">
                              {msg.is_confidential && (
                                <span className="inline-flex items-center gap-1 rounded-full bg-[var(--bc-deep)] px-2 py-0.5 text-[10px] font-bold text-white">
                                  <Lock className="h-2.5 w-2.5" />
                                  <span>ข้อความลับ{msg.confidential_pin ? " (PIN)" : ""}</span>
                                </span>
                              )}
                              {msg.priority === "urgent" && (
                                <span className="inline-flex items-center gap-1 rounded-full bg-amber-600 px-2 py-0.5 text-[10px] font-bold text-white">
                                  <AlertTriangle className="h-2.5 w-2.5" />
                                  <span>เรื่องด่วน</span>
                                </span>
                              )}
                            </div>
                          )}

                          {/* Reply Quote */}
                          {!msg.is_unsent && msg.reply_to && (
                            <div className="mb-2 rounded-xl border-l-4 border-[var(--bc-primary)] bg-black/5 px-2.5 py-1.5 text-[11px]">
                              <div className="font-bold text-[var(--bc-primary)]">
                                ตอบกลับ {msg.reply_to.sender_name}
                              </div>
                              <div className="line-clamp-2 opacity-80">{msg.reply_to.content}</div>
                            </div>
                          )}

                          {/* Content Body */}
                          {msg.is_unsent ? (
                            <span>{msg.content}</span>
                          ) : isLocked ? (
                            <div className="space-y-2 py-1">
                              <div className="flex items-center gap-1.5 text-xs font-bold text-[var(--bc-deep)]">
                                <Lock className="h-4 w-4" />
                                <span>ข้อความลับส่วนตัวล็อกด้วย PIN</span>
                              </div>
                              {pinPromptMsgId === msg.id ? (
                                <div className="flex items-center gap-1.5">
                                  <input
                                    type="password"
                                    maxLength={8}
                                    value={pinAttempt}
                                    onChange={(e) => setPinAttempt(e.target.value)}
                                    placeholder="กรอก PIN"
                                    className="w-24 rounded-lg border border-[var(--bc-border)] bg-white px-2 py-1 text-xs outline-none"
                                  />
                                  <button
                                    type="button"
                                    onClick={() => tryUnlockConfidential(msg)}
                                    className="rounded-lg bg-[var(--bc-primary)] px-2.5 py-1 text-xs font-bold text-white"
                                  >
                                    เปิดดู
                                  </button>
                                </div>
                              ) : (
                                <button
                                  type="button"
                                  onClick={() => {
                                    setPinPromptMsgId(msg.id);
                                    setPinAttempt("");
                                  }}
                                  className="inline-flex items-center gap-1 rounded-lg bg-[var(--bc-primary)] px-2.5 py-1 text-xs font-bold text-white"
                                >
                                  <Unlock className="h-3 w-3" />
                                  <span>ใส่รหัส PIN เพื่อเปิดอ่าน</span>
                                </button>
                              )}
                            </div>
                          ) : (
                            <>
                              {msg.type === "sticker" && (
                                <StickerArt
                                  code={msg.sticker_code}
                                  fallbackLabel={msg.content}
                                />
                              )}

                              {msg.type === "image" && msg.attachment && (
                                <div className="space-y-1.5">
                                  <a
                                    href={resolveMediaUrl(msg.attachment.url)}
                                    target="_blank"
                                    rel="noreferrer"
                                    className="block overflow-hidden rounded-xl border border-[var(--bc-border)]"
                                  >
                                    <img
                                      src={resolveMediaUrl(msg.attachment.url)}
                                      alt={msg.attachment.file_name}
                                      className="max-h-64 w-auto object-contain"
                                    />
                                  </a>
                                  <div className="text-[11px] opacity-80">{msg.attachment.file_name}</div>
                                </div>
                              )}

                              {msg.type === "file" && msg.attachment && (
                                <a
                                  href={resolveMediaUrl(msg.attachment.url)}
                                  target="_blank"
                                  rel="noreferrer"
                                  className="flex items-center gap-2.5 rounded-xl border border-[var(--bc-border)] bg-white/80 px-3 py-2 text-xs hover:bg-white"
                                >
                                  <FileText className="h-5 w-5 shrink-0 text-[var(--bc-primary)]" />
                                  <div className="min-w-0">
                                    <div className="truncate font-bold text-[var(--bc-text)]">
                                      {msg.attachment.file_name}
                                    </div>
                                    <div className="text-[10px] text-[var(--bc-muted)]">
                                      {formatFileSize(msg.attachment.file_size)} • คลังถาวร MinIO
                                    </div>
                                  </div>
                                </a>
                              )}

                              {msg.type === "audio" && msg.attachment && (
                                <div className="space-y-1">
                                  <div className="flex items-center gap-1.5 text-xs font-bold">
                                    <Mic className="h-3.5 w-3.5 text-[var(--bc-primary)]" />
                                    <span>
                                      ข้อความเสียง{" "}
                                      {msg.audio_duration_sec ? `(${msg.audio_duration_sec} วินาที)` : ""}
                                    </span>
                                  </div>
                                  <audio
                                    controls
                                    preload="metadata"
                                    src={resolveMediaUrl(msg.attachment.url)}
                                    className="h-8 max-w-[240px]"
                                  />
                                </div>
                              )}

                              {msg.type === "rich_card" && msg.card_payload && (
                                <div className="w-full min-w-[220px] max-w-[300px] overflow-hidden rounded-xl border border-[var(--bc-border)] bg-white text-[var(--bc-text)] shadow-xs">
                                  <div
                                    style={{
                                      backgroundColor: String(msg.card_payload.color_hex || "#812920"),
                                    }}
                                    className="px-3 py-2 text-xs font-bold text-white"
                                  >
                                    {String(msg.card_payload.title || "การ์ดโต้ตอบ BC Ai Chat")}
                                  </div>
                                  <div className="space-y-1.5 p-3 text-xs">
                                    {msg.card_payload.heading && (
                                      <div className="font-bold text-[var(--bc-text)]">
                                        {String(msg.card_payload.heading)}
                                      </div>
                                    )}
                                    {msg.card_payload.subtitle && (
                                      <div className="text-[var(--bc-muted)]">
                                        {String(msg.card_payload.subtitle)}
                                      </div>
                                    )}
                                    {msg.card_payload.highlight_value && (
                                      <div className="text-sm font-extrabold text-[var(--bc-primary)]">
                                        {String(msg.card_payload.highlight_value)}
                                      </div>
                                    )}
                                    <div className="flex items-center justify-between pt-1">
                                      <span className="rounded-full bg-[var(--bc-soft)] px-2 py-0.5 text-[10px] font-bold text-[var(--bc-deep)]">
                                        {String(
                                          msg.card_payload.status_label ||
                                            msg.card_payload.status ||
                                            "รอเพื่อนตอบ"
                                        )}
                                      </span>
                                      {msg.card_payload.approved_by && (
                                        <span className="text-[10px] text-[var(--bc-muted)]">
                                          โดย {String(msg.card_payload.approved_by)}
                                        </span>
                                      )}
                                    </div>
                                    <div className="flex gap-1.5 pt-1">
                                      <button
                                        type="button"
                                        onClick={() => api.approveCard(msg.id, "ตกลง / ไปด้วย").then(onRefreshMessages)}
                                        className="flex-1 rounded-lg bg-[var(--bc-primary)] px-2 py-1 text-[11px] font-bold text-white"
                                      >
                                        ตกลง / ไปด้วย
                                      </button>
                                      <button
                                        type="button"
                                        onClick={() => api.approveCard(msg.id, "ขอผ่าน").then(onRefreshMessages)}
                                        className="flex-1 rounded-lg border border-[var(--bc-border)] bg-[var(--bc-panel)] px-2 py-1 text-[11px] font-bold text-[var(--bc-text)]"
                                      >
                                        ขอผ่าน
                                      </button>
                                    </div>
                                  </div>
                                </div>
                              )}

                              {msg.type === "poll" && msg.poll && (
                                <div className="w-full min-w-[230px] max-w-[310px] space-y-2 rounded-xl border border-[var(--bc-border)] bg-white p-3 text-[var(--bc-text)]">
                                  <div className="flex items-center justify-between gap-2">
                                    <span className="inline-flex items-center gap-1 text-xs font-bold text-[var(--bc-primary)]">
                                      <BarChart3 className="h-3.5 w-3.5" />
                                      <span>โพลโหวต</span>
                                    </span>
                                    <span className="text-[10px] font-semibold text-[var(--bc-muted)]">
                                      {msg.poll.is_closed ? "ปิดโหวตแล้ว" : "กำลังโหวต"}
                                    </span>
                                  </div>
                                  <div className="text-sm font-bold">{msg.poll.question}</div>
                                  <div className="space-y-1.5">
                                    {(() => {
                                      const total = msg.poll!.options.reduce(
                                        (s, o) => s + o.voter_ids.length,
                                        0
                                      );
                                      return msg.poll!.options.map((opt) => {
                                        const pct =
                                          total > 0
                                            ? Math.round((opt.voter_ids.length / total) * 100)
                                            : 0;
                                        const picked = opt.voter_ids.includes(currentUser.id);
                                        return (
                                          <button
                                            key={opt.id}
                                            type="button"
                                            data-testid={`poll-opt-${msg.id}-${opt.id}`}
                                            disabled={msg.poll!.is_closed}
                                            onClick={() => handleVotePoll(msg.id, [opt.id])}
                                            className={`relative w-full overflow-hidden rounded-lg border px-2.5 py-1.5 text-left text-xs ${
                                              picked
                                                ? "border-[var(--bc-primary)] bg-[var(--bc-soft)]/50 font-bold"
                                                : "border-[var(--bc-border)] bg-[var(--bc-surface)] hover:bg-[var(--bc-panel)]"
                                            }`}
                                          >
                                            <div
                                              style={{ width: `${pct}%` }}
                                              className="absolute inset-y-0 left-0 bg-[var(--bc-primary)]/15"
                                            />
                                            <div className="relative flex justify-between gap-2">
                                              <span>{opt.text}</span>
                                              <span>
                                                {opt.voter_ids.length} ({pct}%)
                                              </span>
                                            </div>
                                          </button>
                                        );
                                      });
                                    })()}
                                  </div>
                                </div>
                              )}

                              {msg.type === "event" && msg.event_data && (
                                <div className="w-full min-w-[230px] max-w-[310px] space-y-2 rounded-xl border border-[var(--bc-border)] bg-white p-3 text-[var(--bc-text)]">
                                  <div className="flex items-center gap-1.5 text-xs font-bold text-[var(--bc-primary)]">
                                    <Calendar className="h-3.5 w-3.5" />
                                    <span>นัดหมาย &amp; RSVP</span>
                                  </div>
                                  <div className="text-sm font-bold">{msg.event_data.title}</div>
                                  {msg.event_data.description && (
                                    <div className="text-xs text-[var(--bc-muted)]">
                                      {msg.event_data.description}
                                    </div>
                                  )}
                                  <div className="text-[11px] text-[var(--bc-primary)]">
                                    🕒 {formatThaiTime(msg.event_data.starts_at)} • 📍{" "}
                                    {msg.event_data.location || "ออนไลน์"}
                                  </div>
                                  <div className="flex flex-wrap gap-1.5 pt-1">
                                    <button
                                      type="button"
                                      data-testid={`rsvp-going-${msg.id}`}
                                      onClick={() => handleRsvpEvent(msg.id, "going")}
                                      className={`rounded-lg border px-2 py-1 text-[11px] font-bold ${
                                        msg.event_data.going_ids.includes(currentUser.id)
                                          ? "border-[var(--bc-primary)] bg-[var(--bc-primary)] text-white"
                                          : "border-[var(--bc-border)] bg-[var(--bc-panel)]"
                                      }`}
                                    >
                                      เข้าร่วม ({msg.event_data.going_ids.length})
                                    </button>
                                    <button
                                      type="button"
                                      onClick={() => handleRsvpEvent(msg.id, "maybe")}
                                      className={`rounded-lg border px-2 py-1 text-[11px] font-bold ${
                                        msg.event_data.maybe_ids.includes(currentUser.id)
                                          ? "border-amber-600 bg-amber-600 text-white"
                                          : "border-[var(--bc-border)] bg-[var(--bc-panel)]"
                                      }`}
                                    >
                                      อาจจะ ({msg.event_data.maybe_ids.length})
                                    </button>
                                    <button
                                      type="button"
                                      onClick={() => handleRsvpEvent(msg.id, "not_going")}
                                      className={`rounded-lg border px-2 py-1 text-[11px] font-bold ${
                                        msg.event_data.not_going_ids.includes(currentUser.id)
                                          ? "border-red-600 bg-red-600 text-white"
                                          : "border-[var(--bc-border)] bg-[var(--bc-panel)]"
                                      }`}
                                    >
                                      ไม่สะดวก ({msg.event_data.not_going_ids.length})
                                    </button>
                                  </div>
                                </div>
                              )}

                              {msg.type === "text" && (
                                <p className="whitespace-pre-wrap break-words text-sm leading-relaxed">
                                  {msg.content}
                                </p>
                              )}

                              {/* Urgent Topic Action Controls */}
                              {msg.priority === "urgent" && (
                                <div className="mt-2 flex flex-wrap items-center gap-1.5 border-t border-black/10 pt-1.5 text-[11px]">
                                  <span className="font-semibold">
                                    สถานะ: {msg.task_status || "open"}
                                    {msg.accepted_by ? ` (${msg.accepted_by})` : ""}
                                  </span>
                                  <button
                                    type="button"
                                    onClick={() => api.taskAction(msg.id, "accept").then(onRefreshMessages)}
                                    className="rounded bg-[var(--bc-primary)] px-2 py-0.5 font-bold text-white"
                                  >
                                    รับทราบ
                                  </button>
                                  <button
                                    type="button"
                                    onClick={() => api.taskAction(msg.id, "done").then(onRefreshMessages)}
                                    className="rounded bg-emerald-700 px-2 py-0.5 font-bold text-white"
                                  >
                                    เรียบร้อย
                                  </button>
                                </div>
                              )}
                            </>
                          )}
                        </div>

                        {/* Reactions Display */}
                        {reactionEntries.length > 0 && !msg.is_unsent && (
                          <div className="mt-1 flex flex-wrap items-center gap-1">
                            {reactionEntries.map(([emoji, uids]) => {
                              const mine = uids.includes(currentUser.id);
                              return (
                                <button
                                  key={emoji}
                                  type="button"
                                  onClick={() => handleReact(msg.id, emoji)}
                                  className={`inline-flex items-center gap-1 rounded-full border px-2 py-0.5 text-[11px] font-semibold shadow-2xs ${
                                    mine
                                      ? "border-[var(--bc-primary)] bg-[var(--bc-soft)] text-[var(--bc-deep)]"
                                      : "border-[var(--bc-border)] bg-white text-[var(--bc-text)]"
                                  }`}
                                >
                                  <span>{emoji}</span>
                                  <span>{uids.length}</span>
                                </button>
                              );
                            })}
                          </div>
                        )}

                        {/* Message Meta + Quick Actions Bar */}
                        <div
                          className={`mt-1 flex flex-wrap items-center gap-1.5 px-1 text-[10px] ${
                            isDarkRoom ? "text-stone-300" : "text-[var(--bc-muted)]"
                          }`}
                        >
                          <span>{formatThaiTime(msg.created_at)}</span>
                          {msg.read_count > 0 && (
                            <span className="inline-flex items-center gap-0.5 font-semibold text-[var(--bc-primary)]">
                              <CheckCheck className="h-3 w-3" />
                              <span>อ่านแล้ว {msg.read_count}</span>
                            </span>
                          )}

                          {!msg.is_unsent && (
                            <div className="inline-flex flex-wrap items-center gap-1">
                              {REACTION_EMOJIS.slice(0, 3).map((em) => (
                                <button
                                  key={em}
                                  type="button"
                                  data-testid={`react-${em}-${msg.id}`}
                                  onClick={() => handleReact(msg.id, em)}
                                  className="rounded px-1 py-0.5 hover:bg-black/10"
                                  title={`แสดงความรู้สึก ${em}`}
                                >
                                  {em}
                                </button>
                              ))}
                              <button
                                type="button"
                                onClick={() => setReplyTarget(msg)}
                                className="inline-flex items-center gap-0.5 rounded px-1.5 py-0.5 hover:bg-black/10"
                                title="ตอบกลับ"
                              >
                                <Reply className="h-3 w-3" />
                                <span>ตอบ</span>
                              </button>
                              <button
                                type="button"
                                onClick={() =>
                                  api.pinMessage(conversation.id, msg.id).then(onConversationUpdated)
                                }
                                className="inline-flex items-center gap-0.5 rounded px-1.5 py-0.5 hover:bg-black/10"
                                title="ปักหมุดหัวห้อง"
                              >
                                <Pin className="h-3 w-3" />
                              </button>
                              <button
                                type="button"
                                onClick={() =>
                                  api.deleteMessageForMe(msg.id).then(onRefreshMessages)
                                }
                                className="rounded px-1.5 py-0.5 hover:bg-black/10"
                                title="ลบเฉพาะฉัน"
                              >
                                ลบเฉพาะฉัน
                              </button>
                              {canDeleteAny && (
                                <button
                                  type="button"
                                  onClick={() =>
                                    api.unsendMessage(msg.id, false).then(onRefreshMessages)
                                  }
                                  className="rounded px-1.5 py-0.5 text-red-600 hover:bg-red-50"
                                  title="ยกเลิกข้อความทุกคน"
                                >
                                  ยกเลิกทุกคน
                                </button>
                              )}
                            </div>
                          )}
                        </div>
                      </div>
                    </div>
                  );
                })
              )}
              <div ref={scrollEndRef} />
            </div>
          </div>

          {/* Inline Sticker Picker */}
          {showStickerPicker && (
            <div className="shrink-0 border-t border-[var(--bc-border)] bg-[var(--bc-panel)] p-3">
              <div className="mb-2 flex items-center justify-between">
                <span className="text-xs font-bold text-[var(--bc-primary)]">
                  ชุดสติกเกอร์ &quot;อารมณ์ดีดินเผาไทย&quot;
                </span>
                <button
                  type="button"
                  onClick={() => setShowStickerPicker(false)}
                  className="text-xs text-[var(--bc-muted)]"
                >
                  ปิด
                </button>
              </div>
              <div className="grid grid-cols-4 gap-2 sm:grid-cols-8">
                {ORIGINAL_THAI_STICKERS.map((st) => (
                  <button
                    key={st.code}
                    type="button"
                    onClick={() => handleSendSticker(st.code, st.label)}
                    className="flex flex-col items-center rounded-xl border border-[var(--bc-border)] bg-white p-1 transition hover:border-[var(--bc-primary)]"
                  >
                    <StickerArt code={st.code} fallbackLabel={st.label} size={66} />
                  </button>
                ))}
              </div>
            </div>
          )}

          {/* Inline Rich Card Composer Tray (Zero Modal) */}
          {showCardModal && (
            <form
              data-testid="rich-card-inline-tray"
              onSubmit={handleSendRichCard}
              className="shrink-0 space-y-2 border-t border-[var(--bc-border)] bg-[var(--bc-panel)] p-3"
            >
              <div className="flex items-center justify-between">
                <span className="text-xs font-bold text-[var(--bc-primary)]">
                  ส่งการ์ดโต้ตอบ (Rich Card)
                </span>
                <button
                  type="button"
                  onClick={() => setShowCardModal(false)}
                  aria-label="ปิดการ์ดโต้ตอบ"
                  className="rounded-lg p-1 text-[var(--bc-muted)] hover:bg-[var(--bc-card)]"
                >
                  <X className="h-4 w-4" />
                </button>
              </div>
              <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
                <input
                  type="text"
                  required
                  value={cardTitle}
                  onChange={(e) => setCardTitle(e.target.value)}
                  placeholder="หัวข้อการ์ด"
                  className="w-full rounded-xl border border-[var(--bc-border)] bg-[var(--bc-card)] px-3 py-1.5 text-xs outline-none focus:border-[var(--bc-primary)]"
                />
                <input
                  type="text"
                  value={cardHeading}
                  onChange={(e) => setCardHeading(e.target.value)}
                  placeholder="รายละเอียดหลัก"
                  className="w-full rounded-xl border border-[var(--bc-border)] bg-[var(--bc-card)] px-3 py-1.5 text-xs outline-none focus:border-[var(--bc-primary)]"
                />
                <input
                  type="text"
                  value={cardSubtitle}
                  onChange={(e) => setCardSubtitle(e.target.value)}
                  placeholder="หมายเหตุ / เวลา"
                  className="w-full rounded-xl border border-[var(--bc-border)] bg-[var(--bc-card)] px-3 py-1.5 text-xs outline-none focus:border-[var(--bc-primary)]"
                />
                <input
                  type="text"
                  value={cardAmount}
                  onChange={(e) => setCardAmount(e.target.value)}
                  placeholder="ค่าใช้จ่าย / ข้อความเด่น"
                  className="w-full rounded-xl border border-[var(--bc-border)] bg-[var(--bc-card)] px-3 py-1.5 text-xs outline-none focus:border-[var(--bc-primary)]"
                />
              </div>
              <div className="flex justify-end gap-2">
                <button
                  type="button"
                  onClick={() => setShowCardModal(false)}
                  className="rounded-xl border border-[var(--bc-border)] bg-[var(--bc-card)] px-3 py-1.5 text-xs font-semibold"
                >
                  ปิด
                </button>
                <button
                  type="submit"
                  className="rounded-xl bg-[var(--bc-primary)] px-3.5 py-1.5 text-xs font-bold text-white"
                >
                  ส่งการ์ดเข้าห้องแชท
                </button>
              </div>
            </form>
          )}

          {/* Inline AI Tray (Summary & Personal Assist — Zero Modal) */}
          {aiModalMode && (
            <div
              data-testid="ai-inline-tray"
              className="max-h-[44dvh] shrink-0 space-y-2.5 overflow-y-auto border-t border-[var(--bc-border)] bg-[var(--bc-panel)] p-3"
            >
              <div className="flex items-center justify-between gap-2">
                <div className="flex items-center gap-1.5 text-xs font-bold text-[var(--bc-primary)]">
                  <Sparkles className="h-4 w-4 shrink-0" />
                  <span>
                    {aiModalMode === "summary"
                      ? "✨ AI สรุปการคุยในห้อง"
                      : "🪄 ผู้ช่วย AI ส่วนตัว — คิดคำตอบ & เกลาข้อความ"}
                  </span>
                </div>
                <button
                  type="button"
                  onClick={() => setAiModalMode(null)}
                  aria-label="ปิดแถบผู้ช่วย AI"
                  className="rounded-lg p-1 text-[var(--bc-muted)] hover:bg-[var(--bc-card)]"
                >
                  <X className="h-4 w-4" />
                </button>
              </div>

              {aiModalMode === "assist" && (
                <div className="flex items-center gap-1.5 overflow-x-auto whitespace-nowrap pb-0.5">
                  {(
                    [
                      ["suggest_reply", "คิดคำตอบ 3 แบบ"],
                      ["polish", "เกลาให้น่ารัก/สุภาพ"],
                      ["formal", "ชวนคุยเป็นกันเอง"],
                      ["translate_en", "แปลอังกฤษ"],
                      ["action_plan", "สรุปนัดหมาย"],
                    ] as const
                  ).map(([m, label]) => (
                    <button
                      key={m}
                      type="button"
                      onClick={() => void handleOpenAiAssist(m)}
                      className={`shrink-0 rounded-full px-2.5 py-1 text-[11px] font-semibold ${
                        assistMode === m
                          ? "bg-[var(--bc-primary)] text-white"
                          : "border border-[var(--bc-border)] bg-[var(--bc-card)] text-[var(--bc-text)]"
                      }`}
                    >
                      {label}
                    </button>
                  ))}
                </div>
              )}

              {aiLoading ? (
                <div className="py-4 text-center text-xs text-[var(--bc-muted)]">
                  กำลังประมวลผลด้วยสมองกล BC AI...
                </div>
              ) : aiModalMode === "summary" && aiSummary ? (
                <div className="space-y-2 rounded-2xl border border-[var(--bc-border)] bg-[var(--bc-card)] p-3 text-xs">
                  <p className="whitespace-pre-wrap leading-relaxed text-[var(--bc-text)]">
                    {aiSummary.summary}
                  </p>
                  {aiSummary.action_items.length > 0 && (
                    <div>
                      <div className="font-bold text-[var(--bc-primary)]">สิ่งที่นัดกันต่อ:</div>
                      <ul className="list-disc pl-4">
                        {aiSummary.action_items.map((a, i) => (
                          <li key={i}>{a}</li>
                        ))}
                      </ul>
                    </div>
                  )}
                  <div className="flex justify-end gap-2 pt-1">
                    <button
                      type="button"
                      onClick={() => void handleOpenAiSummary(true)}
                      className="rounded-xl bg-[var(--bc-primary)] px-3 py-1.5 text-xs font-bold text-white"
                    >
                      โพสต์สรุปเข้าห้องแชท
                    </button>
                  </div>
                </div>
              ) : aiModalMode === "assist" && aiAssist ? (
                <div className="space-y-2 rounded-2xl border border-[var(--bc-border)] bg-[var(--bc-card)] p-3 text-xs">
                  <div className="whitespace-pre-wrap leading-relaxed text-[var(--bc-text)]">
                    {aiAssist.result}
                  </div>
                  <div className="flex flex-wrap gap-1.5 pt-1">
                    <button
                      type="button"
                      onClick={() => {
                        setDraft(aiAssist.result);
                        setAiModalMode(null);
                      }}
                      className="rounded-xl bg-[var(--bc-primary)] px-3 py-1.5 text-xs font-bold text-white"
                    >
                      นำไปใช้ในช่องแชท
                    </button>
                    {aiAssist.suggestions.map((sg, idx) => (
                      <button
                        key={idx}
                        type="button"
                        onClick={() => {
                          setDraft(sg);
                          setAiModalMode(null);
                        }}
                        className="rounded-xl border border-[var(--bc-border)] bg-[var(--bc-panel)] px-2.5 py-1.5 text-left text-xs hover:bg-[var(--bc-soft)]"
                      >
                        ตัวเลือก {idx + 1}: {sg.slice(0, 50)}
                        {sg.length > 50 ? "..." : ""}
                      </button>
                    ))}
                  </div>
                </div>
              ) : null}
            </div>
          )}

          {/* Composer Area */}
          <div className="relative shrink-0 border-t border-[var(--bc-border)] bg-[var(--bc-card)] px-3 py-2 sm:px-3.5 sm:py-2.5">
            {/* @Mention Autocomplete */}
            {mentionQuery !== null && mentionCandidates.length > 0 && (
              <div className="absolute bottom-full left-3 z-30 mb-1 w-72 max-w-[calc(100vw-1.5rem)] rounded-2xl border border-[var(--bc-border)] bg-[var(--bc-card)] p-1.5 shadow-xl">
                <div className="px-2 py-1 text-[10px] font-bold text-[var(--bc-muted)]">
                  แท็กเพื่อนหรือ AI (@mention)
                </div>
                {mentionCandidates.map((c) => (
                  <button
                    key={c.id}
                    type="button"
                    onClick={() => insertMention(c)}
                    className="flex w-full items-center justify-between gap-2 rounded-xl px-2.5 py-1.5 text-left text-xs hover:bg-[var(--bc-soft)]"
                  >
                    <span className="font-bold text-[var(--bc-primary)]">{c.label}</span>
                    <span className="truncate text-[11px] text-[var(--bc-muted)]">{c.name}</span>
                  </button>
                ))}
              </div>
            )}

            {/* Reply Bar */}
            {replyTarget && (
              <div className="mb-2 flex items-center justify-between gap-2 rounded-xl border border-[var(--bc-border)] bg-[var(--bc-panel)] px-3 py-1.5 text-xs">
                <div className="min-w-0">
                  <span className="font-bold text-[var(--bc-primary)]">
                    กำลังตอบกลับ {replyTarget.sender_name}:{" "}
                  </span>
                  <span className="truncate text-[var(--bc-muted)]">{replyTarget.content}</span>
                </div>
                <button type="button" onClick={() => setReplyTarget(null)}>
                  <X className="h-3.5 w-3.5 text-[var(--bc-muted)]" />
                </button>
              </div>
            )}

            {/* Compact Horizontally Scrollable Toolbar Row (Single line on 390px) */}
            <div className="mb-2 flex items-center gap-1.5 overflow-x-auto whitespace-nowrap pb-0.5 sm:flex-wrap">
              <label
                title="แนบไฟล์หรือรูปภาพ"
                className="inline-flex h-7 shrink-0 cursor-pointer items-center gap-1 rounded-lg border border-[var(--bc-border)] bg-[var(--bc-panel)] px-2 text-xs font-semibold text-[var(--bc-text)] hover:bg-[var(--bc-soft)]"
              >
                <Paperclip className="h-3.5 w-3.5 text-[var(--bc-primary)]" />
                <span>{uploading ? "อัปโหลด..." : "ไฟล์/รูป"}</span>
                <input
                  type="file"
                  className="hidden"
                  onChange={(e) => {
                    const f = e.target.files?.[0];
                    if (f) void handleFileUpload(f);
                    e.currentTarget.value = "";
                  }}
                />
              </label>

              <button
                type="button"
                onClick={() => setShowStickerPicker((v) => !v)}
                className="inline-flex h-7 shrink-0 items-center gap-1 rounded-lg border border-[var(--bc-border)] bg-[var(--bc-panel)] px-2 text-xs font-semibold text-[var(--bc-text)] hover:bg-[var(--bc-soft)]"
              >
                <Smile className="h-3.5 w-3.5 text-[var(--bc-primary)]" />
                <span>สติกเกอร์</span>
              </button>

              <button
                type="button"
                onClick={handleToggleRecording}
                className={`inline-flex h-7 shrink-0 items-center gap-1 rounded-lg border px-2 text-xs font-semibold ${
                  isRecording
                    ? "border-red-500 bg-red-600 text-white"
                    : "border-[var(--bc-border)] bg-[var(--bc-panel)] text-[var(--bc-text)] hover:bg-[var(--bc-soft)]"
                }`}
              >
                {isRecording ? <Square className="h-3 w-3" /> : <Mic className="h-3.5 w-3.5 text-[var(--bc-primary)]" />}
                <span>{isRecording ? `หยุด (${recordSeconds}s)` : "อัดเสียง"}</span>
              </button>

              <button
                type="button"
                onClick={() => {
                  setAiModalMode(null);
                  setShowCardModal((v) => !v);
                }}
                className={`inline-flex h-7 shrink-0 items-center gap-1 rounded-lg border px-2 text-xs font-semibold ${
                  showCardModal
                    ? "border-[var(--bc-primary)] bg-[var(--bc-soft)] text-[var(--bc-primary)]"
                    : "border-[var(--bc-border)] bg-[var(--bc-panel)] text-[var(--bc-text)] hover:bg-[var(--bc-soft)]"
                }`}
              >
                <Layers className="h-3.5 w-3.5 text-[var(--bc-primary)]" />
                <span>การ์ดโต้ตอบ</span>
              </button>

              <button
                type="button"
                onClick={() => setIsUrgent((v) => !v)}
                className={`inline-flex h-7 shrink-0 items-center gap-1 rounded-lg border px-2 text-xs font-semibold ${
                  isUrgent
                    ? "border-amber-600 bg-amber-600 text-white"
                    : "border-[var(--bc-border)] bg-[var(--bc-panel)] text-[var(--bc-text)]"
                }`}
              >
                <AlertTriangle className="h-3.5 w-3.5" />
                <span>เรื่องด่วน</span>
              </button>

              <button
                type="button"
                onClick={() => setIsConfidential((v) => !v)}
                className={`inline-flex h-7 shrink-0 items-center gap-1 rounded-lg border px-2 text-xs font-semibold ${
                  isConfidential
                    ? "border-[var(--bc-deep)] bg-[var(--bc-deep)] text-white"
                    : "border-[var(--bc-border)] bg-[var(--bc-panel)] text-[var(--bc-text)]"
                }`}
              >
                {isConfidential ? <EyeOff className="h-3.5 w-3.5" /> : <Eye className="h-3.5 w-3.5" />}
                <span>ข้อความลับ PIN</span>
              </button>

              {isConfidential && (
                <>
                  <input
                    type="text"
                    maxLength={6}
                    value={confidentialPin}
                    onChange={(e) => setConfidentialPin(e.target.value)}
                    placeholder="PIN"
                    className="h-7 w-14 shrink-0 rounded-lg border border-[var(--bc-primary)] bg-white px-2 text-center text-xs font-bold outline-none"
                  />
                  <button
                    type="button"
                    onClick={async () => {
                      const res = await api.clearConfidential(conversation.id);
                      await onRefreshMessages();
                      onNotify(`ลบข้อความลับไร้ร่องรอยแล้ว ${res.purged_messages} รายการ`);
                    }}
                    className="inline-flex h-7 shrink-0 items-center gap-1 rounded-lg border border-red-300 bg-red-50 px-2 text-xs font-semibold text-red-700"
                  >
                    <Eraser className="h-3.5 w-3.5" />
                    <span>ลบไร้ร่องรอย</span>
                  </button>
                </>
              )}

              {/* AI Quick Buttons */}
              <button
                type="button"
                data-testid="btn-ask-ai"
                onClick={() => {
                  setDraft((prev) => (prev.startsWith("@ai ") ? prev : `@ai ${prev}`));
                  inputRef.current?.focus();
                }}
                className="inline-flex h-7 shrink-0 items-center gap-1 rounded-lg border border-indigo-200 bg-indigo-50 px-2 text-xs font-semibold text-indigo-700 hover:bg-indigo-100"
              >
                <Bot className="h-3.5 w-3.5" />
                <span>✨ ถาม AI</span>
              </button>

              <button
                type="button"
                data-testid="btn-ai-assist"
                onClick={() => void handleOpenAiAssist("suggest_reply")}
                className="inline-flex h-7 shrink-0 items-center gap-1 rounded-lg border border-indigo-200 bg-indigo-50 px-2 text-xs font-semibold text-indigo-700 hover:bg-indigo-100"
              >
                <Wand2 className="h-3.5 w-3.5" />
                <span>🪄 AI ช่วยคิด/เกลา</span>
              </button>

              {miniApps.slice(0, 2).map((app) => (
                <button
                  key={app.id}
                  type="button"
                  onClick={() => onOpenMiniApp(app)}
                  className="hidden shrink-0 items-center gap-1 rounded-lg border border-[var(--bc-border)] bg-[var(--bc-surface)] px-2 py-1 text-[11px] font-medium text-[var(--bc-muted)] hover:text-[var(--bc-primary)] xl:inline-flex"
                >
                  <span>{app.title}</span>
                </button>
              ))}
            </div>

            {/* Input Form */}
            <form onSubmit={handleSendText} className="flex items-center gap-2">
              <input
                ref={inputRef}
                data-testid="chat-message-input"
                type="text"
                value={draft}
                onChange={(e) => handleDraftChange(e.target.value)}
                placeholder="พิมพ์ข้อความ... (@ แท็กเพื่อน, @ai ถาม AI)"
                className="h-10 min-w-0 flex-1 rounded-xl border border-[var(--bc-border)] bg-[var(--bc-surface)] px-3 text-sm text-[var(--bc-text)] outline-none focus:border-[var(--bc-primary)]"
              />
              <button
                type="submit"
                data-testid="chat-send-btn"
                disabled={sending || !draft.trim()}
                className="inline-flex h-10 shrink-0 items-center gap-1.5 rounded-xl bg-[var(--bc-primary)] px-3.5 text-sm font-bold text-white shadow-xs transition hover:brightness-95 disabled:opacity-50 sm:px-4"
              >
                <Send className="h-4 w-4" />
                <span>ส่ง</span>
              </button>
            </form>
          </div>
        </>
      )}
    </div>
  );
}
