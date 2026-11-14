import type {
  AdminOverview,
  AiAssistResult,
  AiSettings,
  AiSummaryResult,
  AlbumItem,
  AttachmentInfo,
  ChatMessage,
  Conversation,
  FriendItem,
  MiniAppItem,
  NoteItem,
  RichCardPayload,
  RoomToneId,
  ThemePresetId,
  UserProfile,
  VaultResponse,
} from "./types";

const STORAGE_TOKEN_KEY = "bcaichat_tab_token";
const STORAGE_USER_KEY = "bcaichat_tab_user";
const STORAGE_ROOM_TONE_KEY = "bcaichat_room_tone";

export function getTabToken(): string {
  if (typeof window === "undefined") return "";
  return window.sessionStorage.getItem(STORAGE_TOKEN_KEY) || "";
}

export function setTabSession(token: string, user: UserProfile): void {
  if (typeof window === "undefined") return;
  window.sessionStorage.setItem(STORAGE_TOKEN_KEY, token);
  window.sessionStorage.setItem(STORAGE_USER_KEY, JSON.stringify(user));
}

export function getTabUser(): UserProfile | null {
  if (typeof window === "undefined") return null;
  const raw = window.sessionStorage.getItem(STORAGE_USER_KEY);
  if (!raw) return null;
  try {
    return JSON.parse(raw) as UserProfile;
  } catch {
    return null;
  }
}

export function clearTabSession(): void {
  if (typeof window === "undefined") return;
  window.sessionStorage.removeItem(STORAGE_TOKEN_KEY);
  window.sessionStorage.removeItem(STORAGE_USER_KEY);
}

export function getSavedRoomTone(): RoomToneId {
  if (typeof window === "undefined") return "ban_chiang_cream";
  const raw = window.localStorage.getItem(STORAGE_ROOM_TONE_KEY);
  if (raw === "terracotta_night" || raw === "ivory_white" || raw === "ban_chiang_cream") {
    return raw;
  }
  return "ban_chiang_cream";
}

export function saveRoomTone(tone: RoomToneId): void {
  if (typeof window === "undefined") return;
  window.localStorage.setItem(STORAGE_ROOM_TONE_KEY, tone);
}

export function getWsUrl(token: string, deviceId = "web_tab"): string {
  const configured = process.env.NEXT_PUBLIC_WS_URL;
  let base = configured || "ws://127.0.0.1:8096/ws";
  if (!configured && typeof window !== "undefined") {
    const proto = window.location.protocol === "https:" ? "wss:" : "ws:";
    const host = window.location.hostname || "127.0.0.1";
    base = `${proto}//${host}:8096/ws`;
  }
  const sep = base.includes("?") ? "&" : "?";
  return `${base}${sep}token=${encodeURIComponent(token)}&device=${encodeURIComponent(deviceId)}`;
}

export function resolveMediaUrl(rawUrl?: string | null): string {
  if (!rawUrl) return "";
  try {
    const u = new URL(rawUrl, "http://127.0.0.1:8096");
    if (u.pathname.startsWith("/api/files/")) {
      return u.pathname;
    }
    return rawUrl;
  } catch {
    return rawUrl;
  }
}

