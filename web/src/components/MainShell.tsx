"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import Link from "next/link";
import {
  ArrowLeft,
  Ban,
  BellOff,
  Bot,
  Check,
  Columns,
  Edit3,
  EyeOff,
  LogOut,
  Megaphone,
  MessageSquare,
  Palette,
  Pin,
  Plus,
  QrCode,
  Search,
  Send,
  Settings,
  Shield,
  Sparkles,
  Star,
  StickyNote,
  Trash2,
  UserPlus,
  Users,
  X,
} from "lucide-react";
import { api, formatFileSize, formatThaiTime } from "@/lib/api";
import { ROOM_TONES, THEME_PRESET_LIST } from "@/lib/themes";
import type {
  AdminOverview,
  AiSettings,
  ChatMessage,
  Conversation,
  FriendItem,
  MiniAppItem,
  NoteItem,
  RoomToneId,
  ThemePresetId,
  UserProfile,
} from "@/lib/types";
import { ChatRoomView, resolveMiniAppIframeUrl } from "./ChatRoomView";
import { QrCodeSvg } from "./QrCodeSvg";
import { UserAvatar } from "./StickerArt";

export type MainTabId = "home" | "chats" | "room" | "notes" | "services";
export type ChatFolderId =
  | "all"
  | "personal"
  | "family"
  | "group"
  | "pinned"
  | "unread"
  | "archived";

interface MainShellProps {
  currentUser: UserProfile;
  onUserUpdated: (user: UserProfile) => void;
  onLogout: () => void;
  activeTheme: ThemePresetId;
  onThemeUpdated: (preset: ThemePresetId) => void;
  roomTone: RoomToneId;
  onChangeRoomTone: (tone: RoomToneId) => void;
  wsTick: number;
  lastWsConvId: string | null;
}

