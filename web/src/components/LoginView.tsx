"use client";

import { useState } from "react";
import Link from "next/link";
import {
  Bot,
  Columns,
  Heart,
  Lock,
  Mail,
  MessageSquareText,
  ShieldCheck,
  Sparkles,
  UserCheck,
} from "lucide-react";
import { ADMIN_DEMO_ACCOUNT, DEMO_ACCOUNTS, type DemoAccountPreset } from "@/lib/themes";

interface LoginViewProps {
  onLogin: (params: { email: string; display_name?: string; department?: string }) => Promise<void>;
  isLoading: boolean;
  errorMessage: string | null;
}

export function LoginView({ onLogin, isLoading, errorMessage }: LoginViewProps) {
  const [email, setEmail] = useState("demo1@bcaichat.local");
  const [displayName, setDisplayName] = useState("ก้อง (Demo 1)");

  const handleQuickDemo = async (acc: DemoAccountPreset) => {
    setEmail(acc.email);
    setDisplayName(acc.name);
    await onLogin({
      email: acc.email,
      display_name: acc.name,
      department: acc.department,
    });
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!email.trim()) return;
    await onLogin({
      email: email.trim(),
      display_name: displayName.trim() || undefined,
    });
  };

  return (
    <div className="bc-spiral-bg min-h-[100dvh] overflow-x-hidden px-2.5 py-2 sm:px-4 sm:py-4 lg:px-6">
      <div className="mx-auto max-w-6xl">
        {/* Top bar */}
        <header className="mb-2.5 flex flex-wrap items-center justify-between gap-2 rounded-2xl border border-[var(--bc-border)] bg-[var(--bc-card)]/95 px-3 py-1.5 shadow-sm backdrop-blur sm:mb-3.5 sm:px-4">
          <div className="flex min-w-0 items-center gap-3">
            <div
              className="flex h-8 w-8 shrink-0 items-center justify-center rounded-xl text-xs font-extrabold text-white shadow-sm sm:h-9 sm:w-9"
              style={{
                background: "linear-gradient(135deg, var(--bc-deep), var(--bc-primary))",
              }}
            >
              BC
            </div>
            <div className="min-w-0">
              <div className="flex flex-wrap items-center gap-1.5">
                <span className="text-base font-bold tracking-tight text-[var(--bc-text)] sm:text-lg">
                  BC Ai Chat
                </span>
                <span className="inline-flex items-center rounded-full bg-[var(--bc-soft)] px-2 py-0.5 text-[11px] font-semibold text-[var(--bc-primary)]">
                  ธีมบ้านเชียง
                </span>
              </div>
              <p className="truncate text-[11px] text-[var(--bc-muted)] sm:text-xs">
                แชทส่วนตัว ครอบครัว &amp; เพื่อนสนิท • ผู้ช่วย AI ส่วนตัว
              </p>
            </div>
          </div>

          <Link
            href="/multi-demo"
            data-testid="open-multi-demo-btn"
            className="inline-flex shrink-0 items-center gap-1.5 rounded-xl border border-[var(--bc-primary)] bg-[var(--bc-soft)] px-2.5 py-1.5 text-xs font-semibold text-[var(--bc-deep)] transition hover:brightness-95"
          >
            <Columns className="h-4 w-4 shrink-0" />
            <span>จอคุย 5 คน (/multi-demo)</span>
          </Link>
        </header>

        {/* Main Hero + Mobile-First Compact Login Grid */}
        <main className="flex flex-col gap-3 lg:grid lg:grid-cols-12 lg:items-start lg:gap-4">
          {/* Login Card (First on Mobile, Right on Desktop) */}
          <section className="order-1 mx-auto w-full max-w-md rounded-2xl border border-[var(--bc-border)] bg-[var(--bc-card)] p-3 shadow-md sm:p-4 lg:order-2 lg:col-span-5 lg:max-w-none">
            <div className="mb-2">
              <h2 className="text-base font-bold text-[var(--bc-text)] sm:text-lg">
                แชทส่วนตัว ครอบครัว &amp; เพื่อนสนิท + ผู้ช่วย AI ส่วนตัว
              </h2>
              <p className="mt-1 text-xs text-[var(--bc-muted)]">
                แตะ 1 ครั้งเพื่อเข้าใช้ทันทีด้วยบัญชี Demo 1–5 หรือ ลุงจืด
              </p>
            </div>

            {errorMessage && (
              <div
                role="alert"
                className="mb-3 rounded-xl border border-red-300 bg-red-50 px-3 py-2 text-xs font-medium text-red-800"
              >
                {errorMessage}
              </div>
            )}

            {/* 5 Personal Demo Accounts */}
            <div className="space-y-1">
              {DEMO_ACCOUNTS.map((acc) => (
                <button
                  key={acc.email}
                  type="button"
                  disabled={isLoading}
                  data-testid={`demo-login-${acc.slot}`}
                  onClick={() => handleQuickDemo(acc)}
                  className="flex w-full items-center justify-between gap-2 rounded-xl border border-[var(--bc-border)] bg-[var(--bc-panel)] px-2.5 py-1.5 text-left transition hover:border-[var(--bc-primary)] hover:bg-[var(--bc-soft)]/50 disabled:opacity-60"
                >
                  <div className="flex min-w-0 items-center gap-2.5">
                    <span
                      style={{ backgroundColor: acc.badgeColor }}
                      className="inline-flex h-7 w-7 shrink-0 items-center justify-center rounded-lg text-[11px] font-bold text-white"
                    >
                      D{acc.slot}
                    </span>
                    <div className="min-w-0">
                      <div className="truncate text-sm font-bold text-[var(--bc-text)]">
                        {acc.name}
                      </div>
                      <div className="truncate text-[11px] text-[var(--bc-muted)]">
                        {acc.department} • {acc.bcId}
                      </div>
                    </div>
                  </div>
                  <span className="inline-flex shrink-0 items-center rounded-lg bg-[var(--bc-card)] px-2.5 py-1 text-xs font-semibold text-[var(--bc-primary)] shadow-2xs">
                    เข้าใช้
                  </span>
                </button>
              ))}

              {/* Owner Jead */}
              <button
                type="button"
                disabled={isLoading}
                data-testid="demo-login-jead"
                onClick={() => handleQuickDemo(ADMIN_DEMO_ACCOUNT)}
                className="flex w-full items-center justify-between gap-2 rounded-xl border-2 border-[var(--bc-primary)]/40 bg-[var(--bc-soft)]/60 px-2.5 py-1.5 text-left transition hover:border-[var(--bc-primary)] hover:bg-[var(--bc-soft)] disabled:opacity-60"
              >
                <div className="flex min-w-0 items-center gap-2.5">
                  <span
                    style={{ backgroundColor: ADMIN_DEMO_ACCOUNT.badgeColor }}
                    className="inline-flex h-7 w-7 shrink-0 items-center justify-center rounded-lg text-white"
                  >
                    <UserCheck className="h-4 w-4" />
                  </span>
                  <div className="min-w-0">
                    <div className="truncate text-sm font-bold text-[var(--bc-deep)]">
                      {ADMIN_DEMO_ACCOUNT.name}
                    </div>
                    <div className="truncate text-[11px] text-[var(--bc-ochre)]">
                      {ADMIN_DEMO_ACCOUNT.department} (ตั้งค่าธีม 7 สี + AI) • {ADMIN_DEMO_ACCOUNT.bcId}
                    </div>
                  </div>
                </div>
                <span className="inline-flex shrink-0 items-center rounded-lg bg-[var(--bc-primary)] px-2.5 py-1 text-xs font-semibold text-white">
                  เจ้าของ
                </span>
              </button>
            </div>

            <div className="my-2 flex items-center gap-2">
              <div className="h-px flex-1 bg-[var(--bc-border)]" />
              <span className="text-[11px] font-medium text-[var(--bc-muted)]">
                หรือเข้าสู่ระบบด้วย Gmail / อีเมลส่วนตัว
              </span>
              <div className="h-px flex-1 bg-[var(--bc-border)]" />
            </div>

            <form onSubmit={handleSubmit} className="space-y-2">
              <div>
                <label className="mb-1 block text-xs font-semibold text-[var(--bc-text)]">
                  Gmail / อีเมลส่วนตัว
                </label>
                <div className="relative flex items-center">
                  <Mail className="pointer-events-none absolute left-3 h-4 w-4 text-[var(--bc-muted)]" />
                  <input
                    type="email"
                    required
                    value={email}
                    onChange={(e) => setEmail(e.target.value)}
                    placeholder="yourname@gmail.com"
                    className="w-full rounded-xl border border-[var(--bc-border)] bg-[var(--bc-surface)] py-1.5 pl-8 pr-2.5 text-xs text-[var(--bc-text)] outline-none focus:border-[var(--bc-primary)]"
                  />
                </div>
              </div>

              <div>
                <label className="mb-1 block text-xs font-semibold text-[var(--bc-text)]">
                  ชื่อที่แสดงในแชท (ไม่บังคับ)
                </label>
                <input
                  type="text"
                  value={displayName}
                  onChange={(e) => setDisplayName(e.target.value)}
                  placeholder="เช่น ก้อง หรือ น้องแพร"
                  className="w-full rounded-xl border border-[var(--bc-border)] bg-[var(--bc-surface)] px-2.5 py-1.5 text-xs text-[var(--bc-text)] outline-none focus:border-[var(--bc-primary)]"
                />
              </div>

              <button
                type="submit"
                disabled={isLoading}
                className="flex w-full items-center justify-center gap-2 rounded-xl px-3 py-2 text-xs font-bold text-white shadow-sm transition hover:brightness-95 disabled:opacity-60"
                style={{
                  background: "linear-gradient(135deg, var(--bc-deep), var(--bc-primary))",
                }}
              >
                <span>{isLoading ? "กำลังเข้าสู่ระบบ..." : "เข้าสู่ระบบ BC Ai Chat"}</span>
              </button>
            </form>
          </section>

          {/* Hero + FAQ (Second on Mobile, Left on Desktop) */}
          <section className="order-2 space-y-2.5 lg:order-1 lg:col-span-7">
            <div className="rounded-2xl border border-[var(--bc-border)] bg-[var(--bc-card)] p-3 shadow-sm sm:p-4">
              <div className="mb-3 inline-flex items-center gap-2 rounded-full border border-[var(--bc-border)] bg-[var(--bc-panel)] px-3 py-1 text-xs font-semibold text-[var(--bc-primary)]">
                <Sparkles className="h-3.5 w-3.5 shrink-0" />
                <span>ระบบแชทส่วนตัว ปลอดลิขสิทธิ์ 100%</span>
              </div>

              <h1 className="text-xl font-bold leading-snug text-[var(--bc-text)] sm:text-3xl">
                BC Ai Chat — แชทส่วนตัว ครอบครัว เพื่อนสนิท และผู้ช่วย AI ส่วนตัว
              </h1>
              <p className="mt-3 text-sm leading-relaxed text-[var(--bc-muted)] sm:text-base">
                ออกแบบด้วยลวดลายเส้นเกลียวคลื่นประยุกต์และโทนสีดินเผาบ้านเชียงร่วมสมัย
                ใช้งานลื่นไหลบนมือถือแบบไม่ต้องมี popup กวนใจ พร้อมผู้ช่วย{" "}
                <strong className="font-semibold text-[var(--bc-primary)]">@bc.ai</strong>{" "}
                อัลบั้มรูปถาวรไม่หมดอายุ โพลโหวต นัดเจอ RSVP โน้ตกลุ่ม และสมุดบันทึก BC ส่วนตัว
              </p>

              <div className="mt-2.5 grid grid-cols-1 gap-2 sm:grid-cols-2">
                <div className="flex items-start gap-2 rounded-xl border border-[var(--bc-border)] bg-[var(--bc-panel)] p-2.5">
                  <div className="flex h-7 w-7 shrink-0 items-center justify-center rounded-lg bg-[var(--bc-soft)] text-[var(--bc-primary)]">
                    <Bot className="h-5 w-5" />
                  </div>
                  <div>
                    <h2 className="text-sm font-bold text-[var(--bc-text)]">
                      ผู้ช่วย AI ประจำแชท
                    </h2>
                    <p className="mt-0.5 text-xs text-[var(--bc-muted)]">
                      พิมพ์ @ai ถามได้ทุกเรื่อง ช่วยคิดคำตอบ 3 แบบ เกลาให้น่ารัก และสรุปนัดหมายทันที
                    </p>
                  </div>
                </div>

                <div className="flex items-start gap-2 rounded-xl border border-[var(--bc-border)] bg-[var(--bc-panel)] p-2.5">
                  <div className="flex h-7 w-7 shrink-0 items-center justify-center rounded-lg bg-[var(--bc-soft)] text-[var(--bc-primary)]">
                    <Lock className="h-5 w-5" />
                  </div>
                  <div>
                    <h2 className="text-sm font-bold text-[var(--bc-text)]">
                      ข้อความลับ PIN 4 หลัก
                    </h2>
                    <p className="mt-0.5 text-xs text-[var(--bc-muted)]">
                      ล็อกข้อความส่วนตัว ลบเฉพาะฉัน ยกเลิกทุกคน หรือลบไฟล์จากคลังถาวร MinIO ได้ทันที
                    </p>
                  </div>
                </div>

                <div className="flex items-start gap-2 rounded-xl border border-[var(--bc-border)] bg-[var(--bc-panel)] p-2.5">
                  <div className="flex h-7 w-7 shrink-0 items-center justify-center rounded-lg bg-[var(--bc-soft)] text-[var(--bc-primary)]">
                    <Heart className="h-5 w-5" />
                  </div>
                  <div>
                    <h2 className="text-sm font-bold text-[var(--bc-text)]">
                      อัลบั้มถาวร &amp; ชวนเพื่อนง่าย
                    </h2>
                    <p className="mt-0.5 text-xs text-[var(--bc-muted)]">
                      โพลโหวตเลือกร้าน นัดเจอ RSVP อัลบั้มทริปไม่หมดอายุ โน้ตกลุ่ม และเรื่องด่วน
                    </p>
                  </div>
                </div>

                <div className="flex items-start gap-2 rounded-xl border border-[var(--bc-border)] bg-[var(--bc-panel)] p-2.5">
                  <div className="flex h-7 w-7 shrink-0 items-center justify-center rounded-lg bg-[var(--bc-soft)] text-[var(--bc-primary)]">
                    <ShieldCheck className="h-5 w-5" />
                  </div>
                  <div>
                    <h2 className="text-sm font-bold text-[var(--bc-text)]">
                      แยก Session อิสระต่อแท็บ
                    </h2>
                    <p className="mt-0.5 text-xs text-[var(--bc-muted)]">
                      เปิดหลายแท็บหรือหลายหน้าต่างเพื่อล็อกอินต่างบัญชีและทดลองคุยสดข้ามจอได้ทันที
                    </p>
                  </div>
                </div>
              </div>
            </div>

            {/* FAQ Section matching JSON-LD */}
            <div className="rounded-2xl border border-[var(--bc-border)] bg-[var(--bc-card)] p-3 shadow-sm sm:p-4">
              <h2 className="mb-3 flex items-center gap-2 text-base font-bold text-[var(--bc-text)]">
                <MessageSquareText className="h-4 w-4 text-[var(--bc-primary)]" />
                <span>คำถามที่พบบ่อย</span>
              </h2>
              <div className="space-y-1.5 text-xs text-[var(--bc-muted)]">
                <p>
                  <strong className="text-[var(--bc-text)]">ทดลองแชทกับแก๊งเพื่อน 5 คนพร้อมกันได้อย่างไร?</strong>{" "}
                  กดปุ่มบัญชี Demo 1–5 ในแต่ละแท็บเบราว์เซอร์ (ใช้{" "}
                  <code className="rounded bg-[var(--bc-panel)] px-1 py-0.5 text-[11px]">
                    ?demo=1..5
                  </code>
                  ) หรือเข้าหน้า{" "}
                  <Link href="/multi-demo" className="font-semibold text-[var(--bc-primary)] underline">
                    /multi-demo
                  </Link>{" "}
                  เพื่อเปิด 5 จอเรียงกันในหน้าเดียว
                </p>
                <p>
                  <strong className="text-[var(--bc-text)]">เรียกผู้ช่วยส่วนตัว BC AI ได้อย่างไร?</strong>{" "}
                  พิมพ์ <code className="rounded bg-[var(--bc-panel)] px-1 py-0.5 text-[11px]">@ai</code>{" "}
                  หรือ <code className="rounded bg-[var(--bc-panel)] px-1 py-0.5 text-[11px]">@bc.ai</code>{" "}
                  ในกลุ่มเพื่อน/ครอบครัว หรือแชท 1-1 กับ BC AI ได้ทันที
                </p>
              </div>
            </div>
          </section>
        </main>
      </div>
    </div>
  );
}