export function normalizeMessage(raw: Record<string, unknown>): ChatMessage {
  const rawPayload =
    (raw.card_payload as RichCardPayload | null | undefined) ??
    (raw["flex_payload"] as RichCardPayload | null | undefined) ??
    null;
  const rawType = String(raw.type ?? raw.msg_type ?? "text");
  const normalizedType = rawType === "flex_card" ? "rich_card" : rawType;

  return {
    id: String(raw.id ?? raw._id ?? ""),
    conversation_id: String(raw.conversation_id ?? ""),
    sender_id: String(raw.sender_id ?? ""),
    sender_name: String(raw.sender_name ?? "สมาชิก"),
    sender_avatar: String(raw.sender_avatar ?? ""),
    type: normalizedType,
    content: String(raw.content ?? ""),
    sticker_code: (raw.sticker_code as string | null | undefined) ?? null,
    attachment: (raw.attachment as AttachmentInfo | null | undefined) ?? null,
    card_payload: rawPayload,
    reply_to: (raw.reply_to as ChatMessage["reply_to"]) ?? null,
    read_by: Array.isArray(raw.read_by) ? raw.read_by.map(String) : [],
    read_count: Number(raw.read_count ?? 0),
    is_unsent: Boolean(raw.is_unsent),
    is_confidential: Boolean(raw.is_confidential),
    confidential_pin: (raw.confidential_pin as string | null | undefined) ?? null,
    expire_at: (raw.expire_at as string | null | undefined) ?? null,
    priority: String(raw.priority ?? "normal"),
    task_status: (raw.task_status as string | null | undefined) ?? null,
    accepted_by: (raw.accepted_by as string | null | undefined) ?? null,
    accepted_at: (raw.accepted_at as string | null | undefined) ?? null,
    reactions:
      raw.reactions && typeof raw.reactions === "object"
        ? (raw.reactions as Record<string, string[]>)
        : {},
    mentions: Array.isArray(raw.mentions) ? raw.mentions.map(String) : [],
    audio_duration_sec:
      raw.audio_duration_sec !== undefined && raw.audio_duration_sec !== null
        ? Number(raw.audio_duration_sec)
        : null,
    poll: (raw.poll as ChatMessage["poll"]) ?? null,
    event_data: (raw.event_data as ChatMessage["event_data"]) ?? null,
    created_at: String(raw.created_at ?? ""),
  };
}

export class ApiClient {
  private tokenOverride: string | null = null;

  constructor(tokenOverride?: string) {
    this.tokenOverride = tokenOverride ?? null;
  }

  private getToken(): string {
    return this.tokenOverride !== null ? this.tokenOverride : getTabToken();
  }

  private async request<T>(
    path: string,
    options: RequestInit = {},
    skipAuth = false
  ): Promise<T> {
    const headers = new Headers(options.headers);
    if (!headers.has("Content-Type") && !(options.body instanceof FormData)) {
      headers.set("Content-Type", "application/json");
    }
    const token = this.getToken();
    if (!skipAuth && token) {
      headers.set("Authorization", `Bearer ${token}`);
    }

    const res = await fetch(path, {
      ...options,
      headers,
      cache: "no-store",
    });

    const text = await res.text();
    let parsed: unknown = null;
    try {
      parsed = text ? JSON.parse(text) : null;
    } catch {
      parsed = text;
    }

    if (!res.ok) {
      const msg =
        parsed && typeof parsed === "object" && "error" in parsed
          ? String((parsed as { error: unknown }).error)
          : `คำขอไม่สำเร็จ (HTTP ${res.status})`;
      throw new Error(msg);
    }

    return parsed as T;
  }

  async getHealth(): Promise<{ status: string; mongodb: boolean; minio: boolean }> {
    return this.request("/api/health", {}, true);
  }

  async getTheme(): Promise<{ preset: ThemePresetId }> {
    return this.request("/api/settings/theme", {}, true);
  }

  async setTheme(preset: ThemePresetId): Promise<{ preset: ThemePresetId }> {
    return this.request("/api/settings/theme", {
      method: "PUT",
      body: JSON.stringify({ preset }),
    });
  }

  async loginDemoOrEmail(params: {
    email: string;
    display_name?: string;
    department?: string;
    job_title?: string;
  }): Promise<{ token: string; user: UserProfile }> {
    const res = await this.request<{ token: string; user: UserProfile }>(
      "/api/auth/google",
      {
        method: "POST",
        body: JSON.stringify({
          email: params.email,
          display_name: params.display_name,
          department: params.department,
          job_title: params.job_title,
          id_token: `demo_${Date.now()}`,
        }),
      },
      true
    );
    return res;
  }

  async getMe(): Promise<UserProfile> {
    return this.request<UserProfile>("/api/auth/me");
  }

  async updateProfile(payload: {
    display_name?: string;
    bc_id?: string;
    status_message?: string;
    department?: string;
    job_title?: string;
  }): Promise<UserProfile> {
    return this.request<UserProfile>("/api/auth/profile", {
      method: "PUT",
      body: JSON.stringify(payload),
    });
  }

  async listFriends(): Promise<FriendItem[]> {
    return this.request<FriendItem[]>("/api/friends");
  }