export function MainShell({
  currentUser,
  onUserUpdated,
  onLogout,
  activeTheme,
  onThemeUpdated,
  roomTone,
  onChangeRoomTone,
  wsTick,
  lastWsConvId,
}: MainShellProps) {
  const [activeTab, setActiveTab] = useState<MainTabId>("chats");
  const [chatFolder, setChatFolder] = useState<ChatFolderId>("all");
  const [chatQuery, setChatQuery] = useState("");
  const [globalSearchMsgs, setGlobalSearchMsgs] = useState<ChatMessage[]>([]);

  const [friends, setFriends] = useState<FriendItem[]>([]);
  const [conversations, setConversations] = useState<Conversation[]>([]);
  const [activeConvId, setActiveConvId] = useState<string | null>(null);
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [personalNotes, setPersonalNotes] = useState<NoteItem[]>([]);
  const [miniApps, setMiniApps] = useState<MiniAppItem[]>([]);

  // Owner / Admin state
  const [adminOverview, setAdminOverview] = useState<AdminOverview | null>(null);
  const [aiSettings, setAiSettings] = useState<AiSettings | null>(null);
  const [broadcastTitle, setBroadcastTitle] = useState("แจ้งข่าวจาก BC Ai Chat");
  const [broadcastBody, setBroadcastBody] = useState("");

  // Inline Home / Profile / Group / Friend panels
  const [showQrInline, setShowQrInline] = useState(false);
  const [showEditProfile, setShowEditProfile] = useState(false);
  const [editName, setEditName] = useState(currentUser.display_name);
  const [editStatus, setEditStatus] = useState(currentUser.status_message);
  const [userSearchQuery, setUserSearchQuery] = useState("");
  const [userSearchResults, setUserSearchResults] = useState<UserProfile[]>([]);
  const [addFriendInput, setAddFriendInput] = useState("");
  const [joinTokenInput, setJoinTokenInput] = useState("");
  const [showHiddenBlocked, setShowHiddenBlocked] = useState(false);

  // Inline Create Group panel
  const [showCreateGroup, setShowCreateGroup] = useState(false);
  const [newGroupName, setNewGroupName] = useState("");
  const [newGroupFolder, setNewGroupFolder] = useState<"group" | "family">("group");
  const [newGroupMembers, setNewGroupMembers] = useState<string[]>([]);
  const [includeAiInGroup, setIncludeAiInGroup] = useState(true);

  // Personal notes
  const [noteQuery, setNoteQuery] = useState("");
  const [noteTitle, setNoteTitle] = useState("");
  const [noteBody, setNoteBody] = useState("");
  const [noteFile, setNoteFile] = useState<File | null>(null);

  // Inline Mini-App runner (inside Settings or active ChatRoom)
  const [runningMiniApp, setRunningMiniApp] = useState<MiniAppItem | null>(null);

  // Toast notice
  const [toast, setToast] = useState<string | null>(null);

  const notify = useCallback((msg: string) => {
    setToast(msg);
    setTimeout(() => {
      setToast((prev) => (prev === msg ? null : prev));
    }, 3500);
  }, []);

  const refreshCore = useCallback(async () => {
    try {
      const [fr, convs, apps, notes] = await Promise.all([
        api.listFriends(),
        api.listConversations("all"),
        api.listMiniApps(),
        api.listNotes(),
      ]);
      setFriends(fr);
      setConversations(convs);
      setMiniApps(apps);
      setPersonalNotes(notes);
      setActiveConvId((prev) => {
        if (prev && convs.some((c) => c.id === prev)) return prev;
        const preferred =
          convs.find((c) => c.id === "conv_group_demo5") || convs[0];
        return preferred ? preferred.id : null;
      });
    } catch {
      // Ignore transient errors
    }
  }, []);

  const refreshAdmin = useCallback(async () => {
    if (currentUser.role !== "admin") return;
    try {
      const [ov, ai] = await Promise.all([
        api.adminOverview(),
        api.adminGetAiSettings(),
      ]);
      setAdminOverview(ov);
      setAiSettings(ai);
    } catch {
      // Non-admin or offline
    }
  }, [currentUser.role]);

  const refreshActiveMessages = useCallback(async () => {
    if (!activeConvId) return;
    try {
      const msgs = await api.listMessages(activeConvId);
      setMessages(msgs);
      await api.markRead(activeConvId);
    } catch {
      // Ignore
    }
  }, [activeConvId]);

  useEffect(() => {
    void refreshCore();
    void refreshAdmin();
  }, [refreshCore, refreshAdmin]);

  useEffect(() => {
    if (activeConvId) {
      void refreshActiveMessages();
    }
  }, [activeConvId, refreshActiveMessages]);

  useEffect(() => {
    if (wsTick === 0) return;
    void refreshCore();
    if (!lastWsConvId || lastWsConvId === activeConvId) {
      void refreshActiveMessages();
    }
  }, [wsTick, lastWsConvId, activeConvId, refreshCore, refreshActiveMessages]);

  useEffect(() => {
    const onMsg = (ev: MessageEvent) => {
      if (ev.data && ev.data.event === "miniapp_card_sent") {
        void refreshActiveMessages();
        void refreshCore();
        setRunningMiniApp(null);
        notify("ส่งการ์ดจากเครื่องมือส่วนตัวเข้าห้องแชทเรียบร้อย");
      }
    };
    window.addEventListener("message", onMsg);
    return () => window.removeEventListener("message", onMsg);
  }, [refreshActiveMessages, refreshCore, notify]);

  const activeConversation = useMemo(
    () => conversations.find((c) => c.id === activeConvId) || null,
    [conversations, activeConvId]
  );

  const filteredConversations = useMemo(() => {
    const q = chatQuery.trim().toLowerCase();
    return conversations.filter((c) => {
      if (chatFolder === "archived") {
        if (!c.is_archived) return false;
      } else {
        if (c.is_archived) return false;
      }
      if (chatFolder === "personal" && c.folder !== "personal") return false;
      if (chatFolder === "family" && c.folder !== "family" && c.folder !== "work") return false;
      if (chatFolder === "group" && c.type !== "group") return false;
      if (chatFolder === "pinned" && !c.is_pinned) return false;
      if (chatFolder === "unread" && c.unread_count <= 0) return false;

      if (q) {
        const hitName = c.name.toLowerCase().includes(q);
        const hitLast = c.last_message?.content.toLowerCase().includes(q) ?? false;
        return hitName || hitLast;
      }
      return true;
    });
  }, [conversations, chatFolder, chatQuery]);

  const handleSearchChats = async (q: string) => {
    setChatQuery(q);
    if (q.trim().length >= 2) {
      try {
        setGlobalSearchMsgs(await api.searchMessages(q.trim()));
      } catch {
        setGlobalSearchMsgs([]);
      }
    } else {
      setGlobalSearchMsgs([]);
    }
  };

  const totalUnread = useMemo(
    () => conversations.reduce((sum, c) => sum + (c.unread_count || 0), 0),
    [conversations]
  );

  const visibleFriends = friends.filter((f) =>
    showHiddenBlocked ? true : !f.is_hidden && !f.is_blocked
  );

  const handleOpenRoom = (convId: string) => {
    setRunningMiniApp(null);
    setActiveConvId(convId);
    setActiveTab("room");
  };

  const handleSelectNavTab = (tab: MainTabId) => {
    setRunningMiniApp(null);
    setActiveTab(tab);
  };

  const handleAddFriend = async (payload: {
    target_id?: string;
    bc_id?: string;
    email?: string;
    qr_token?: string;
  }) => {
    try {
      const res = await api.addFriend(payload);
      await refreshCore();
      setActiveConvId(res.conversation_id);
      setAddFriendInput("");
      notify(`เพิ่มเพื่อน ${res.friend.display_name} เรียบร้อย`);
    } catch (err) {
      notify(err instanceof Error ? err.message : "เพิ่มเพื่อนไม่สำเร็จ");
    }
  };

  const handleCreateGroup = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!newGroupName.trim()) return;
    const ids = [...newGroupMembers];
    if (includeAiInGroup && !ids.includes("user_ai")) {
      ids.push("user_ai");
    }
    try {
      const created = await api.createGroupConversation({
        name: newGroupName.trim(),
        folder: newGroupFolder,
        member_ids: ids,
      });
      setShowCreateGroup(false);
      setNewGroupName("");
      setNewGroupMembers([]);
      await refreshCore();
      setActiveConvId(created.id);
      setActiveTab("room");
      notify(`สร้างกลุ่ม "${created.name}" แล้ว`);
    } catch (err) {
      notify(err instanceof Error ? err.message : "สร้างกลุ่มไม่สำเร็จ");
    }
  };

  const handleJoinGroup = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!joinTokenInput.trim()) return;
    try {
      const conv = await api.joinGroupByToken(joinTokenInput.trim());
      setJoinTokenInput("");
      await refreshCore();
      setActiveConvId(conv.id);
      setActiveTab("room");
      notify(`เข้าร่วมกลุ่ม "${conv.name}" สำเร็จ`);
    } catch (err) {
      notify(err instanceof Error ? err.message : "ไม่พบรหัสเชิญเข้ากลุ่มนี้");
    }
  };

  const handleCreatePersonalNote = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!noteTitle.trim() && !noteBody.trim()) return;
    try {
      const attachments = noteFile ? [await api.uploadFile(noteFile, noteFile.name)] : [];
      await api.createNote({
        title: noteTitle.trim() || "บันทึกสมุด BC",
        content: noteBody.trim(),
        attachments,
      });
      setNoteTitle("");
      setNoteBody("");
      setNoteFile(null);
      setPersonalNotes(await api.listNotes());
      notify("บันทึกเข้าสมุดบันทึก BC แล้ว");
    } catch (err) {
      notify(err instanceof Error ? err.message : "บันทึกไม่สำเร็จ");
    }
  };

  // 4 Thumb-Friendly Nav Items (เพื่อน / แชท / สมุดบันทึก / ตั้งค่า)
  const navItems: Array<{
    id: MainTabId;
    label: string;
    icon: React.ReactNode;
    badge?: number;
  }> = [
    { id: "home", label: "เพื่อน", icon: <Users className="h-5 w-5" /> },
    {
      id: "chats",
      label: "แชท",
      icon: <MessageSquare className="h-5 w-5" />,
      badge: totalUnread,
    },
    { id: "notes", label: "สมุดบันทึก", icon: <StickyNote className="h-5 w-5" /> },
    { id: "services", label: "ตั้งค่า", icon: <Settings className="h-5 w-5" /> },
  ];

  const showRoomOnDesktop = activeTab === "chats" || activeTab === "room";
  const isImmersiveMobileRoom = activeTab === "room";

  return (
    <div className="flex h-[100dvh] w-full flex-col overflow-hidden bg-[var(--bc-surface)] text-[var(--bc-text)]">
      {/* Global Top Bar (Hidden on < md when activeTab === "room" for 100% immersive mobile chat) */}
      <header
        className={`${
          isImmersiveMobileRoom ? "hidden md:flex" : "flex"
        } shrink-0 items-center justify-between gap-2 border-b border-[var(--bc-border)] bg-[var(--bc-card)] px-3 py-2 sm:px-4`}
      >
        <div className="flex min-w-0 items-center gap-2.5">
          <div
            className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl text-sm font-extrabold text-white shadow-2xs"
            style={{
              background: "linear-gradient(135deg, var(--bc-deep), var(--bc-primary))",
            }}
          >
            BC
          </div>
          <div className="min-w-0">
            <h1 className="truncate text-sm font-bold leading-tight text-[var(--bc-text)] sm:text-base">
              BC Ai Chat
            </h1>
            <p className="truncate text-[11px] text-[var(--bc-muted)]">
              {currentUser.display_name} ({currentUser.bc_id}) • {currentUser.department}
            </p>
          </div>
        </div>

        <div className="flex shrink-0 items-center gap-2">
          <Link
            href="/multi-demo"
            className="hidden items-center gap-1.5 rounded-xl border border-[var(--bc-border)] bg-[var(--bc-panel)] px-3 py-1.5 text-xs font-semibold text-[var(--bc-primary)] hover:bg-[var(--bc-soft)] sm:inline-flex"
          >
            <Columns className="h-3.5 w-3.5" />
            <span>จอคุย 5 คน</span>
          </Link>
          <button
            type="button"
            data-testid="logout-btn"
            onClick={onLogout}
            className="inline-flex items-center gap-1.5 rounded-xl border border-[var(--bc-border)] bg-[var(--bc-panel)] px-3 py-1.5 text-xs font-semibold text-[var(--bc-text)] hover:bg-red-50 hover:text-red-700"
          >
            <LogOut className="h-3.5 w-3.5" />
            <span>สลับบัญชี</span>
          </button>
        </div>
      </header>

      {/* Main Content Area (Desktop Split-View >= md, Mobile single column) */}
      <div className="flex min-h-0 flex-1 overflow-hidden">
        {/* Desktop Left Rail Navigation (md+) */}
        <nav
          aria-label="เมนูหลัก BC Ai Chat"
          className="hidden w-20 shrink-0 flex-col items-center justify-between border-r border-[var(--bc-border)] bg-[var(--bc-panel)] py-3 md:flex"
        >
          <div className="flex w-full flex-col items-center gap-1.5 px-1.5">
            {navItems.map((item) => {
              const active =
                activeTab === item.id ||
                (item.id === "chats" && activeTab === "room");
              return (
                <button
                  key={item.id}
                  type="button"
                  data-testid={`nav-tab-${item.id}`}
                  onClick={() => handleSelectNavTab(item.id)}
                  className={`relative flex w-full flex-col items-center justify-center gap-1 rounded-2xl px-1 py-2.5 text-[10px] font-bold transition ${
                    active
                      ? "bg-[var(--bc-primary)] text-white shadow-sm"
                      : "text-[var(--bc-muted)] hover:bg-[var(--bc-soft)] hover:text-[var(--bc-primary)]"
                  }`}
                >
                  {item.icon}
                  <span className="text-center leading-tight">{item.label}</span>
                  {item.badge && item.badge > 0 ? (
                    <span className="absolute right-2 top-1.5 rounded-full bg-red-600 px-1.5 py-0.2 text-[9px] font-bold text-white">
                      {item.badge}
                    </span>
                  ) : null}
                </button>
              );
            })}
          </div>
          <button
            type="button"
            onClick={() => {
              setActiveTab("home");
              setShowQrInline(true);
            }}
            title="QR Code ของฉัน"
            aria-label="QR Code ของฉัน"
            className="flex h-10 w-10 items-center justify-center rounded-xl border border-[var(--bc-border)] bg-[var(--bc-card)] text-[var(--bc-primary)] hover:bg-[var(--bc-soft)]"
          >
            <QrCode className="h-5 w-5" />
          </button>
        </nav>

        {/* Left/Main Pane */}
        <section
          className={`${
            showRoomOnDesktop
              ? activeTab === "room"
                ? "hidden md:flex md:w-[340px] lg:w-[370px]"
                : "flex w-full md:w-[340px] lg:w-[370px]"
              : "flex w-full flex-1"
          } min-h-0 shrink-0 flex-col overflow-hidden border-r border-[var(--bc-border)] bg-[var(--bc-surface)]`}
        >
          {/* TAB 1: เพื่อน & โปรไฟล์ (Home / Friends) */}
          {activeTab === "home" && (
            <div className="flex-1 space-y-4 overflow-y-auto p-3.5 sm:p-6">
              <div className="mx-auto max-w-4xl space-y-4">
                {/* Profile Card + Inline QR & Edit Profile */}
                <div className="space-y-3 rounded-3xl border border-[var(--bc-border)] bg-[var(--bc-card)] p-4 shadow-xs sm:p-5">
                  <div className="flex flex-wrap items-center justify-between gap-3">
                    <div className="flex min-w-0 items-center gap-3">
                      <UserAvatar
                        name={currentUser.display_name}
                        avatarUrl={currentUser.avatar_url}
                        size={52}
                      />
                      <div className="min-w-0">
                        <div className="flex flex-wrap items-center gap-1.5">
                          <h2 className="truncate text-base font-bold text-[var(--bc-text)] sm:text-lg">
                            {currentUser.display_name}
                          </h2>
                          <span className="rounded-full bg-[var(--bc-soft)] px-2 py-0.5 text-[11px] font-bold text-[var(--bc-primary)]">
                            {currentUser.bc_id}
                          </span>
                        </div>
                        <p className="truncate text-xs text-[var(--bc-muted)]">
                          {currentUser.department} • {currentUser.job_title}
                        </p>
                        <p className="mt-0.5 truncate text-xs text-[var(--bc-text)]">
                          {currentUser.status_message}
                        </p>
                      </div>
                    </div>

                    <div className="flex flex-wrap items-center gap-2">
                      <button
                        type="button"
                        data-testid="toggle-qr-inline-btn"
                        onClick={() => setShowQrInline((v) => !v)}
                        className={`inline-flex items-center gap-1.5 rounded-xl border px-3 py-2 text-xs font-bold transition ${
                          showQrInline
                            ? "border-[var(--bc-primary)] bg-[var(--bc-soft)] text-[var(--bc-deep)]"
                            : "border-[var(--bc-border)] bg-[var(--bc-panel)] text-[var(--bc-primary)] hover:bg-[var(--bc-soft)]"
                        }`}
                      >
                        <QrCode className="h-4 w-4" />
                        <span>{showQrInline ? "ซ่อน QR" : "QR Code ของฉัน"}</span>
                      </button>
                      <button
                        type="button"
                        onClick={() => setShowEditProfile((v) => !v)}
                        className="inline-flex items-center gap-1.5 rounded-xl bg-[var(--bc-primary)] px-3 py-2 text-xs font-bold text-white"
                      >
                        <Edit3 className="h-4 w-4" />
                        <span>แก้ไขโปรไฟล์</span>
                      </button>
                    </div>
                  </div>

                  {/* Inline QR Code Card (Zero Modal) */}
                  {showQrInline && (
                    <div
                      data-testid="inline-qr-card"
                      className="flex flex-col items-center gap-3 rounded-2xl border border-[var(--bc-border)] bg-[var(--bc-panel)] p-4 text-center sm:flex-row sm:text-left"
                    >
                      <QrCodeSvg value={currentUser.qr_token || currentUser.bc_id} size={156} />
                      <div className="min-w-0 flex-1 space-y-1 text-xs">
                        <div className="text-sm font-bold text-[var(--bc-text)]">
                          QR Code เพิ่มเพื่อนของฉัน
                        </div>
                        <div className="text-[var(--bc-muted)]">
                          ให้เพื่อนหรือคนในครอบครัวสแกนหรือกรอก BC ID เพื่อเริ่มแชทส่วนตัว
                        </div>
                        <div className="font-semibold text-[var(--bc-text)]">
                          {currentUser.display_name} ({currentUser.bc_id})
                        </div>
                        <div className="break-all font-mono text-[11px] text-[var(--bc-primary)]">
                          {currentUser.qr_token}
                        </div>
                        <button
                          type="button"
                          onClick={() => setShowQrInline(false)}
                          className="mt-1 inline-flex items-center gap-1 rounded-lg border border-[var(--bc-border)] bg-[var(--bc-card)] px-2.5 py-1 text-[11px] font-semibold text-[var(--bc-text)]"
                        >
                          <X className="h-3 w-3" />
                          <span>ปิด QR</span>
                        </button>
                      </div>
                    </div>
                  )}

                  {/* Inline Edit Profile Form */}
                  {showEditProfile && (
                    <form
                      onSubmit={async (e) => {
                        e.preventDefault();
                        const updated = await api.updateProfile({
                          display_name: editName.trim(),
                          status_message: editStatus.trim(),
                        });
                        onUserUpdated(updated);
                        setShowEditProfile(false);
                        notify("อัปเดตโปรไฟล์เรียบร้อย");
                      }}
                      className="grid grid-cols-1 gap-2.5 rounded-2xl border border-[var(--bc-border)] bg-[var(--bc-panel)] p-3.5 sm:grid-cols-3"
                    >
                      <input
                        type="text"
                        value={editName}
                        onChange={(e) => setEditName(e.target.value)}
                        placeholder="ชื่อแสดงผล"
                        className="rounded-xl border border-[var(--bc-border)] bg-[var(--bc-card)] px-3 py-2 text-xs outline-none"
                      />
                      <input
                        type="text"
                        value={editStatus}
                        onChange={(e) => setEditStatus(e.target.value)}
                        placeholder="ข้อความสถานะ"
                        className="rounded-xl border border-[var(--bc-border)] bg-[var(--bc-card)] px-3 py-2 text-xs outline-none"
                      />
                      <button
                        type="submit"
                        className="rounded-xl bg-[var(--bc-primary)] px-4 py-2 text-xs font-bold text-white"
                      >
                        บันทึกข้อมูล
                      </button>
                    </form>
                  )}
                </div>

                {/* Add Friend + Search + Inline Create Group + Join Group */}
                <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
                  <div className="space-y-3 rounded-3xl border border-[var(--bc-border)] bg-[var(--bc-card)] p-4">
                    <h3 className="flex items-center gap-2 text-sm font-bold text-[var(--bc-primary)]">
                      <UserPlus className="h-4 w-4" />
                      <span>ค้นหา &amp; เพิ่มเพื่อน</span>
                    </h3>
                    <div className="flex gap-2">
                      <input
                        type="text"
                        value={addFriendInput}
                        onChange={(e) => setAddFriendInput(e.target.value)}
                        placeholder="BC ID (@prae.bc), อีเมล หรือ QR Token"
                        className="min-w-0 flex-1 rounded-xl border border-[var(--bc-border)] bg-[var(--bc-surface)] px-3 py-2 text-xs outline-none"
                      />
                      <button
                        type="button"
                        onClick={() =>
                          handleAddFriend(
                            addFriendInput.includes("@") && addFriendInput.includes(".")
                              ? addFriendInput.startsWith("@")
                                ? { bc_id: addFriendInput }
                                : { email: addFriendInput }
                              : addFriendInput.startsWith("BCQR_")
                                ? { qr_token: addFriendInput }
                                : { bc_id: addFriendInput }
                          )
                        }
                        className="shrink-0 rounded-xl bg-[var(--bc-primary)] px-3.5 py-2 text-xs font-bold text-white"
                      >
                        เพิ่มเพื่อน
                      </button>
                    </div>
                    <div className="flex gap-2">
                      <input
                        type="text"
                        value={userSearchQuery}
                        onChange={(e) => setUserSearchQuery(e.target.value)}
                        placeholder="ค้นหาชื่อเพื่อนด้วยชื่อหรือ BC ID..."
                        className="min-w-0 flex-1 rounded-xl border border-[var(--bc-border)] bg-[var(--bc-surface)] px-3 py-2 text-xs outline-none"
                      />
                      <button
                        type="button"
                        onClick={async () => {
                          setUserSearchResults(await api.searchUsers(userSearchQuery));
                        }}
                        className="shrink-0 rounded-xl border border-[var(--bc-border)] bg-[var(--bc-panel)] px-3 py-2 text-xs font-semibold"
                      >
                        ค้นหา
                      </button>
                    </div>
                    {userSearchResults.length > 0 && (
                      <div className="max-h-40 space-y-1.5 overflow-y-auto pt-1">
                        {userSearchResults
                          .filter((u) => u.id !== currentUser.id)
                          .map((u) => (
                            <div
                              key={u.id}
                              className="flex items-center justify-between gap-2 rounded-xl bg-[var(--bc-panel)] px-3 py-1.5 text-xs"
                            >
                              <span className="truncate font-semibold">
                                {u.display_name} ({u.bc_id})
                              </span>
                              <button
                                type="button"
                                onClick={() => handleAddFriend({ target_id: u.id })}
                                className="shrink-0 rounded-lg bg-[var(--bc-primary)] px-2.5 py-1 text-[11px] font-bold text-white"
                              >
                                + เพิ่ม
                              </button>
                            </div>
                          ))}
                      </div>
                    )}
                  </div>

                  <div className="space-y-3 rounded-3xl border border-[var(--bc-border)] bg-[var(--bc-card)] p-4">
                    <h3 className="flex items-center gap-2 text-sm font-bold text-[var(--bc-primary)]">
                      <Users className="h-4 w-4" />
                      <span>สร้างกลุ่มใหม่ / เข้าร่วมด้วยรหัสเชิญ</span>
                    </h3>
                    <button
                      type="button"
                      data-testid="open-create-group-btn"
                      onClick={() => setShowCreateGroup((v) => !v)}
                      className="flex w-full items-center justify-center gap-2 rounded-xl bg-[var(--bc-primary)] px-4 py-2.5 text-xs font-bold text-white"
                    >
                      <Plus className="h-4 w-4" />
                      <span>
                        {showCreateGroup
                          ? "ซ่อนฟอร์มสร้างกลุ่ม"
                          : "สร้างกลุ่มแชทใหม่ (พร้อมดึง 🤖 BC AI)"}
                      </span>
                    </button>

                    {/* Inline Create Group Form (Zero Modal) */}
                    {showCreateGroup && (
                      <form
                        data-testid="inline-create-group-form"
                        onSubmit={handleCreateGroup}
                        className="space-y-2.5 rounded-2xl border border-[var(--bc-border)] bg-[var(--bc-panel)] p-3.5"
                      >
                        <div className="flex items-center justify-between">
                          <span className="text-xs font-bold text-[var(--bc-text)]">
                            ตั้งค่ากลุ่มแชทใหม่
                          </span>
                          <button
                            type="button"
                            onClick={() => setShowCreateGroup(false)}
                            aria-label="ปิดฟอร์มสร้างกลุ่ม"
                            className="rounded-lg p-1 text-[var(--bc-muted)] hover:bg-[var(--bc-card)]"
                          >
                            <X className="h-3.5 w-3.5" />
                          </button>
                        </div>
                        <input
                          type="text"
                          required
                          value={newGroupName}
                          onChange={(e) => setNewGroupName(e.target.value)}
                          placeholder="ชื่อกลุ่ม เช่น แก๊งนัดกินหมูกระทะ / ทริปเชียงใหม่"
                          className="w-full rounded-xl border border-[var(--bc-border)] bg-[var(--bc-card)] px-3 py-2 text-xs outline-none focus:border-[var(--bc-primary)]"
                        />
                        <div className="flex items-center gap-2 text-xs">
                          <span className="font-semibold text-[var(--bc-muted)]">หมวดหมู่:</span>
                          <button
                            type="button"
                            onClick={() => setNewGroupFolder("group")}
                            className={`rounded-full px-2.5 py-1 text-[11px] font-semibold ${
                              newGroupFolder === "group"
                                ? "bg-[var(--bc-primary)] text-white"
                                : "border border-[var(--bc-border)] bg-[var(--bc-card)]"
                            }`}
                          >
                            กลุ่มเพื่อน
                          </button>
                          <button
                            type="button"
                            onClick={() => setNewGroupFolder("family")}
                            className={`rounded-full px-2.5 py-1 text-[11px] font-semibold ${
                              newGroupFolder === "family"
                                ? "bg-[var(--bc-primary)] text-white"
                                : "border border-[var(--bc-border)] bg-[var(--bc-card)]"
                            }`}
                          >
                            ครอบครัว
                          </button>
                        </div>
                        <label className="flex items-center gap-2 rounded-xl border border-indigo-200 bg-indigo-50 px-3 py-2 text-xs font-bold text-indigo-800">
                          <input
                            type="checkbox"
                            checked={includeAiInGroup}
                            onChange={(e) => setIncludeAiInGroup(e.target.checked)}
                          />
                          <Bot className="h-4 w-4 shrink-0" />
                          <span>ดึง 🤖 BC AI เข้ากลุ่มอัตโนมัติ</span>
                        </label>
                        <div className="max-h-40 space-y-1.5 overflow-y-auto">
                          {friends
                            .filter((f) => f.id !== "user_ai")
                            .map((f) => {
                              const checked = newGroupMembers.includes(f.id);
                              return (
                                <label
                                  key={f.id}
                                  className="flex cursor-pointer items-center gap-2 rounded-xl border border-[var(--bc-border)] bg-[var(--bc-card)] px-3 py-2 text-xs"
                                >
                                  <input
                                    type="checkbox"
                                    checked={checked}
                                    onChange={(e) =>
                                      setNewGroupMembers((prev) =>
                                        e.target.checked
                                          ? [...prev, f.id]
                                          : prev.filter((id) => id !== f.id)
                                      )
                                    }
                                  />
                                  <span className="truncate font-semibold">{f.display_name}</span>
                                  <span className="shrink-0 text-[11px] text-[var(--bc-muted)]">
                                    ({f.department})
                                  </span>
                                </label>
                              );
                            })}
                        </div>
                        <div className="flex justify-end gap-2 pt-1">
                          <button
                            type="button"
                            onClick={() => setShowCreateGroup(false)}
                            className="rounded-xl border border-[var(--bc-border)] bg-[var(--bc-card)] px-3 py-1.5 text-xs font-semibold"
                          >
                            ยกเลิก
                          </button>
                          <button
                            type="submit"
                            className="rounded-xl bg-[var(--bc-primary)] px-3.5 py-1.5 text-xs font-bold text-white"
                          >
                            สร้างกลุ่มทันที
                          </button>
                        </div>
                      </form>
                    )}

                    <form onSubmit={handleJoinGroup} className="flex gap-2">
                      <input
                        type="text"
                        value={joinTokenInput}
                        onChange={(e) => setJoinTokenInput(e.target.value)}
                        placeholder="วางรหัสเชิญกลุ่ม (invite_token)"
                        className="min-w-0 flex-1 rounded-xl border border-[var(--bc-border)] bg-[var(--bc-surface)] px-3 py-2 text-xs outline-none"
                      />
                      <button
                        type="submit"
                        className="shrink-0 rounded-xl border border-[var(--bc-primary)] bg-[var(--bc-soft)] px-3.5 py-2 text-xs font-bold text-[var(--bc-deep)]"
                      >
                        เข้าร่วมกลุ่ม
                      </button>
                    </form>
                  </div>
                </div>

                {/* Friend List */}
                <div className="rounded-3xl border border-[var(--bc-border)] bg-[var(--bc-card)] p-4">
                  <div className="mb-3 flex flex-wrap items-center justify-between gap-2">
                    <h3 className="text-sm font-bold text-[var(--bc-text)]">
                      รายชื่อเพื่อน &amp; ครอบครัว ({visibleFriends.length})
                    </h3>
                    <button
                      type="button"
                      onClick={() => setShowHiddenBlocked((v) => !v)}
                      className="text-xs font-semibold text-[var(--bc-primary)]"
                    >
                      {showHiddenBlocked ? "ซ่อนรายการที่บล็อก/ซ่อน" : "ดูรายชื่อที่ซ่อน/บล็อก"}
                    </button>
                  </div>
                  <div className="grid grid-cols-1 gap-2.5 sm:grid-cols-2">
                    {visibleFriends.map((f) => (
                      <div
                        key={f.id}
                        className="flex items-center justify-between gap-2 rounded-2xl border border-[var(--bc-border)] bg-[var(--bc-panel)] p-3"
                      >
                        <div className="flex min-w-0 items-center gap-2.5">
                          <UserAvatar
                            name={f.display_name}
                            avatarUrl={f.avatar_url}
                            size={38}
                            isAi={f.id === "user_ai"}
                          />
                          <div className="min-w-0">
                            <div className="truncate text-xs font-bold text-[var(--bc-text)]">
                              {f.display_name}
                            </div>
                            <div className="truncate text-[11px] text-[var(--bc-muted)]">
                              {f.department} • {f.bc_id}
                            </div>
                          </div>
                        </div>
                        <div className="flex shrink-0 items-center gap-1">
                          <button
                            type="button"
                            title="รายการโปรด"
                            onClick={async () => {
                              await api.updateFriendStatus(f.id, { is_favorite: !f.is_favorite });
                              await refreshCore();
                            }}
                            className={`rounded-lg p-1.5 ${
                              f.is_favorite ? "text-amber-500" : "text-[var(--bc-muted)]"
                            }`}
                          >
                            <Star className="h-3.5 w-3.5" />
                          </button>
                          <button
                            type="button"
                            title="ซ่อนเพื่อน"
                            onClick={async () => {
                              await api.updateFriendStatus(f.id, { is_hidden: !f.is_hidden });
                              await refreshCore();
                            }}
                            className={`rounded-lg p-1.5 ${
                              f.is_hidden ? "text-[var(--bc-primary)]" : "text-[var(--bc-muted)]"
                            }`}
                          >
                            <EyeOff className="h-3.5 w-3.5" />
                          </button>
                          <button
                            type="button"
                            title="บล็อก"
                            onClick={async () => {
                              await api.updateFriendStatus(f.id, { is_blocked: !f.is_blocked });
                              await refreshCore();
                            }}
                            className={`rounded-lg p-1.5 ${
                              f.is_blocked ? "text-red-600" : "text-[var(--bc-muted)]"
                            }`}
                          >
                            <Ban className="h-3.5 w-3.5" />
                          </button>
                          <button
                            type="button"
                            onClick={async () => {
                              const conv = await api.openDirectConversation(f.id);
                              await refreshCore();
                              handleOpenRoom(conv.id);
                            }}
                            className="rounded-xl bg-[var(--bc-primary)] px-2.5 py-1 text-[11px] font-bold text-white"
                          >
                            แชท
                          </button>
                        </div>
                      </div>
                    ))}
                  </div>
                </div>
              </div>
            </div>
          )}

          {/* TAB 2 / 3 LEFT LIST: CHATS */}
          {(activeTab === "chats" || activeTab === "room") && (
            <div className="flex h-full min-h-0 flex-col">
              <div className="space-y-2 border-b border-[var(--bc-border)] bg-[var(--bc-card)] p-3">
                <div className="flex items-center gap-2">
                  <div className="flex min-w-0 flex-1 items-center gap-2 rounded-xl border border-[var(--bc-border)] bg-[var(--bc-surface)] px-3 py-1.5">
                    <Search className="h-4 w-4 shrink-0 text-[var(--bc-muted)]" />
                    <input
                      type="text"
                      value={chatQuery}
                      onChange={(e) => void handleSearchChats(e.target.value)}
                      placeholder="ค้นหาชื่อห้องหรือข้อความ..."
                      className="min-w-0 w-full bg-transparent text-xs outline-none"
                    />
                  </div>
                  <button
                    type="button"
                    onClick={() => {
                      setActiveTab("home");
                      setShowCreateGroup(true);
                    }}
                    title="สร้างกลุ่มใหม่"
                    className="inline-flex h-8 shrink-0 items-center gap-1 rounded-xl border border-[var(--bc-border)] bg-[var(--bc-panel)] px-2.5 text-xs font-bold text-[var(--bc-primary)] hover:bg-[var(--bc-soft)]"
                  >
                    <Plus className="h-3.5 w-3.5" />
                    <span>กลุ่ม</span>
                  </button>
                </div>

                {/* 7 Horizontally Scrollable Folder Chips */}
                <div
                  data-testid="chat-folder-chips"
                  className="flex items-center gap-1.5 overflow-x-auto whitespace-nowrap pb-0.5"
                >
                  {(
                    [
                      ["all", "ทั้งหมด"],
                      ["personal", "ส่วนตัว"],
                      ["family", "ครอบครัว"],
                      ["group", "กลุ่ม"],
                      ["pinned", "ปักหมุด"],
                      ["unread", "ยังไม่อ่าน"],
                      ["archived", "เก็บถาวร"],
                    ] as const
                  ).map(([fid, label]) => (
                    <button
                      key={fid}
                      type="button"
                      data-testid={`folder-chip-${fid}`}
                      onClick={() => setChatFolder(fid)}
                      className={`shrink-0 rounded-full px-2.5 py-1 text-[11px] font-semibold transition ${
                        chatFolder === fid
                          ? "bg-[var(--bc-primary)] text-white"
                          : "bg-[var(--bc-panel)] text-[var(--bc-muted)] hover:bg-[var(--bc-soft)]"
                      }`}
                    >
                      {label}
                    </button>
                  ))}
                </div>
              </div>

              <div className="flex-1 divide-y divide-[var(--bc-border)]/60 overflow-y-auto">
                {globalSearchMsgs.length > 0 && (
                  <div className="bg-[var(--bc-soft)]/40 p-2.5">
                    <div className="mb-1 text-[11px] font-bold text-[var(--bc-primary)]">
                      ผลการค้นหาข้ามห้อง ({globalSearchMsgs.length})
                    </div>
                    {globalSearchMsgs.slice(0, 5).map((gm) => (
                      <button
                        key={gm.id}
                        type="button"
                        onClick={() => handleOpenRoom(gm.conversation_id)}
                        className="block w-full truncate rounded-lg px-2 py-1 text-left text-xs hover:bg-white"
                      >
                        <span className="font-bold">{gm.sender_name}: </span>
                        <span>{gm.content}</span>
                      </button>
                    ))}
                  </div>
                )}

                {filteredConversations.map((c) => {
                  const selected = c.id === activeConvId;
                  return (
                    <button
                      key={c.id}
                      type="button"
                      data-testid={`conv-item-${c.id}`}
                      onClick={() => handleOpenRoom(c.id)}
                      className={`flex w-full items-center gap-3 px-3.5 py-3 text-left transition ${
                        selected
                          ? "bg-[var(--bc-soft)]/70"
                          : "bg-[var(--bc-card)] hover:bg-[var(--bc-panel)]"
                      }`}
                    >
                      <UserAvatar
                        name={c.name}
                        avatarUrl={c.avatar_url}
                        size={42}
                        isAi={c.members.some((m) => m.id === "user_ai") && c.type === "direct"}
                        isOfficial={c.type === "official"}
                      />
                      <div className="min-w-0 flex-1">
                        <div className="flex items-center justify-between gap-2">
                          <div className="flex min-w-0 items-center gap-1">
                            {c.is_pinned && (
                              <Pin className="h-3 w-3 shrink-0 text-[var(--bc-primary)]" />
                            )}
                            <span className="truncate text-sm font-bold text-[var(--bc-text)]">
                              {c.name}
                            </span>
                            {c.is_muted && (
                              <BellOff className="h-3 w-3 shrink-0 text-[var(--bc-muted)]" />
                            )}
                          </div>
                          <span className="shrink-0 text-[10px] text-[var(--bc-muted)]">
                            {formatThaiTime(c.updated_at)}
                          </span>
                        </div>
                        <div className="mt-0.5 flex items-center justify-between gap-2">
                          <p className="truncate text-xs text-[var(--bc-muted)]">
                            {c.last_message?.content || "เริ่มสนทนาได้เลย"}
                          </p>
                          {c.unread_count > 0 && (
                            <span className="inline-flex h-5 min-w-5 shrink-0 items-center justify-center rounded-full bg-[var(--bc-primary)] px-1.5 text-[10px] font-bold text-white">
                              {c.unread_count}
                            </span>
                          )}
                        </div>
                      </div>
                    </button>
                  );
                })}
              </div>
            </div>
          )}

          {/* TAB 3: สมุดบันทึก BC (Personal Notes) */}
          {activeTab === "notes" && (
            <div className="flex-1 overflow-y-auto p-3.5 sm:p-6">
              <div className="mx-auto max-w-4xl space-y-4">
                <div className="flex flex-wrap items-center justify-between gap-3">
                  <div>
                    <h2 className="text-lg font-bold text-[var(--bc-text)]">
                      สมุดบันทึก BC (คลังบันทึกส่วนตัวถาวร)
                    </h2>
                    <p className="text-xs text-[var(--bc-muted)]">
                      บันทึกข้อความ รูปภาพ ลิสต์หนัง และไฟล์สำคัญส่วนตัวไม่หมดอายุ
                    </p>
                  </div>
                  <div className="flex w-full items-center gap-2 rounded-xl border border-[var(--bc-border)] bg-[var(--bc-card)] px-3 py-1.5 sm:w-auto">
                    <Search className="h-4 w-4 shrink-0 text-[var(--bc-muted)]" />
                    <input
                      type="text"
                      value={noteQuery}
                      onChange={(e) => setNoteQuery(e.target.value)}
                      placeholder="ค้นหาบันทึก..."
                      className="min-w-0 flex-1 text-xs outline-none"
                    />
                  </div>
                </div>

                <form
                  onSubmit={handleCreatePersonalNote}
                  className="space-y-3 rounded-3xl border border-[var(--bc-border)] bg-[var(--bc-card)] p-4"
                >
                  <input
                    type="text"
                    value={noteTitle}
                    onChange={(e) => setNoteTitle(e.target.value)}
                    placeholder="หัวข้อบันทึก..."
                    className="w-full rounded-xl border border-[var(--bc-border)] bg-[var(--bc-surface)] px-3 py-2 text-sm outline-none"
                  />
                  <textarea
                    rows={3}
                    value={noteBody}
                    onChange={(e) => setNoteBody(e.target.value)}
                    placeholder="เนื้อหาบันทึก..."
                    className="w-full rounded-xl border border-[var(--bc-border)] bg-[var(--bc-surface)] px-3 py-2 text-xs outline-none"
                  />
                  <div className="flex flex-wrap items-center justify-between gap-2">
                    <input
                      type="file"
                      onChange={(e) => setNoteFile(e.target.files?.[0] || null)}
                      className="max-w-full text-xs text-[var(--bc-muted)]"
                    />
                    <button
                      type="submit"
                      data-testid="create-personal-note-btn"
                      className="inline-flex items-center gap-1.5 rounded-xl bg-[var(--bc-primary)] px-4 py-2 text-xs font-bold text-white"
                    >
                      <Plus className="h-3.5 w-3.5" />
                      <span>บันทึกลงสมุดบันทึก BC</span>
                    </button>
                  </div>
                </form>

                <div className="grid grid-cols-1 gap-3 md:grid-cols-2">
                  {personalNotes
                    .filter((n) => {
                      const q = noteQuery.trim().toLowerCase();
                      if (!q) return true;
                      return (
                        n.title.toLowerCase().includes(q) ||
                        n.content.toLowerCase().includes(q)
                      );
                    })
                    .map((n) => (
                      <div
                        key={n.id}
                        className="flex flex-col justify-between space-y-2 rounded-2xl border border-[var(--bc-border)] bg-[var(--bc-card)] p-4"
                      >
                        <div>
                          <div className="flex items-start justify-between gap-2">
                            <h3 className="text-sm font-bold text-[var(--bc-text)]">{n.title}</h3>
                            <div className="flex shrink-0 items-center gap-1">
                              <button
                                type="button"
                                onClick={async () => {
                                  await api.updateNote(n.id, { is_pinned: !n.is_pinned });
                                  setPersonalNotes(await api.listNotes());
                                }}
                                className={`rounded-lg p-1 ${
                                  n.is_pinned ? "text-[var(--bc-primary)]" : "text-[var(--bc-muted)]"
                                }`}
                              >
                                <Pin className="h-3.5 w-3.5" />
                              </button>
                              <button
                                type="button"
                                onClick={async () => {
                                  await api.deleteNote(n.id);
                                  setPersonalNotes(await api.listNotes());
                                }}
                                className="rounded-lg p-1 text-red-600"
                              >
                                <Trash2 className="h-3.5 w-3.5" />
                              </button>
                            </div>
                          </div>
                          <p className="mt-1 whitespace-pre-wrap text-xs text-[var(--bc-muted)]">
                            {n.content}
                          </p>
                          {n.attachments.length > 0 && (
                            <div className="mt-2 space-y-1">
                              {n.attachments.map((att) => (
                                <a
                                  key={att.key}
                                  href={`/api/files/${att.key}`}
                                  target="_blank"
                                  rel="noreferrer"
                                  className="inline-flex items-center gap-1 text-xs font-semibold text-[var(--bc-primary)] underline"
                                >
                                  <span>📎 {att.file_name}</span>
                                </a>
                              ))}
                            </div>
                          )}
                        </div>
                        <div className="text-[10px] text-[var(--bc-muted)]">
                          อัปเดตล่าสุด {formatThaiTime(n.updated_at)}
                        </div>
                      </div>
                    ))}
                </div>
              </div>
            </div>
          )}

          {/* TAB 4: ตั้งค่า & เครื่องมือส่วนตัว */}
          {activeTab === "services" && (
            <div className="flex-1 overflow-y-auto p-3.5 sm:p-6">
              <div className="mx-auto max-w-5xl space-y-5">
                {runningMiniApp ? (
                  /* Inline Mini-App Runner (Zero Modal) */
                  <div
                    data-testid="inline-miniapp-settings-runner"
                    className="flex h-[74dvh] min-h-[420px] flex-col overflow-hidden rounded-3xl border border-[var(--bc-border)] bg-[var(--bc-card)] shadow-sm"
                  >
                    <div className="flex shrink-0 items-center justify-between gap-2 border-b border-[var(--bc-border)] bg-[var(--bc-panel)] px-4 py-2.5">
                      <button
                        type="button"
                        data-testid="close-inline-miniapp"
                        onClick={() => setRunningMiniApp(null)}
                        className="inline-flex items-center gap-1.5 rounded-xl border border-[var(--bc-border)] bg-[var(--bc-card)] px-3 py-1.5 text-xs font-bold text-[var(--bc-primary)] hover:bg-[var(--bc-soft)]"
                      >
                        <ArrowLeft className="h-3.5 w-3.5" />
                        <span>← กลับ</span>
                      </button>
                      <span className="truncate text-sm font-bold text-[var(--bc-text)]">
                        {runningMiniApp.title}
                      </span>
                    </div>
                    <iframe
                      title={runningMiniApp.title}
                      src={resolveMiniAppIframeUrl(
                        runningMiniApp,
                        activeConvId || "conv_group_demo5"
                      )}
                      className="w-full flex-1 border-0"
                    />
                  </div>
                ) : (
                  <>
                    <div className="flex flex-wrap items-center justify-between gap-2">
                      <div>
                        <h2 className="text-lg font-bold text-[var(--bc-text)]">
                          ตั้งค่า &amp; เครื่องมือส่วนตัว
                        </h2>
                        <p className="text-xs text-[var(--bc-muted)]">
                          เลือกโทนห้องแชท เครื่องมือไลฟ์สไตล์ ธีมสีไทย และตั้งค่าผู้ช่วย AI ส่วนตัว
                        </p>
                      </div>
                    </div>

                    {/* Personal Room Tone Chooser (All Users) */}
                    <div className="space-y-2.5 rounded-3xl border border-[var(--bc-border)] bg-[var(--bc-card)] p-4 sm:p-5">
                      <div className="flex items-center gap-2 text-sm font-bold text-[var(--bc-primary)]">
                        <Palette className="h-4 w-4" />
                        <span>โทนสีพื้นหลังห้องแชทส่วนตัว (3 แบบ)</span>
                      </div>
                      <div className="grid grid-cols-1 gap-2 sm:grid-cols-3">
                        {Object.values(ROOM_TONES).map((t) => {
                          const active = roomTone === t.id;
                          return (
                            <button
                              key={t.id}
                              type="button"
                              onClick={() => {
                                onChangeRoomTone(t.id);
                                notify(`เปลี่ยนโทนห้องแชทเป็น "${t.label}" แล้ว`);
                              }}
                              className={`flex items-center justify-between gap-2 rounded-2xl border p-3 text-left text-xs font-semibold transition ${
                                active
                                  ? "border-[var(--bc-primary)] bg-[var(--bc-soft)]/70 text-[var(--bc-deep)]"
                                  : "border-[var(--bc-border)] bg-[var(--bc-panel)] hover:bg-[var(--bc-soft)]/30"
                              }`}
                            >
                              <span className="flex items-center gap-2">
                                <span
                                  style={{ backgroundColor: t.swatch }}
                                  className="h-5 w-5 shrink-0 rounded-full border border-[var(--bc-border)]"
                                />
                                <span>{t.label}</span>
                              </span>
                              {active && <Check className="h-4 w-4 text-[var(--bc-primary)]" />}
                            </button>
                          );
                        })}
                      </div>
                    </div>

                    {/* Personal Lifestyle Tools (Mini-Apps) */}
                    <div className="rounded-3xl border border-[var(--bc-border)] bg-[var(--bc-card)] p-4 sm:p-5">
                      <h3 className="mb-3 flex items-center gap-2 text-sm font-bold text-[var(--bc-text)]">
                        <Sparkles className="h-4 w-4 text-[var(--bc-primary)]" />
                        <span>เครื่องมือไลฟ์สไตล์ &amp; ผู้ช่วยส่วนตัว (Mini-Apps)</span>
                      </h3>
                      <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3">
                        {miniApps.map((app) => (
                          <button
                            key={app.id}
                            type="button"
                            onClick={() => setRunningMiniApp(app)}
                            className="flex flex-col items-start rounded-2xl border border-[var(--bc-border)] bg-[var(--bc-panel)] p-3.5 text-left transition hover:border-[var(--bc-primary)] hover:bg-[var(--bc-soft)]/50"
                          >
                            <span
                              style={{
                                backgroundColor: app.color_hex || "#812920",
                              }}
                              className="mb-2 inline-flex rounded-lg px-2 py-0.5 text-[10px] font-bold text-white"
                            >
                              {app.category}
                            </span>
                            <div className="text-sm font-bold text-[var(--bc-text)]">{app.title}</div>
                            <div className="mt-0.5 text-xs text-[var(--bc-muted)]">{app.subtitle}</div>
                          </button>
                        ))}
                      </div>
                    </div>

                    {/* Owner / Admin Personal Settings */}
                    {currentUser.role === "admin" ? (
                      <div className="space-y-4 rounded-3xl border border-[var(--bc-border)] bg-[var(--bc-card)] p-4 sm:p-5">
                        <div className="flex items-center justify-between">
                          <h3 className="flex items-center gap-2 text-sm font-bold text-[var(--bc-primary)]">
                            <Shield className="h-4 w-4" />
                            <span>ตั้งค่าระบบส่วนตัว (สำหรับเจ้าของระบบ)</span>
                          </h3>
                        </div>

                        {/* Stats */}
                        {adminOverview && (
                          <div className="grid grid-cols-2 gap-2.5 sm:grid-cols-5">
                            <div className="rounded-2xl bg-[var(--bc-panel)] p-3">
                              <div className="text-[11px] text-[var(--bc-muted)]">สมาชิก</div>
                              <div className="text-lg font-extrabold">{adminOverview.total_users}</div>
                            </div>
                            <div className="rounded-2xl bg-[var(--bc-panel)] p-3">
                              <div className="text-[11px] text-[var(--bc-muted)]">ห้องแชท</div>
                              <div className="text-lg font-extrabold">
                                {adminOverview.total_conversations}
                              </div>
                            </div>
                            <div className="rounded-2xl bg-[var(--bc-panel)] p-3">
                              <div className="text-[11px] text-[var(--bc-muted)]">ข้อความ</div>
                              <div className="text-lg font-extrabold">{adminOverview.total_messages}</div>
                            </div>
                            <div className="rounded-2xl bg-[var(--bc-panel)] p-3">
                              <div className="text-[11px] text-[var(--bc-muted)]">ไฟล์ถาวร</div>
                              <div className="text-lg font-extrabold">{adminOverview.total_files}</div>
                            </div>
                            <div className="col-span-2 rounded-2xl bg-[var(--bc-panel)] p-3 sm:col-span-1">
                              <div className="text-[11px] text-[var(--bc-muted)]">พื้นที่ใช้ไป</div>
                              <div className="text-lg font-extrabold">
                                {formatFileSize(adminOverview.total_storage_bytes)}
                              </div>
                            </div>
                          </div>
                        )}

                        {/* 7 Thai Heritage Themes Live Switcher */}
                        <div className="space-y-2 rounded-2xl border border-[var(--bc-border)] bg-[var(--bc-panel)] p-4">
                          <div className="flex items-center gap-2 text-xs font-bold text-[var(--bc-primary)]">
                            <Palette className="h-4 w-4" />
                            <span>เลือก 7 ธีมส่วนตัวแบบเรียลไทม์ (ซิงค์ทุกจอทันที)</span>
                          </div>
                          <div className="grid grid-cols-1 gap-2 sm:grid-cols-2 lg:grid-cols-4">
                            {THEME_PRESET_LIST.map((th) => {
                              const active = th.id === activeTheme;
                              return (
                                <button
                                  key={th.id}
                                  type="button"
                                  data-testid={`theme-btn-${th.id}`}
                                  onClick={async () => {
                                    await api.setTheme(th.id);
                                    onThemeUpdated(th.id);
                                    notify(`เปลี่ยนธีมแชทเป็น "${th.name}" แล้ว`);
                                  }}
                                  className={`flex items-center gap-2.5 rounded-xl border p-2.5 text-left text-xs transition ${
                                    active
                                      ? "border-[var(--bc-primary)] bg-white font-bold shadow-xs"
                                      : "border-[var(--bc-border)] bg-white/70 hover:bg-white"
                                  }`}
                                >
                                  <span
                                    style={{ backgroundColor: th.primary }}
                                    className="h-5 w-5 shrink-0 rounded-full"
                                  />
                                  <div className="min-w-0">
                                    <div className="truncate text-[var(--bc-text)]">{th.name}</div>
                                    <div className="truncate text-[10px] text-[var(--bc-muted)]">
                                      {th.subtitle}
                                    </div>
                                  </div>
                                </button>
                              );
                            })}
                          </div>
                        </div>

                        {/* Personal Broadcast & Private AI Settings */}
                        <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
                          <form
                            onSubmit={async (e) => {
                              e.preventDefault();
                              const res = await api.adminBroadcast(broadcastTitle, broadcastBody);
                              setBroadcastBody("");
                              notify(`ส่งประกาศส่วนตัวแล้ว ${res.sent_count} บัญชี`);
                            }}
                            className="space-y-2.5 rounded-2xl border border-[var(--bc-border)] bg-[var(--bc-panel)] p-4"
                          >
                            <div className="flex items-center gap-2 text-xs font-bold text-[var(--bc-primary)]">
                              <Megaphone className="h-4 w-4" />
                              <span>ส่งประกาศส่วนตัวถึงเพื่อนและครอบครัวทุกคน</span>
                            </div>
                            <input
                              type="text"
                              value={broadcastTitle}
                              onChange={(e) => setBroadcastTitle(e.target.value)}
                              className="w-full rounded-xl border border-[var(--bc-border)] bg-white px-3 py-1.5 text-xs outline-none"
                            />
                            <textarea
                              rows={2}
                              required
                              value={broadcastBody}
                              onChange={(e) => setBroadcastBody(e.target.value)}
                              placeholder="ข้อความแจ้งข่าวส่วนตัว..."
                              className="w-full rounded-xl border border-[var(--bc-border)] bg-white px-3 py-1.5 text-xs outline-none"
                            />
                            <button
                              type="submit"
                              className="inline-flex items-center gap-1.5 rounded-xl bg-[var(--bc-primary)] px-3.5 py-1.5 text-xs font-bold text-white"
                            >
                              <Send className="h-3.5 w-3.5" />
                              <span>ส่งแจ้งข่าว</span>
                            </button>
                          </form>

                          {aiSettings && (
                            <form
                              onSubmit={async (e) => {
                                e.preventDefault();
                                const updated = await api.adminUpdateAiSettings({
                                  enabled: aiSettings.enabled,
                                  model: aiSettings.model,
                                  system_prompt: aiSettings.system_prompt,
                                  auto_reply_in_groups: aiSettings.auto_reply_in_groups,
                                  redact_confidential: aiSettings.redact_confidential,
                                });
                                setAiSettings(updated);
                                notify("บันทึกการตั้งค่า AI ส่วนตัวแล้ว");
                              }}
                              className="space-y-2.5 rounded-2xl border border-[var(--bc-border)] bg-[var(--bc-panel)] p-4"
                            >
                              <div className="flex items-center justify-between gap-2">
                                <div className="flex items-center gap-2 text-xs font-bold text-[var(--bc-primary)]">
                                  <Sparkles className="h-4 w-4" />
                                  <span>ตั้งค่า AI ส่วนตัว ({aiSettings.masked_key || "พร้อมใช้งาน"})</span>
                                </div>
                                <label className="inline-flex items-center gap-1.5 text-xs font-semibold">
                                  <input
                                    type="checkbox"
                                    checked={aiSettings.enabled}
                                    onChange={(e) =>
                                      setAiSettings({ ...aiSettings, enabled: e.target.checked })
                                    }
                                  />
                                  <span>เปิดใช้งาน AI</span>
                                </label>
                              </div>
                              <textarea
                                rows={2}
                                value={aiSettings.system_prompt}
                                onChange={(e) =>
                                  setAiSettings({ ...aiSettings, system_prompt: e.target.value })
                                }
                                className="w-full rounded-xl border border-[var(--bc-border)] bg-white px-3 py-1.5 text-xs outline-none"
                              />
                              <button
                                type="submit"
                                className="rounded-xl bg-[var(--bc-primary)] px-3.5 py-1.5 text-xs font-bold text-white"
                              >
                                บันทึกตั้งค่า AI ส่วนตัว
                              </button>
                            </form>
                          )}
                        </div>
                      </div>
                    ) : (
                      <div className="rounded-2xl border border-[var(--bc-border)] bg-[var(--bc-card)] p-4 text-xs text-[var(--bc-muted)]">
                        ต้องการสลับ 7 ธีมสีไทยร่วมสมัยแบบสด, ส่งแจ้งข่าวส่วนตัว หรือปรับแต่งผู้ช่วย AI?
                        กด &quot;สลับบัญชี&quot; แล้วเลือกเข้าสู่ระบบด้วย{" "}
                        <strong className="text-[var(--bc-primary)]">ลุงจืด (jead@bcaichat.local)</strong>
                      </div>
                    )}
                  </>
                )}
              </div>
            </div>
          )}
        </section>

        {/* Right Split-View Pane: Active Chat Room */}
        {showRoomOnDesktop && (
          <section
            className={`${
              activeTab === "room" ? "flex w-full" : "hidden md:flex"
            } min-h-0 flex-1 flex-col overflow-hidden`}
          >
            {activeConversation ? (
              <ChatRoomView
                conversation={activeConversation}
                messages={messages}
                currentUser={currentUser}
                friends={friends}
                miniApps={miniApps}
                roomTone={roomTone}
                onChangeRoomTone={onChangeRoomTone}
                onConversationUpdated={refreshCore}
                onRefreshMessages={refreshActiveMessages}
                onOpenMiniApp={(app) => setRunningMiniApp(app)}
                runningMiniApp={runningMiniApp}
                onCloseMiniApp={() => setRunningMiniApp(null)}
                onBackMobile={() => {
                  setRunningMiniApp(null);
                  setActiveTab("chats");
                }}
                onNotify={notify}
              />
            ) : (
              <div className="flex flex-1 items-center justify-center p-6 text-sm text-[var(--bc-muted)]">
                เลือกห้องแชทจากรายการด้านซ้ายเพื่อเริ่มสนทนา
              </div>
            )}
          </section>
        )}
      </div>

      {/* Mobile Bottom Nav (< md, hidden when activeTab === "room" for immersive full-screen chat) */}
      <nav
        aria-label="เมนูล่างมือถือ"
        data-testid="mobile-bottom-nav"
        className={`${
          isImmersiveMobileRoom ? "hidden" : "flex"
        } shrink-0 items-center justify-around border-t border-[var(--bc-border)] bg-[var(--bc-card)] px-1 py-1.5 pb-[max(0.375rem,env(safe-area-inset-bottom))] md:hidden`}
      >
        {navItems.map((item) => {
          const active = activeTab === item.id;
          return (
            <button
              key={item.id}
              type="button"
              data-testid={`mobile-nav-tab-${item.id}`}
              onClick={() => handleSelectNavTab(item.id)}
              className={`relative flex min-h-[44px] flex-1 flex-col items-center justify-center gap-0.5 rounded-xl px-2 py-1 text-[11px] font-bold transition ${
                active
                  ? "bg-[var(--bc-soft)]/60 text-[var(--bc-primary)]"
                  : "text-[var(--bc-muted)]"
              }`}
            >
              {item.icon}
              <span>{item.label}</span>
              {item.badge && item.badge > 0 ? (
                <span className="absolute right-3 top-0.5 rounded-full bg-red-600 px-1.5 text-[9px] text-white">
                  {item.badge}
                </span>
              ) : null}
            </button>
          );
        })}
      </nav>

      {/* Non-blocking Toast Notice */}
      {toast && (
        <div
          role="status"
          className="fixed bottom-20 right-4 z-40 max-w-[calc(100vw-2rem)] rounded-2xl border border-[var(--bc-primary)] bg-[var(--bc-deep)] px-4 py-2.5 text-xs font-bold text-white shadow-xl md:bottom-5"
        >
          {toast}
        </div>
      )}
    </div>
  );
}
