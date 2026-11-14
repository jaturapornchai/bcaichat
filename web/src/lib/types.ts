export type ThemePresetId =
  | "ban_chiang"
  | "silk_amber"
  | "indigo_kram"
  | "jade_celadon"
  | "lotus_rose"
  | "spice_cinnamon"
  | "royal_amethyst";

export type RoomToneId = "ban_chiang_cream" | "terracotta_night" | "ivory_white";

export interface UserProfile {
  id: string;
  email: string;
  display_name: string;
  bc_id: string;
  avatar_url: string;
  status_message: string;
  qr_token: string;
  role: string;
  department: string;
  job_title: string;
  created_at?: string;
}

export interface FriendItem extends UserProfile {
  is_favorite: boolean;
  is_blocked: boolean;
  is_hidden: boolean;
}

export interface AttachmentInfo {
  key: string;
  url: string;
  file_name: string;
  mime_type: string;
  file_size: number;
}

export interface ReplyInfo {
  id: string;
  sender_name: string;
  content: string;
}

export interface PollOption {
  id: string;
  text: string;
  voter_ids: string[];
}

export interface PollData {
  question: string;
  options: PollOption[];
  allow_multiple: boolean;
  is_anonymous: boolean;
  is_closed: boolean;
  closed_at?: string | null;
}

export interface EventData {
  title: string;
  description: string;
  starts_at: string;
  ends_at?: string | null;
  location: string;
  going_ids: string[];
  maybe_ids: string[];
  not_going_ids: string[];
}

export interface RichCardPayload {
  app_code?: string;
  title?: string;
  color_hex?: string;
  heading?: string;
  subtitle?: string;
  highlight_value?: string;
  status?: string;
  status_label?: string;
  approved_by?: string;
  approved_at?: string;
  approval_comment?: string;
  action_url?: string;
  [key: string]: unknown;
}

export interface ChatMessage {
  id: string;
  conversation_id: string;
  sender_id: string;
  sender_name: string;
  sender_avatar: string;
  type: string;
  content: string;
  sticker_code?: string | null;
  attachment?: AttachmentInfo | null;
  card_payload?: RichCardPayload | null;
  reply_to?: ReplyInfo | null;
  read_by: string[];
  read_count: number;
  is_unsent: boolean;
  is_confidential: boolean;
  confidential_pin?: string | null;
  expire_at?: string | null;
  priority: string;
  task_status?: string | null;
  accepted_by?: string | null;
  accepted_at?: string | null;
  reactions: Record<string, string[]>;
  mentions: string[];
  audio_duration_sec?: number | null;
  poll?: PollData | null;
  event_data?: EventData | null;
  created_at: string;
}

export interface PinnedMessageSummary {
  id: string;
  sender_id: string;
  sender_name: string;
  type: string;
  content: string;
  created_at: string;
}

export interface LastMessageSummary {
  id: string;
  sender_id: string;
  sender_name: string;
  type: string;
  content: string;
  created_at: string;
  read_count: number;
}

export interface ConversationMember {
  id: string;
  email: string;
  display_name: string;
  bc_id: string;
  avatar_url: string;
  status_message: string;
  role: string;
  department: string;
  job_title: string;
}

export interface Conversation {
  id: string;
  type: string;
  name: string;
  avatar_url: string;
  folder: string;
  is_pinned: boolean;
  is_muted: boolean;
  is_archived: boolean;
  invite_token: string;
  admin_ids: string[];
  pinned_message?: PinnedMessageSummary | null;
  unread_count: number;
  member_count: number;
  members: ConversationMember[];
  last_message?: LastMessageSummary | null;
  created_at: string;
  updated_at: string;
}

export interface NoteComment {
  id: string;
  user_id: string;
  user_name: string;
  content: string;
  created_at: string;
}

export interface NoteItem {
  id: string;
  conversation_id?: string | null;
  owner_id: string;
  owner_name: string;
  title: string;
  content: string;
  attachments: AttachmentInfo[];
  is_pinned: boolean;
  liked_by: string[];
  comments: NoteComment[];
  created_at: string;
  updated_at: string;
}

export interface AlbumItem {
  id: string;
  conversation_id: string;
  title: string;
  description: string;
  photos: AttachmentInfo[];
  created_by: string;
  created_by_name: string;
  created_at: string;
  updated_at: string;
}

export interface VaultFileItem {
  id: string;
  message_id: string;
  sender_id: string;
  sender_name: string;
  key: string;
  url: string;
  file_name: string;
  mime_type: string;
  file_size: number;
  is_confidential: boolean;
  created_at: string;
}

export interface VaultLinkItem {
  id: string;
  message_id: string;
  sender_id: string;
  sender_name: string;
  url: string;
  content: string;
  created_at: string;
}

export interface VaultResponse {
  images: VaultFileItem[];
  files: VaultFileItem[];
  links: VaultLinkItem[];
}

export interface MiniAppItem {
  id: string;
  app_code: string;
  title: string;
  subtitle: string;
  category: string;
  icon_name: string;
  color_hex: string;
  entry_url: string;
  is_active: boolean;
  sort_order: number;
  created_at: string;
  updated_at: string;
}

export interface AdminOverview {
  total_users: number;
  total_conversations: number;
  total_messages: number;
  total_files: number;
  total_storage_bytes: number;
  total_mini_apps: number;
  recent_files: Array<{
    id: string;
    key: string;
    url: string;
    file_name: string;
    mime_type: string;
    file_size: number;
    uploader_name: string;
    created_at: string;
  }>;
}

export interface AiSettings {
  enabled: boolean;
  has_api_key: boolean;
  masked_key: string;
  model: string;
  base_url: string;
  system_prompt: string;
  auto_reply_in_groups: boolean;
  redact_confidential: boolean;
  updated_at: string;
}

export interface AiSummaryResult {
  conversation_id: string;
  conversation_name: string;
  summary: string;
  action_items: string[];
  decisions: string[];
  participants: string[];
  message_count: number;
  model: string;
  live_api: boolean;
}

export interface AiAssistResult {
  mode: string;
  result: string;
  suggestions: string[];
  model: string;
  live_api: boolean;
}

export interface WsEvent {
  event?: string;
  type?: string;
  conversation_id?: string;
  message_id?: string;
  user_id?: string;
  preset?: string;
  message?: Record<string, unknown>;
  [key: string]: unknown;
}
