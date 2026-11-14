import type { Metadata } from "next";
import { MultiDemoWorkspace } from "@/components/MultiDemoWorkspace";

export const metadata: Metadata = {
  title: "ทดสอบแชทแก๊งเพื่อน 5 บัญชี Demo พร้อมกัน",
  description:
    "หน้าจอจำลองห้องแชทแก๊งเพื่อน Demo 1–5 ใน BC Ai Chat เพื่อทดสอบส่งข้อความโต้ตอบแบบเรียลไทม์และเรียกผู้ช่วย AI ส่วนตัวข้ามผู้ใช้ในหน้าเดียว",
};

export default function MultiDemoPage() {
  return <MultiDemoWorkspace />;
}