  async updateFriendStatus(
    friendId: string,
    payload: { is_favorite?: boolean; is_blocked?: boolean; is_hidden?: boolean }
  ): Promise<FriendItem> {
    return this.request<FriendItem>(`/api/friends/${encodeURIComponent(friendId)}`, {
      method: "PUT",
      body: JSON.stringify(payload),
    });
  }

  async searchUsers(q: string): Promise<UserProfile[]> {
    return this.request<UserProfile[]>(`/api/users/search?q=${encodeURIComponent(q)}`);
  }

  async addFriend(payload: {
    target_id?: string;
    bc_id?: string;
    email?: string;
    qr_token?: string;
  }): Promise<{ friend: FriendItem; conversation_id: string; conversation: Conversation }> {
    return this.request("/api/friends/add", {
      method: "POST",
      body: JSON.stringify(payload),
    });
  }

  async listConversations(folder = "all"): Promise<Conversation[]> {
    return this.request<Conversation[]>(
      `/api/conversations?folder=${encodeURIComponent(folder)}`
    );
  }

  async openDirectConversation(friendId: string): Promise<Conversation> {
    return this.request<Conversation>("/api/conversations/direct", {
      method: "POST",
      body: JSON.stringify({ friend_id: friendId }),
    });
  }

  async createGroupConversation(payload: {
    name: string;
    folder?: string;
    member_ids: string[];
    avatar_url?: string;
  }): Promise<Conversation> {
    return this.request<Conversation>("/api/conversations/group", {
      method: "POST",
      body: JSON.stringify(payload),
    });
  }

  async joinGroupByToken(inviteToken: string): Promise<Conversation> {
    return this.request<Conversation>("/api/conversations/join", {
      method: "POST",
      body: JSON.stringify({ invite_token: inviteToken }),
    });
  }

  async updateConversationMeta(
    convId: string,
    payload: {
      folder?: string;
      is_pinned?: boolean;
      is_muted?: boolean;
      is_archived?: boolean;
      name?: string;
      avatar_url?: string;
    }
  ): Promise<Conversation> {
    return this.request<Conversation>(
      `/api/conversations/${encodeURIComponent(convId)}/meta`,
      {
        method: "PUT",
        body: JSON.stringify(payload),
      }
    );
  }

  async inviteGroupMembers(convId: string, memberIds: string[]): Promise<Conversation> {
    return this.request<Conversation>(
      `/api/conversations/${encodeURIComponent(convId)}/members`,
      {
        method: "POST",
        body: JSON.stringify({ member_ids: memberIds }),
      }
    );
  }

  async removeGroupMember(convId: string, memberId: string): Promise<Conversation> {
    return this.request<Conversation>(
      `/api/conversations/${encodeURIComponent(convId)}/members/${encodeURIComponent(memberId)}`,
      {
        method: "DELETE",
      }
    );
  }

  async pinMessage(convId: string, messageId: string | null): Promise<Conversation> {
    return this.request<Conversation>(
      `/api/conversations/${encodeURIComponent(convId)}/pin-message`,
      {
        method: "PUT",
        body: JSON.stringify({ message_id: messageId }),
      }
    );
  }

  async listMessages(convId: string): Promise<ChatMessage[]> {
    const raw = await this.request<Record<string, unknown>[]>(
      `/api/conversations/${encodeURIComponent(convId)}/messages`
    );
    return raw.map(normalizeMessage);
  }

  async sendMessage(
    convId: string,
    payload: {
      type?: string;
      content?: string;
      sticker_code?: string;
      attachment?: AttachmentInfo;
      card_payload?: RichCardPayload;
      reply_to_id?: string;
      is_confidential?: boolean;
      confidential_pin?: string;
      expire_at?: string;
      priority?: string;
      task_status?: string;
      mentions?: string[];
      audio_duration_sec?: number;
    }
  ): Promise<ChatMessage> {
    const bodyPayload: Record<string, unknown> = {
      type: payload.type || "text",
      content: payload.content,
      sticker_code: payload.sticker_code,
      attachment: payload.attachment,
      reply_to_id: payload.reply_to_id,
      is_confidential: payload.is_confidential ?? false,
      confidential_pin: payload.confidential_pin,
      expire_at: payload.expire_at,
      priority: payload.priority,
      task_status: payload.task_status,
      mentions: payload.mentions,
      audio_duration_sec: payload.audio_duration_sec,
    };
    if (payload.card_payload) {
      bodyPayload.card_payload = payload.card_payload;
    }
    const raw = await this.request<Record<string, unknown>>(
      `/api/conversations/${encodeURIComponent(convId)}/messages`,
      {
        method: "POST",
        body: JSON.stringify(bodyPayload),
      }
    );
    return normalizeMessage(raw);
  }

