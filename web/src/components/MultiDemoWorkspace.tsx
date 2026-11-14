"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import Link from "next/link";
import { ArrowLeft, Bot, RefreshCw, Send, Users } from "lucide-react";
import { ApiClient, formatThaiTime, getWsUrl } from "@/lib/api";
import {
  applyThemeCssVars,
  DEMO_ACCOUNTS,
  normalizeThemeId,
  type DemoAccountPreset,
} from "@/lib/themes";
import type { ChatMessage, Conversation, UserProfile, WsEvent } from "@/lib/types";
import { StickerArt, UserAvatar } from "./StickerArt";

interface DemoPaneState {
  account: DemoAccountPreset;
  client: ApiClient | null;
  user: UserProfile | null;
  conversations: Conversation[];
  activeConvId: string;
  messages: ChatMessage[];
  draft: string;
  status: string;
}

export function MultiDemoWorkspace() {
  const [panes, setPanes] = useState<DemoPaneState[]>(() =>
    DEMO_ACCOUNTS.map((account) => ({
      account,
      client: null,
      user: null,
      conversations: [],
      activeConvId: "conv_group_demo5",
      messages: [],
      draft: "",
      status: "กำลังเชื่อมต่อ...",
    }))
  );
  const socketsRef = useRef<Array<WebSocket | null>>([null, null, null, null, null]);

  const loadPaneMessages = useCallback(
    async (index: number, client: ApiClient, convId: string) => {
      if (!convId) return;
      try {
        const msgs = await client.listMessages(convId);
        await client.markRead(convId).catch(() => {});
        setPanes((prev) =>
          prev.map((p, i) => (i === index ? { ...p, messages: msgs } : p))
        );
      } catch {
        // Ignore transient fetch errors
      }
    },
    []
  );

  const bootAll = useCallback(async () => {
    try {
      const publicClient = new ApiClient("");
      const th = await publicClient.getTheme();
      applyThemeCssVars(normalizeThemeId(th.preset));
    } catch {
      applyThemeCssVars("ban_chiang");
    }

    await Promise.all(
      DEMO_ACCOUNTS.map(async (acc, idx) => {
        try {
          const authClient = new ApiClient("");
          const loginRes = await authClient.loginDemoOrEmail({
            email: acc.email,
            display_name: acc.name,
            department: acc.department,
          });
          const client = new ApiClient(loginRes.token);
          const convs = await client.listConversations("all");
          const defaultConv =
            convs.find((c) => c.id === "conv_group_demo5")?.id ||
            convs[0]?.id ||
            "";
          const msgs = defaultConv ? await client.listMessages(defaultConv) : [];

          setPanes((prev) =>
            prev.map((p, i) =>
              i === idx
                ? {
                    ...p,
                    client,
                    user: loginRes.user,
                    conversations: convs,
                    activeConvId: defaultConv,
                    messages: msgs,
                    status: "ออนไลน์",
                  }
                : p
            )
          );

          socketsRef.current[idx]?.close();
          const ws = new WebSocket(getWsUrl(loginRes.token, `multidemo_${idx + 1}`));
          socketsRef.current[idx] = ws;
          ws.onmessage = (ev) => {
            try {
              const payload = JSON.parse(String(ev.data)) as WsEvent;
              const evName = String(payload.event ?? payload.type ?? "");
              if (evName === "theme_changed" && payload.preset) {
                applyThemeCssVars(normalizeThemeId(String(payload.preset)));
              }
              if (evName && evName !== "connected" && evName !== "typing") {
                setPanes((current) => {
                  const targetConv = current[idx]?.activeConvId;
                  if (targetConv) {
                    void loadPaneMessages(idx, client, targetConv);
                  }
                  return current;
                });
              }
            } catch {
              // Ignore
            }
          };
        } catch (err) {
          setPanes((prev) =>
            prev.map((p, i) =>
              i === idx
                ? {
                    ...p,
                    status: err instanceof Error ? err.message : "เชื่อมต่อไม่สำเร็จ",
                  }
                : p
            )
          );
        }
      })
    );
  }, [loadPaneMessages]);

  useEffect(() => {
    void bootAll();
    return () => {
      socketsRef.current.forEach((ws) => ws?.close());
    };
  }, [bootAll]);

  const handleSend = async (idx: number) => {
    const pane = panes[idx];
    const text = pane.draft.trim();
    if (!pane.client || !pane.activeConvId || !text) return;

    setPanes((prev) =>
      prev.map((p, i) => (i === idx ? { ...p, draft: "" } : p))
    );
    try {
      await pane.client.sendMessage(pane.activeConvId, {
        type: "text",
        content: text,
      });
      await loadPaneMessages(idx, pane.client, pane.activeConvId);
    } catch {
      setPanes((prev) =>
        prev.map((p, i) => (i === idx ? { ...p, draft: text } : p))
      );
    }
  };

  const onlineCount = useMemo(
    () => panes.filter((p) => p.status === "ออนไลน์").length,
    [panes]
  );

  return (
    <div className="bc-spiral-bg flex min-h-screen flex-col">
      <header className="flex flex-wrap items-center justify-between gap-3 border-b border-[var(--bc-border)] bg-[var(--bc-card)] px-4 py-3 shadow-2xs">
        <div className="flex items-center gap-3">
          <Link
            href="/"
            className="inline-flex items-center gap-1.5 rounded-xl border border-[var(--bc-border)] bg-[var(--bc-panel)] px-3 py-1.5 text-xs font-bold text-[var(--bc-text)] hover:bg-[var(--bc-soft)]"
          >
            <ArrowLeft className="h-3.5 w-3.5" />
            <span>กลับหน้าหลัก</span>
          </Link>
          <div>
            <h1 className="text-base font-bold text-[var(--bc-text)] sm:text-lg">
              โหมดทดลองแชทแก๊งเพื่อน 5 จอพร้อมกัน (Multi-Demo Live)
            </h1>
            <p className="text-xs text-[var(--bc-muted)]">
              บัญชี Demo 1–5 เชื่อมต่อ WebSocket อิสระต่อกัน ({onlineCount}/5 ออนไลน์) • ทดลองคุยกลุ่มและเรียก @ai ได้ทันที
            </p>
          </div>
        </div>

        <button
          type="button"
          onClick={() => void bootAll()}
          className="inline-flex items-center gap-1.5 rounded-xl bg-[var(--bc-primary)] px-3.5 py-2 text-xs font-bold text-white"
        >
          <RefreshCw className="h-3.5 w-3.5" />
          <span>รีเฟรชทั้ง 5 จอ</span>
        </button>
      </header>

      <main className="grid flex-1 grid-cols-1 gap-3 p-3 md:grid-cols-2 lg:grid-cols-3 xl:grid-cols-5">
        {panes.map((pane, idx) => (
          <section
            key={pane.account.email}
            data-testid={`multi-demo-pane-${pane.account.slot}`}
            className="flex h-[540px] flex-col overflow-hidden rounded-2xl border border-[var(--bc-border)] bg-[var(--bc-card)] shadow-sm xl:h-[calc(100vh-96px)]"
          >
            {/* Pane Header */}
            <div
              style={{ backgroundColor: pane.account.badgeColor }}
              className="flex items-center justify-between gap-2 px-3 py-2 text-white"
            >
              <div className="min-w-0">
                <div className="truncate text-xs font-bold">{pane.account.name}</div>
                <div className="truncate text-[10px] opacity-90">
                  {pane.account.bcId} • {pane.status}
                </div>
              </div>
              <Users className="h-4 w-4 shrink-0 opacity-90" />
            </div>

            {/* Room Selector */}
            <div className="border-b border-[var(--bc-border)] bg-[var(--bc-panel)] p-2">
              <select
                value={pane.activeConvId}
                onChange={(e) => {
                  const cid = e.target.value;
                  setPanes((prev) =>
                    prev.map((p, i) => (i === idx ? { ...p, activeConvId: cid } : p))
                  );
                  if (pane.client) void loadPaneMessages(idx, pane.client, cid);
                }}
                className="w-full rounded-lg border border-[var(--bc-border)] bg-white px-2 py-1 text-xs font-semibold outline-none"
              >
                {pane.conversations.map((c) => (
                  <option key={c.id} value={c.id}>
                    {c.name}
                  </option>
                ))}
              </select>
            </div>

            {/* Messages */}
            <div className="bc-room-spiral-light flex-1 space-y-2 overflow-y-auto bg-[#F5EFEA] p-2.5">
              {pane.messages.slice(-25).map((m) => {
                const isMe = m.sender_id === pane.user?.id;
                const isAi = m.sender_id === "user_ai";
                return (
                  <div
                    key={m.id}
                    className={`flex flex-col ${isMe ? "items-end" : "items-start"}`}
                  >
                    {!isMe && (
                      <div className="mb-0.5 flex items-center gap-1 text-[10px] font-bold text-[var(--bc-primary)]">
                        <UserAvatar name={m.sender_name} size={18} isAi={isAi} />
                        <span>{m.sender_name}</span>
                      </div>
                    )}
                    <div
                      style={
                        isMe
                          ? {
                              backgroundColor: "var(--bc-bubble-sent)",
                              color: "var(--bc-bubble-sent-text)",
                            }
                          : isAi
                            ? { backgroundColor: "#EEF2FF", color: "#1E1B4B" }
                            : { backgroundColor: "#FFFFFF", color: "#1B1C1C" }
                      }
                      className="max-w-[90%] rounded-xl border border-[var(--bc-border)] px-2.5 py-1.5 text-xs shadow-2xs"
                    >
                      {m.type === "sticker" ? (
                        <StickerArt
                          code={m.sticker_code}
                          fallbackLabel={m.content}
                          size={76}
                        />
                      ) : (
                        <p className="whitespace-pre-wrap break-words">{m.content}</p>
                      )}
                    </div>
                    <span className="mt-0.5 text-[9px] text-[var(--bc-muted)]">
                      {formatThaiTime(m.created_at)}
                      {m.read_count > 0 ? ` • อ่าน ${m.read_count}` : ""}
                    </span>
                  </div>
                );
              })}
            </div>

            {/* Composer */}
            <form
              onSubmit={(e) => {
                e.preventDefault();
                void handleSend(idx);
              }}
              className="flex items-center gap-1.5 border-t border-[var(--bc-border)] bg-[var(--bc-card)] p-2"
            >
              <button
                type="button"
                title="เติม @ai"
                aria-label="เติม @ai"
                onClick={() =>
                  setPanes((prev) =>
                    prev.map((p, i) =>
                      i === idx
                        ? { ...p, draft: p.draft.startsWith("@ai ") ? p.draft : `@ai ${p.draft}` }
                        : p
                    )
                  )
                }
                className="inline-flex h-8 w-8 shrink-0 items-center justify-center rounded-lg border border-indigo-200 bg-indigo-50 text-indigo-700"
              >
                <Bot className="h-3.5 w-3.5" />
              </button>
              <input
                type="text"
                value={pane.draft}
                onChange={(e) =>
                  setPanes((prev) =>
                    prev.map((p, i) => (i === idx ? { ...p, draft: e.target.value } : p))
                  )
                }
                placeholder={`พิมพ์ในนาม Demo ${pane.account.slot}...`}
                className="h-8 min-w-0 flex-1 rounded-lg border border-[var(--bc-border)] bg-[var(--bc-surface)] px-2 text-xs outline-none focus:border-[var(--bc-primary)]"
              />
              <button
                type="submit"
                aria-label="ส่ง"
                title="ส่ง"
                className="inline-flex h-8 w-8 shrink-0 items-center justify-center rounded-lg bg-[var(--bc-primary)] text-white"
              >
                <Send className="h-3.5 w-3.5" />
              </button>
            </form>
          </section>
        ))}
      </main>
    </div>
  );
}
