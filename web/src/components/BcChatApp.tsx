"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { useSearchParams } from "next/navigation";
import {
  api,
  clearTabSession,
  getSavedRoomTone,
  getTabToken,
  getTabUser,
  getWsUrl,
  saveRoomTone,
  setTabSession,
} from "@/lib/api";
import { playChime } from "@/lib/sound";
import {
  ADMIN_DEMO_ACCOUNT,
  applyThemeCssVars,
  DEMO_ACCOUNTS,
  normalizeThemeId,
} from "@/lib/themes";
import type { RoomToneId, ThemePresetId, UserProfile, WsEvent } from "@/lib/types";
import { LoginView } from "./LoginView";
import { MainShell } from "./MainShell";

export function BcChatApp() {
  const searchParams = useSearchParams();
  const [user, setUser] = useState<UserProfile | null>(null);
  const [booting, setBooting] = useState(true);
  const [loginLoading, setLoginLoading] = useState(false);
  const [loginError, setLoginError] = useState<string | null>(null);

  const [activeTheme, setActiveTheme] = useState<ThemePresetId>("ban_chiang");
  const [roomTone, setRoomTone] = useState<RoomToneId>("ban_chiang_cream");
  const [wsTick, setWsTick] = useState(0);
  const [lastWsConvId, setLastWsConvId] = useState<string | null>(null);

  const wsRef = useRef<WebSocket | null>(null);
  const userRef = useRef<UserProfile | null>(null);
  userRef.current = user;

  const applyAndSaveTheme = useCallback((rawPreset?: string | null) => {
    const id = normalizeThemeId(rawPreset);
    setActiveTheme(id);
    applyThemeCssVars(id);
  }, []);

  const performLogin = useCallback(
    async (params: { email: string; display_name?: string; department?: string }) => {
      setLoginLoading(true);
      setLoginError(null);
      try {
        const res = await api.loginDemoOrEmail(params);
        setTabSession(res.token, res.user);
        setUser(res.user);
      } catch (err) {
        setLoginError(
          err instanceof Error ? err.message : "ไม่สามารถเชื่อมต่อเซิร์ฟเวอร์ได้"
        );
      } finally {
        setLoginLoading(false);
      }
    },
    []
  );

  // Boot: apply theme + check URL query (?demo=1..5 / ?test_login=...) or sessionStorage
  useEffect(() => {
    let active = true;
    setRoomTone(getSavedRoomTone());
    applyAndSaveTheme("ban_chiang");

    const init = async () => {
      try {
        const themeRes = await api.getTheme();
        if (active) applyAndSaveTheme(themeRes.preset);
      } catch {
        // Keep default ban_chiang when backend is still booting
      }

      const demoParam = searchParams.get("demo");
      const testLoginParam = searchParams.get("test_login");

      if (demoParam) {
        const match =
          demoParam === "jead"
            ? ADMIN_DEMO_ACCOUNT
            : DEMO_ACCOUNTS.find((d) => d.slot === demoParam);
        if (match) {
          await performLogin({
            email: match.email,
            display_name: match.name,
            department: match.department,
          });
          if (active) setBooting(false);
          return;
        }
      }

      if (testLoginParam) {
        const foundDemo = DEMO_ACCOUNTS.find(
          (d) => d.email.toLowerCase() === testLoginParam.trim().toLowerCase()
        );
        await performLogin({
          email: testLoginParam.trim(),
          display_name: foundDemo?.name,
          department: foundDemo?.department,
        });
        if (active) setBooting(false);
        return;
      }

      const token = getTabToken();
      const savedUser = getTabUser();
      if (token && savedUser) {
        if (active) setUser(savedUser);
        try {
          const me = await api.getMe();
          if (active) {
            setTabSession(token, me);
            setUser(me);
          }
        } catch {
          clearTabSession();
          if (active) setUser(null);
        }
      }

      if (active) setBooting(false);
    };

    void init();
    return () => {
      active = false;
    };
  }, [applyAndSaveTheme, performLogin, searchParams]);

  // WebSocket lifecycle per tab session
  useEffect(() => {
    if (!user) {
      wsRef.current?.close();
      wsRef.current = null;
      return;
    }

    const token = getTabToken();
    if (!token) return;

    let cancelled = false;
    let reconnectTimer: ReturnType<typeof setTimeout> | null = null;
    const deviceId = `web_${user.id}`;

    const connect = () => {
      if (cancelled) return;
      const socket = new WebSocket(getWsUrl(token, deviceId));
      wsRef.current = socket;

      socket.onmessage = (ev) => {
        try {
          const payload = JSON.parse(String(ev.data)) as WsEvent;
          const evName = String(payload.event ?? payload.type ?? "");
          if (evName === "theme_changed" && payload.preset) {
            applyAndSaveTheme(String(payload.preset));
            return;
          }
          if (evName === "new_message" && payload.message) {
            const senderId = String(payload.message.sender_id ?? "");
            if (senderId && senderId !== userRef.current?.id) {
              playChime("incoming");
            }
          }
          if (evName && evName !== "connected" && evName !== "typing") {
            setLastWsConvId(payload.conversation_id ? String(payload.conversation_id) : null);
            setWsTick((t) => t + 1);
          }
        } catch {
          // Ignore malformed ws frames
        }
      };

      socket.onclose = () => {
        if (!cancelled) {
          reconnectTimer = setTimeout(connect, 2500);
        }
      };
    };

    connect();

    return () => {
      cancelled = true;
      if (reconnectTimer) clearTimeout(reconnectTimer);
      wsRef.current?.close();
      wsRef.current = null;
    };
  }, [user, applyAndSaveTheme]);

  const handleLogout = () => {
    clearTabSession();
    setUser(null);
  };

  const handleChangeRoomTone = (tone: RoomToneId) => {
    setRoomTone(tone);
    saveRoomTone(tone);
  };

  if (booting) {
    return (
      <div className="bc-spiral-bg flex min-h-screen items-center justify-center p-6">
        <div className="rounded-3xl border border-[var(--bc-border)] bg-[var(--bc-card)] px-8 py-6 text-center shadow-sm">
          <div
            className="mx-auto mb-3 flex h-12 w-12 items-center justify-center rounded-2xl font-extrabold text-white"
            style={{
              background: "linear-gradient(135deg, var(--bc-deep), var(--bc-primary))",
            }}
          >
            BC
          </div>
          <h1 className="text-base font-bold text-[var(--bc-text)]">BC Ai Chat</h1>
          <p className="mt-1 text-xs text-[var(--bc-muted)]">
            กำลังเตรียมห้องแชทและธีมบ้านเชียง...
          </p>
        </div>
      </div>
    );
  }

  if (!user) {
    return (
      <LoginView
        onLogin={performLogin}
        isLoading={loginLoading}
        errorMessage={loginError}
      />
    );
  }

  return (
    <MainShell
      currentUser={user}
      onUserUpdated={(updated) => {
        setUser(updated);
        const tok = getTabToken();
        if (tok) setTabSession(tok, updated);
      }}
      onLogout={handleLogout}
      activeTheme={activeTheme}
      onThemeUpdated={(p) => applyAndSaveTheme(p)}
      roomTone={roomTone}
      onChangeRoomTone={handleChangeRoomTone}
      wsTick={wsTick}
      lastWsConvId={lastWsConvId}
    />
  );
}