  async markRead(convId: string): Promise<void> {
    await this.request(`/api/conversations/${encodeURIComponent(convId)}/read`, {
      method: "POST",
    });
  }

  async reactMessage(msgId: string, emoji: string): Promise<ChatMessage> {
    const raw = await this.request<Record<string, unknown>>(
      `/api/messages/${encodeURIComponent(msgId)}/react`,
      {
        method: "POST",
        body: JSON.stringify({ emoji }),
      }
    );
    return normalizeMessage(raw);
  }

  async deleteMessageForMe(msgId: string): Promise<void> {
    await this.request(`/api/messages/${encodeURIComponent(msgId)}/delete-for-me`, {
      method: "POST",
    });
  }

  async unsendMessage(msgId: string, hard = false): Promise<void> {
    await this.request(
      `/api/messages/${encodeURIComponent(msgId)}/unsend?hard=${hard ? "true" : "false"}`,
      {
        method: "DELETE",
      }
    );
  }

  async clearConfidential(convId: string): Promise<{ purged_messages: number; purged_files: number }> {
    return this.request(`/api/conversations/${encodeURIComponent(convId)}/clear-confidential`, {
      method: "POST",
    });
  }

  async taskAction(msgId: string, action: "accept" | "done" | "reopen"): Promise<ChatMessage> {
    const raw = await this.request<Record<string, unknown>>(
      `/api/messages/${encodeURIComponent(msgId)}/task-action`,
      {
        method: "POST",
        body: JSON.stringify({ action }),
      }
    );
    return normalizeMessage(raw);
  }

  async approveCard(msgId: string, status: string, comment?: string): Promise<ChatMessage> {
    const raw = await this.request<Record<string, unknown>>(
      `/api/messages/${encodeURIComponent(msgId)}/approve-card`,
      {
        method: "POST",
        body: JSON.stringify({ status, comment }),
      }
    );
    return normalizeMessage(raw);
  }

  async createPoll(
    convId: string,
    payload: {
      question: string;
      options: string[];
      allow_multiple?: boolean;
      is_anonymous?: boolean;
    }
  ): Promise<ChatMessage> {
    const raw = await this.request<Record<string, unknown>>(
      `/api/conversations/${encodeURIComponent(convId)}/polls`,
      {
        method: "POST",
        body: JSON.stringify(payload),
      }
    );
    return normalizeMessage(raw);
  }

  async votePoll(msgId: string, optionIds: string[]): Promise<ChatMessage> {
    const raw = await this.request<Record<string, unknown>>(
      `/api/messages/${encodeURIComponent(msgId)}/vote`,
      {
        method: "POST",
        body: JSON.stringify({ option_ids: optionIds }),
      }
    );
    return normalizeMessage(raw);
  }

  async closePoll(msgId: string): Promise<ChatMessage> {
    const raw = await this.request<Record<string, unknown>>(
      `/api/messages/${encodeURIComponent(msgId)}/close-poll`,
      {
        method: "POST",
      }
    );
    return normalizeMessage(raw);
  }

  async listEvents(convId: string): Promise<ChatMessage[]> {
    const raw = await this.request<Record<string, unknown>[]>(
      `/api/conversations/${encodeURIComponent(convId)}/events`
    );
    return raw.map(normalizeMessage);
  }

  async createEvent(
    convId: string,
    payload: {
      title: string;
      description?: string;
      starts_at: string;
      ends_at?: string;
      location?: string;
    }
  ): Promise<ChatMessage> {
    const raw = await this.request<Record<string, unknown>>(
      `/api/conversations/${encodeURIComponent(convId)}/events`,
      {
        method: "POST",
        body: JSON.stringify(payload),
      }
    );
    return normalizeMessage(raw);
  }

  async rsvpEvent(
    msgId: string,
    status: "going" | "maybe" | "not_going"
  ): Promise<ChatMessage> {
    const raw = await this.request<Record<string, unknown>>(
      `/api/messages/${encodeURIComponent(msgId)}/rsvp`,
      {
        method: "POST",
        body: JSON.stringify({ status }),
      }
    );
    return normalizeMessage(raw);
  }

  async listAlbums(convId: string): Promise<AlbumItem[]> {
    return this.request<AlbumItem[]>(
      `/api/conversations/${encodeURIComponent(convId)}/albums`
    );
  }

  async createAlbum(
    convId: string,
    payload: { title: string; description?: string; photos?: AttachmentInfo[] }
  ): Promise<AlbumItem> {
    return this.request<AlbumItem>(
      `/api/conversations/${encodeURIComponent(convId)}/albums`,
      {
        method: "POST",
        body: JSON.stringify(payload),
      }
    );
  }

  async addAlbumPhotos(albumId: string, photos: AttachmentInfo[]): Promise<AlbumItem> {
    return this.request<AlbumItem>(
      `/api/albums/${encodeURIComponent(albumId)}/photos`,
      {
        method: "POST",
        body: JSON.stringify({ photos }),
      }
    );
  }

  async deleteAlbum(albumId: string): Promise<void> {
    await this.request(`/api/albums/${encodeURIComponent(albumId)}`, {
      method: "DELETE",
    });
  }

  async getVault(convId: string): Promise<VaultResponse> {
    return this.request<VaultResponse>(
      `/api/conversations/${encodeURIComponent(convId)}/vault`
    );
  }

  async searchMessages(q: string, conversationId?: string): Promise<ChatMessage[]> {
    const params = new URLSearchParams({ q });
    if (conversationId) params.set("conversation_id", conversationId);
    const raw = await this.request<Record<string, unknown>[]>(
      `/api/messages/search?${params.toString()}`
    );
    return raw.map(normalizeMessage);
  }

  async listNotes(conversationId?: string): Promise<NoteItem[]> {
    const q = conversationId
      ? `?conversation_id=${encodeURIComponent(conversationId)}`
      : "";
    return this.request<NoteItem[]>(`/api/notes${q}`);
  }

  async createNote(payload: {
    conversation_id?: string;
    title: string;
    content: string;
    attachments?: AttachmentInfo[];
    is_pinned?: boolean;
  }): Promise<NoteItem> {
    return this.request<NoteItem>("/api/notes", {
      method: "POST",
      body: JSON.stringify(payload),
    });
  }

  async updateNote(
    noteId: string,
    payload: { title?: string; content?: string; is_pinned?: boolean }
  ): Promise<NoteItem> {
    return this.request<NoteItem>(`/api/notes/${encodeURIComponent(noteId)}`, {
      method: "PUT",
      body: JSON.stringify(payload),
    });
  }

  async deleteNote(noteId: string): Promise<void> {
    await this.request(`/api/notes/${encodeURIComponent(noteId)}`, {
      method: "DELETE",
    });
  }

  async likeNote(noteId: string): Promise<NoteItem> {
    return this.request<NoteItem>(`/api/notes/${encodeURIComponent(noteId)}/like`, {
      method: "POST",
    });
  }

  async commentNote(noteId: string, content: string): Promise<NoteItem> {
    return this.request<NoteItem>(`/api/notes/${encodeURIComponent(noteId)}/comments`, {
      method: "POST",
      body: JSON.stringify({ content }),
    });
  }

  async uploadFile(file: File | Blob, fileName?: string, conversationId?: string): Promise<AttachmentInfo> {
    const form = new FormData();
    form.append("file", file, fileName || (file instanceof File ? file.name : "recording.webm"));
    if (fileName) form.append("file_name", fileName);
    if (conversationId) form.append("conversation_id", conversationId);
    const res = await this.request<AttachmentInfo & { id: string }>("/api/upload", {
      method: "POST",
      body: form,
    });
    return {
      key: res.key,
      url: res.url,
      file_name: res.file_name,
      mime_type: res.mime_type,
      file_size: res.file_size,
    };
  }

  async summarizeChat(conversationId: string, postToChat = false): Promise<AiSummaryResult> {
    return this.request<AiSummaryResult>("/api/ai/summarize", {
      method: "POST",
      body: JSON.stringify({
        conversation_id: conversationId,
        post_to_chat: postToChat,
      }),
    });
  }

  async assistAi(payload: {
    conversation_id?: string;
    prompt?: string;
    mode: "polish" | "formal" | "suggest_reply" | "translate_en" | "action_plan";
  }): Promise<AiAssistResult> {
    return this.request<AiAssistResult>("/api/ai/assist", {
      method: "POST",
      body: JSON.stringify(payload),
    });
  }

  async listMiniApps(): Promise<MiniAppItem[]> {
    return this.request<MiniAppItem[]>("/api/mini-apps");
  }

  async adminOverview(): Promise<AdminOverview> {
    return this.request<AdminOverview>("/api/admin/overview");
  }

  async adminUsers(): Promise<UserProfile[]> {
    return this.request<UserProfile[]>("/api/admin/users");
  }

  async adminUpdateUserRole(userId: string, role: "admin" | "user"): Promise<UserProfile> {
    return this.request<UserProfile>(
      `/api/admin/users/${encodeURIComponent(userId)}/role`,
      {
        method: "PUT",
        body: JSON.stringify({ role }),
      }
    );
  }

  async adminMiniApps(): Promise<MiniAppItem[]> {
    return this.request<MiniAppItem[]>("/api/admin/mini-apps");
  }

  async adminCreateMiniApp(payload: Partial<MiniAppItem> & { title: string }): Promise<MiniAppItem> {
    return this.request<MiniAppItem>("/api/admin/mini-apps", {
      method: "POST",
      body: JSON.stringify(payload),
    });
  }

  async adminUpdateMiniApp(appId: string, payload: Partial<MiniAppItem>): Promise<MiniAppItem> {
    return this.request<MiniAppItem>(`/api/admin/mini-apps/${encodeURIComponent(appId)}`, {
      method: "PUT",
      body: JSON.stringify(payload),
    });
  }

  async adminDeleteMiniApp(appId: string): Promise<void> {
    await this.request(`/api/admin/mini-apps/${encodeURIComponent(appId)}`, {
      method: "DELETE",
    });
  }

  async adminGetAiSettings(): Promise<AiSettings> {
    return this.request<AiSettings>("/api/admin/ai-settings");
  }

  async adminUpdateAiSettings(payload: {
    enabled?: boolean;
    api_key?: string;
    clear_api_key?: boolean;
    model?: string;
    base_url?: string;
    system_prompt?: string;
    auto_reply_in_groups?: boolean;
    redact_confidential?: boolean;
  }): Promise<AiSettings> {
    return this.request<AiSettings>("/api/admin/ai-settings", {
      method: "PUT",
      body: JSON.stringify(payload),
    });
  }

  async adminBroadcast(title: string, content: string): Promise<{ sent_count: number }> {
    return this.request("/api/admin/broadcast", {
      method: "POST",
      body: JSON.stringify({ title, content }),
    });
  }
}

export const api = new ApiClient();

export function formatThaiTime(iso?: string | null): string {
  if (!iso) return "";
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return iso;
  const now = new Date();
  const sameDay =
    d.getFullYear() === now.getFullYear() &&
    d.getMonth() === now.getMonth() &&
    d.getDate() === now.getDate();
  const hh = String(d.getHours()).padStart(2, "0");
  const mm = String(d.getMinutes()).padStart(2, "0");
  if (sameDay) return `${hh}:${mm} น.`;
  const dd = String(d.getDate()).padStart(2, "0");
  const mo = String(d.getMonth() + 1).padStart(2, "0");
  return `${dd}/${mo} ${hh}:${mm}`;
}

export function formatFileSize(bytes: number): string {
  if (!bytes || bytes <= 0) return "0 B";
  if (bytes < 1024) return `${bytes} B`;
  const kb = bytes / 1024;
  if (kb < 1024) return `${kb.toFixed(1)} KB`;
  return `${(kb / 1024).toFixed(2)} MB`;
}
