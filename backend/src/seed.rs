use bson::{doc, Document, Regex};
use chrono::{Duration, Utc};
use futures_util::TryStreamExt;
use std::collections::HashMap;
use uuid::Uuid;

use crate::{
    models::{
        AlbumDoc, AttachmentInfo, ConversationDoc, EventData, FileDoc, FriendshipDoc,
        LastMessageSummary, MessageDoc, MiniAppDoc, NoteComment, NoteDoc, PinnedMessageSummary,
        PollData, PollOption, UserDoc,
    },
    routes::admin_routes::DEFAULT_THEME,
    AppState,
};

pub const DEMO_CHAT_ROOM_ID: &str = "conv_group_demo5";
pub const TEST_CHAT_ROOM_ID: &str = DEMO_CHAT_ROOM_ID;
pub const FAMILY_CHAT_ROOM_ID: &str = "conv_group_family";

/// 5 Personal Demo accounts: (id, email, display_name, bc_id, department, avatar_bg)
pub const DEMO_ACCOUNTS: [(&str, &str, &str, &str, &str, &str); 5] = [
    (
        "user_demo1",
        "demo1@bcaichat.local",
        "ก้อง (Demo 1)",
        "@kong.bc",
        "เพื่อนสนิท",
        "812920",
    ),
    (
        "user_demo2",
        "demo2@bcaichat.local",
        "แพร (Demo 2)",
        "@prae.bc",
        "เพื่อนสนิท",
        "B45309",
    ),
    (
        "user_demo3",
        "demo3@bcaichat.local",
        "บอส (Demo 3)",
        "@boss.bc",
        "ครอบครัว",
        "13795B",
    ),
    (
        "user_demo4",
        "demo4@bcaichat.local",
        "มายด์ (Demo 4)",
        "@mind.bc",
        "เพื่อนสนิท",
        "1E40AF",
    ),
    (
        "user_demo5",
        "demo5@bcaichat.local",
        "ต้น (Demo 5)",
        "@ton.bc",
        "ก๊วนกีฬา",
        "A04035",
    ),
];

const DEMO_PERSONA_DETAILS: [(&str, &str); 5] = [
    (
        "สายเที่ยว & ถ่ายรูป",
        "ว่างนัดเที่ยวและส่งรูปทริปความละเอียดเต็มได้เสมอ",
    ),
    (
        "สายคาเฟ่ & ชวนกินข้าว",
        "เจอคาเฟ่น่านั่งหรือร้านอร่อย ส่งพิกัดมาในแก๊งได้เลย!",
    ),
    (
        "สายแกดเจ็ต & เพลง",
        "แชร์เพลย์ลิสต์เพลงดีๆ และไอเดียแต่งมุมโปรดที่บ้าน",
    ),
    (
        "สายดูหนัง & ซีรีส์",
        "ป้ายยาหนังและซีรีส์น่าดูประจำสัปดาห์",
    ),
    (
        "สายวิ่ง & แคมป์ปิ้ง",
        "เช้าวิ่งสวน เย็นกางเต็นท์ ทักชวนออกทริปได้ตลอด",
    ),
];

pub const TEST_ACCOUNTS: [(&str, &str, &str); 5] = [
    ("user_demo1", "demo1@bcaichat.local", "ก้อง (Demo 1)"),
    ("user_demo2", "demo2@bcaichat.local", "แพร (Demo 2)"),
    ("user_demo3", "demo3@bcaichat.local", "บอส (Demo 3)"),
    ("user_demo4", "demo4@bcaichat.local", "มายด์ (Demo 4)"),
    ("user_demo5", "demo5@bcaichat.local", "ต้น (Demo 5)"),
];

pub async fn ensure_mongo_indexes(db: &mongodb::Database) {
    use mongodb::IndexModel;
    let _ = db
        .collection::<UserDoc>("users")
        .create_indexes(vec![
            IndexModel::builder().keys(doc! { "email": 1 }).build(),
            IndexModel::builder().keys(doc! { "bc_id": 1 }).build(),
            IndexModel::builder().keys(doc! { "qr_token": 1 }).build(),
        ])
        .await;
    let _ = db
        .collection::<ConversationDoc>("conversations")
        .create_indexes(vec![
            IndexModel::builder()
                .keys(doc! { "member_ids": 1, "is_pinned": -1, "updated_at": -1 })
                .build(),
            IndexModel::builder()
                .keys(doc! { "invite_token": 1 })
                .build(),
        ])
        .await;
    let _ = db
        .collection::<MessageDoc>("messages")
        .create_indexes(vec![
            IndexModel::builder()
                .keys(doc! { "conversation_id": 1, "created_at": 1 })
                .build(),
            IndexModel::builder()
                .keys(doc! { "conversation_id": 1, "is_unsent": 1, "sender_id": 1 })
                .build(),
            IndexModel::builder()
                .keys(doc! { "conversation_id": 1, "is_confidential": 1 })
                .build(),
            IndexModel::builder()
                .keys(doc! { "conversation_id": 1, "type": 1 })
                .build(),
        ])
        .await;
    let _ = db
        .collection::<bson::Document>("device_tokens")
        .create_index(IndexModel::builder().keys(doc! { "user_id": 1 }).build())
        .await;
    let _ = db
        .collection::<FriendshipDoc>("friendships")
        .create_index(
            IndexModel::builder()
                .keys(doc! { "user_id": 1, "friend_id": 1 })
                .build(),
        )
        .await;
    let _ = db
        .collection::<NoteDoc>("notes")
        .create_index(
            IndexModel::builder()
                .keys(doc! { "owner_id": 1, "conversation_id": 1, "is_pinned": -1 })
                .build(),
        )
        .await;
    let _ = db
        .collection::<AlbumDoc>("albums")
        .create_index(
            IndexModel::builder()
                .keys(doc! { "conversation_id": 1, "updated_at": -1 })
                .build(),
        )
        .await;
}

async fn upsert_seeded_user(
    users_coll: &mongodb::Collection<UserDoc>,
    user: &UserDoc,
) -> Result<(), String> {
    let existing = users_coll
        .find_one(doc! { "_id": &user.id })
        .await
        .map_err(|e| e.to_string())?;
    if existing.is_none() {
        users_coll
            .insert_one(user)
            .await
            .map_err(|e| e.to_string())?;
    } else {
        users_coll
            .update_one(
                doc! { "_id": &user.id },
                doc! {
                    "$set": {
                        "display_name": &user.display_name,
                        "bc_id": &user.bc_id,
                        "avatar_url": &user.avatar_url,
                        "status_message": &user.status_message,
                        "role": &user.role,
                        "department": &user.department,
                        "job_title": &user.job_title,
                    }
                },
            )
            .await
            .map_err(|e| e.to_string())?;
    }
    Ok(())
}

/// Cleans up legacy pre-personal seed docs in MongoDB & MinIO so live state is 100% personal.
async fn migrate_legacy_seed_data(state: &AppState) {
    let legacy_file_keys = [
        "seed_tax_invoice_preview.svg",
        "seed_quotation_QT2026_0089.txt",
    ];
    for key in legacy_file_keys {
        let _ = state.minio.delete_object(key).await;
    }

    let _ = state
        .db
        .collection::<Document>("files")
        .delete_many(doc! {
            "$or": [
                { "_id": { "$in": ["file_seed_invoice_img", "file_seed_quotation_doc"] } },
                { "key": { "$in": ["seed_tax_invoice_preview.svg", "seed_quotation_QT2026_0089.txt"] } },
                { "conversation_id": "conv_group_office" }
            ]
        })
        .await;

    let _ = state
        .db
        .collection::<Document>("conversations")
        .delete_one(doc! { "_id": "conv_group_office" })
        .await;

    let _ = state
        .db
        .collection::<Document>("messages")
        .delete_many(doc! { "conversation_id": "conv_group_office" })
        .await;

    let _ = state
        .db
        .collection::<Document>("notes")
        .delete_many(doc! {
            "$or": [
                { "conversation_id": "conv_group_office" },
                { "_id": "note_group_office_1" }
            ]
        })
        .await;

    let _ = state
        .db
        .collection::<Document>("albums")
        .delete_many(doc! {
            "$or": [
                { "conversation_id": "conv_group_office" },
                { "_id": "album_office_seed_1" }
            ]
        })
        .await;

    let _ = state
        .db
        .collection::<Document>("mini_apps")
        .delete_many(doc! {
            "$or": [
                { "app_code": { "$in": ["ai_copilot", "leave_approval", "quick_quotation", "expense_claim", "crm_queue"] } },
                { "_id": { "$in": ["mini_ai_copilot", "mini_leave", "mini_quotation", "mini_expense", "mini_booking"] } }
            ]
        })
        .await;

    // Match legacy seeded text & denormalized business persona patterns via unicode escapes
    let legacy_rx = Regex {
        pattern: concat!(
            "0105566099887|INV-2026-08914|QT-2026-0089|",
            "\u{0e1d}\u{0e48}\u{0e32}\u{0e22}\u{0e02}\u{0e32}\u{0e22}|",
            "\u{0e1a}\u{0e31}\u{0e0d}\u{0e0a}\u{0e35}\u{0e01}\u{0e32}\u{0e23}\u{0e40}\u{0e07}\u{0e34}\u{0e19}|",
            "\u{0e1a}\u{0e31}\u{0e0d}\u{0e0a}\u{0e35}\u{0e41}\u{0e25}\u{0e30}\u{0e01}\u{0e32}\u{0e23}\u{0e40}\u{0e07}\u{0e34}\u{0e19}|",
            "\u{0e04}\u{0e25}\u{0e31}\u{0e07}\u{0e2a}\u{0e34}\u{0e19}\u{0e04}\u{0e49}\u{0e32}|",
            "\u{0e14}\u{0e39}\u{0e41}\u{0e25}\u{0e25}\u{0e39}\u{0e01}\u{0e04}\u{0e49}\u{0e32}|",
            "\u{0e1a}\u{0e23}\u{0e34}\u{0e01}\u{0e32}\u{0e23}\u{0e25}\u{0e39}\u{0e01}\u{0e04}\u{0e49}\u{0e32}|",
            "\u{0e08}\u{0e31}\u{0e14}\u{0e0b}\u{0e37}\u{0e49}\u{0e2d}|",
            "\u{0e43}\u{0e1a}\u{0e40}\u{0e2a}\u{0e19}\u{0e2d}\u{0e23}\u{0e32}\u{0e04}\u{0e32}|",
            "\u{0e43}\u{0e1a}\u{0e01}\u{0e33}\u{0e01}\u{0e31}\u{0e1a}\u{0e20}\u{0e32}\u{0e29}\u{0e35}|",
            "\u{0e2d}\u{0e19}\u{0e38}\u{0e21}\u{0e31}\u{0e15}\u{0e34}\u{0e43}\u{0e1a}\u{0e25}\u{0e32}|",
            "\u{0e42}\u{0e2d}\u{0e19}\u{0e22}\u{0e49}\u{0e32}\u{0e22}\u{0e07}\u{0e32}\u{0e19}|",
            "\u{0e2d}\u{0e07}\u{0e04}\u{0e4c}\u{0e01}\u{0e23}|",
            "\u{0e40}\u{0e23}\u{0e37}\u{0e48}\u{0e2d}\u{0e07}\u{0e07}\u{0e32}\u{0e19}|",
            "\u{0e07}\u{0e32}\u{0e19}\u{0e14}\u{0e48}\u{0e27}\u{0e19}|",
            "\u{0e1b}\u{0e23}\u{0e30}\u{0e01}\u{0e32}\u{0e28}\u{0e17}\u{0e32}\u{0e07}\u{0e01}\u{0e32}\u{0e23}|",
            "\u{0e1c}\u{0e39}\u{0e49}\u{0e14}\u{0e39}\u{0e41}\u{0e25}\u{0e2a}\u{0e39}\u{0e07}\u{0e2a}\u{0e38}\u{0e14}|",
            "\u{0e1c}\u{0e39}\u{0e49}\u{0e0a}\u{0e48}\u{0e27}\u{0e22}\u{0e2d}\u{0e31}\u{0e08}\u{0e09}\u{0e23}\u{0e34}\u{0e22}\u{0e30}|",
            "\u{0e18}\u{0e38}\u{0e23}\u{0e01}\u{0e34}\u{0e08}|",
            "\u{0e1e}\u{0e19}\u{0e31}\u{0e01}\u{0e07}\u{0e32}\u{0e19}"
        )
        .to_string(),
        options: "i".to_string(),
    };

    let files_doc_coll = state.db.collection::<Document>("files");
    if let Ok(f_cursor) = files_doc_coll
        .find(doc! {
            "$or": [
                { "uploader_name": legacy_rx.clone() },
                { "file_name": legacy_rx.clone() }
            ]
        })
        .await
    {
        if let Ok(stale_files) = f_cursor.try_collect::<Vec<Document>>().await {
            for fd in &stale_files {
                if let Ok(k) = fd.get_str("key") {
                    let _ = state.minio.delete_object(k).await;
                }
            }
        }
    }
    let _ = files_doc_coll
        .delete_many(doc! {
            "$or": [
                { "uploader_name": legacy_rx.clone() },
                { "file_name": legacy_rx.clone() }
            ]
        })
        .await;

    let _ = state
        .db
        .collection::<Document>("notes")
        .delete_many(doc! {
            "$or": [
                { "title": legacy_rx.clone() },
                { "content": legacy_rx.clone() },
                { "owner_name": legacy_rx.clone() },
                { "comments.user_name": legacy_rx.clone() },
                { "comments.content": legacy_rx.clone() }
            ]
        })
        .await;

    let _ = state
        .db
        .collection::<Document>("albums")
        .delete_many(doc! {
            "$or": [
                { "title": legacy_rx.clone() },
                { "description": legacy_rx.clone() },
                { "created_by_name": legacy_rx.clone() }
            ]
        })
        .await;

    // Remove legacy starter direct/official chats & stale non-seeded work groups so personal onboarding recreates clean ones
    let conv_docs_coll = state.db.collection::<Document>("conversations");
    if let Ok(cursor) = conv_docs_coll
        .find(doc! {
            "_id": { "$nin": [DEMO_CHAT_ROOM_ID, FAMILY_CHAT_ROOM_ID] },
            "$or": [
                { "folder": "work" },
                { "name": legacy_rx.clone() },
                { "last_message.content": legacy_rx.clone() },
                { "last_message.sender_name": legacy_rx.clone() },
                { "pinned_message.content": legacy_rx.clone() },
                { "pinned_message.sender_name": legacy_rx.clone() }
            ]
        })
        .await
    {
        if let Ok(stale_convs) = cursor.try_collect::<Vec<Document>>().await {
            let stale_ids: Vec<String> = stale_convs
                .into_iter()
                .filter_map(|d| d.get_str("_id").ok().map(str::to_string))
                .collect();
            if !stale_ids.is_empty() {
                let _ = state
                    .db
                    .collection::<Document>("messages")
                    .delete_many(doc! { "conversation_id": { "$in": &stale_ids } })
                    .await;
                let _ = conv_docs_coll
                    .delete_many(doc! { "_id": { "$in": &stale_ids } })
                    .await;
            }
        }
    }

    let _ = state
        .db
        .collection::<Document>("messages")
        .delete_many(doc! {
            "$or": [
                { "content": legacy_rx.clone() },
                { "sender_name": legacy_rx.clone() },
                { "accepted_by": legacy_rx.clone() },
                { "card_payload.title": legacy_rx.clone() },
                { "flex_payload.title": legacy_rx }
            ]
        })
        .await;

    // Upgrade any non-seeded user records still carrying old default department/job_title
    let _ = state
        .db
        .collection::<Document>("users")
        .update_many(
            doc! { "department": { "$in": ["\u{0e1a}\u{0e23}\u{0e34}\u{0e2b}\u{0e32}\u{0e23}", "\u{0e17}\u{0e31}\u{0e48}\u{0e27}\u{0e44}\u{0e1b}", ""] } },
            doc! { "$set": { "department": "เพื่อน" } },
        )
        .await;
    let _ = state
        .db
        .collection::<Document>("users")
        .update_many(
            doc! { "job_title": { "$in": ["\u{0e1e}\u{0e19}\u{0e31}\u{0e01}\u{0e07}\u{0e32}\u{0e19}", "\u{0e1e}\u{0e19}\u{0e31}\u{0e01}\u{0e07}\u{0e32}\u{0e19}\u{0e2d}\u{0e07}\u{0e04}\u{0e4c}\u{0e01}\u{0e23}", ""] } },
            doc! { "$set": { "job_title": "เพื่อน" } },
        )
        .await;

    // Ensure AI settings default prompt is upgraded if legacy
    let _ = crate::routes::ai_routes::get_effective_ai_settings(state).await;
}

pub async fn seed_initial_data(state: &AppState) -> Result<(), String> {
    ensure_mongo_indexes(&state.db).await;

    if let Err(e) = state.minio.ensure_bucket().await {
        tracing::warn!("MinIO bucket ensure warning: {}", e);
    }

    migrate_legacy_seed_data(state).await;

    let now = Utc::now().to_rfc3339();

    // Ensure default Ban Chiang theme in app_settings if not already configured
    let settings_coll = state.db.collection::<Document>("app_settings");
    if settings_coll
        .find_one(doc! { "_id": "theme" })
        .await
        .map_err(|e| e.to_string())?
        .is_none()
    {
        let _ = settings_coll
            .insert_one(doc! {
                "_id": "theme",
                "preset": DEFAULT_THEME,
                "updated_by": "user_jead",
                "updated_at": &now,
            })
            .await;
    }

    let users_coll = state.db.collection::<UserDoc>("users");

    let initial_users = vec![
        UserDoc {
            id: "user_jead".to_string(),
            email: "jead@bcaichat.local".to_string(),
            display_name: "ลุงจืด".to_string(),
            bc_id: "jead.bc".to_string(),
            avatar_url: "https://ui-avatars.com/api/?name=Lung+Jead&background=812920&color=fff&bold=true".to_string(),
            status_message: "พื้นที่แชทส่วนตัวของครอบครัวและแก๊งเพื่อน เก็บรูปถาวร".to_string(),
            qr_token: "BCQR_JEAD_ADMIN".to_string(),
            role: "admin".to_string(),
            department: "เจ้าของระบบ".to_string(),
            job_title: "ผู้ดูแลระบบส่วนตัว".to_string(),
            google_id: None,
            created_at: now.clone(),
        },
        UserDoc {
            id: "user_somchai".to_string(),
            email: "somchai@bcaichat.local".to_string(),
            display_name: "สมชาย เพื่อนบ้าน".to_string(),
            bc_id: "somchai.s".to_string(),
            avatar_url: "https://ui-avatars.com/api/?name=Somchai&background=B45309&color=fff&bold=true".to_string(),
            status_message: "มีของอร่อยหน้าปากซอยหรือฝากรับพัสดุทักแชทบอกได้เลยครับ".to_string(),
            qr_token: "BCQR_SOMCHAI_HOME".to_string(),
            role: "user".to_string(),
            department: "เพื่อนบ้าน".to_string(),
            job_title: "เพื่อนสนิทประจำซอย".to_string(),
            google_id: None,
            created_at: now.clone(),
        },
        UserDoc {
            id: "user_nida".to_string(),
            email: "nida@bcaichat.local".to_string(),
            display_name: "นิดา พี่สาว".to_string(),
            bc_id: "nida.acc".to_string(),
            avatar_url: "https://ui-avatars.com/api/?name=Nida&background=13795B&color=fff&bold=true".to_string(),
            status_message: "ส่งรูปครอบครัวและสูตรอาหารเก็บถาวรในคลัง ไม่มีวันหมดอายุค่ะ".to_string(),
            qr_token: "BCQR_NIDA_FAM".to_string(),
            role: "user".to_string(),
            department: "ครอบครัว".to_string(),
            job_title: "พี่สาวคนโต".to_string(),
            google_id: None,
            created_at: now.clone(),
        },
        UserDoc {
            id: "user_official".to_string(),
            email: "official@bcaichat.local".to_string(),
            display_name: "ข่าวสาร BC Ai Chat".to_string(),
            bc_id: "@bc.official".to_string(),
            avatar_url: "https://ui-avatars.com/api/?name=BC+News&background=A04035&color=fff&bold=true".to_string(),
            status_message: "อัปเดตฟีเจอร์ใหม่สำหรับแชทส่วนตัว ครอบครัว และแก๊งเพื่อน".to_string(),
            qr_token: "BCQR_OFFICIAL_BC".to_string(),
            role: "admin".to_string(),
            department: "ข่าวสารแอป".to_string(),
            job_title: "อัปเดตฟีเจอร์ส่วนตัว".to_string(),
            google_id: None,
            created_at: now.clone(),
        },
        UserDoc {
            id: "user_ai".to_string(),
            email: "ai@bcaichat.local".to_string(),
            display_name: "🤖 BC AI ผู้ช่วยส่วนตัว".to_string(),
            bc_id: "@bc.ai".to_string(),
            avatar_url: "https://ui-avatars.com/api/?name=BC+AI&background=1E40AF&color=fff&bold=true".to_string(),
            status_message: "ผู้ช่วย AI ส่วนตัวสำหรับทุกคนและทุกกลุ่ม (เรียก @ai ได้ทุกห้อง)".to_string(),
            qr_token: "BCQR_DEEPSEEK_AI".to_string(),
            role: "admin".to_string(),
            department: "AI ส่วนตัว".to_string(),
            job_title: "เพื่อนคู่คิด & ผู้ช่วยประจำแชท".to_string(),
            google_id: None,
            created_at: now.clone(),
        },
    ];

    for u in &initial_users {
        upsert_seeded_user(&users_coll, u).await?;
    }

    // Seed permanent personal files into MinIO + files collection (Ban Chiang palette, zero banned colors)
    let files_coll = state.db.collection::<FileDoc>("files");
    let sample_img_key = "seed_trip_postcard.svg";
    let sample_img_url = format!("{}/api/files/{}", state.config.public_base_url, sample_img_key);
    let svg_bytes = r##"<svg xmlns="http://www.w3.org/2000/svg" width="600" height="360" viewBox="0 0 600 360">
  <rect width="600" height="360" rx="16" fill="#FBF9F8"/>
  <rect x="20" y="20" width="560" height="70" rx="12" fill="#812920"/>
  <text x="45" y="63" fill="#FFFFFF" font-family="sans-serif" font-size="23" font-weight="bold">BC AI CHAT - โปสการ์ดทริปเขาใหญ่สุดสัปดาห์</text>
  <text x="45" y="130" fill="#1B1C1C" font-family="sans-serif" font-size="18">ความทรงจำดีๆ กับครอบครัวและแก๊งเพื่อน (เก็บถาวรบน MinIO)</text>
  <text x="45" y="168" fill="#615E53" font-family="sans-serif" font-size="16">พิกัด: จุดชมวิวผาเดียวดาย • คาเฟ่กลางหุบเขา • ลานกางเต็นท์ดูดาว</text>
  <text x="45" y="206" fill="#615E53" font-family="sans-serif" font-size="16">อัลบั้มภาพความละเอียดเต็ม เปิดดูย้อนหลังได้ตลอด ไม่มีวันหมดอายุ</text>
  <rect x="45" y="240" width="510" height="75" rx="10" fill="#FADBD4"/>
  <text x="65" y="285" fill="#681F18" font-family="sans-serif" font-size="22" font-weight="bold">ทริปเสาร์-อาทิตย์ • งบหารเฉลี่ยคนละ 1,250 บาท</text>
</svg>"##
        .as_bytes();

    let sample_img_attachment = AttachmentInfo {
        key: sample_img_key.to_string(),
        url: sample_img_url.clone(),
        file_name: "โปสการ์ดทริปเขาใหญ่_Weekend.svg".to_string(),
        mime_type: "image/svg+xml".to_string(),
        file_size: svg_bytes.len() as u64,
    };

    let _ = state
        .minio
        .put_object(sample_img_key, svg_bytes, "image/svg+xml")
        .await;
    let img_fdoc = FileDoc {
        id: "file_seed_trip_img".to_string(),
        key: sample_img_key.to_string(),
        url: sample_img_url.clone(),
        file_name: "โปสการ์ดทริปเขาใหญ่_Weekend.svg".to_string(),
        mime_type: "image/svg+xml".to_string(),
        file_size: svg_bytes.len() as u64,
        uploader_id: "user_nida".to_string(),
        uploader_name: "นิดา พี่สาว".to_string(),
        conversation_id: Some(FAMILY_CHAT_ROOM_ID.to_string()),
        created_at: now.clone(),
    };
    let _ = files_coll
        .replace_one(doc! { "_id": "file_seed_trip_img" }, &img_fdoc)
        .upsert(true)
        .await;

    let sample_doc_key = "seed_weekend_trip.txt";
    let sample_doc_url = format!("{}/api/files/{}", state.config.public_base_url, sample_doc_key);
    let doc_bytes = "แผนทริปพักผ่อนสุดสัปดาห์ เขาใหญ่ - ปากช่อง\nผู้ร่วมทริป: ครอบครัวและแก๊งเพื่อนสนิท\nรายการกิจกรรม: แวะจิบกาแฟคาเฟ่โฮมมี่ • ชมวิวพระอาทิตย์ตก • ปิ้งย่างยามเย็น\nงบหารเฉลี่ย: คนละ 1,250 บาท\nหมายเหตุ: ไฟล์และรูปถ่ายทริปนี้จัดเก็บถาวรใน MinIO Object Storage ไม่มีวันหมดอายุ\n".as_bytes();

    let _ = state
        .minio
        .put_object(sample_doc_key, doc_bytes, "text/plain; charset=utf-8")
        .await;
    let txt_fdoc = FileDoc {
        id: "file_seed_trip_doc".to_string(),
        key: sample_doc_key.to_string(),
        url: sample_doc_url.clone(),
        file_name: "แผนเที่ยววันหยุดสุดสัปดาห์_เขาใหญ่.txt".to_string(),
        mime_type: "text/plain".to_string(),
        file_size: doc_bytes.len() as u64,
        uploader_id: "user_somchai".to_string(),
        uploader_name: "สมชาย เพื่อนบ้าน".to_string(),
        conversation_id: Some(FAMILY_CHAT_ROOM_ID.to_string()),
        created_at: now.clone(),
    };
    let _ = files_coll
        .replace_one(doc! { "_id": "file_seed_trip_doc" }, &txt_fdoc)
        .upsert(true)
        .await;

    // Seed 5 Personal Mini-Apps (Ban Chiang palette)
    let mini_coll = state.db.collection::<MiniAppDoc>("mini_apps");
    let base_url = &state.config.public_base_url;
    let initial_mini_apps = vec![
        MiniAppDoc {
            id: "mini_ai_companion".to_string(),
            app_code: "ai_companion".to_string(),
            title: "ผู้ช่วย AI ส่วนตัว".to_string(),
            subtitle: "ช่วยคิดแผนเที่ยว สรุปแชทกลุ่ม เกลาข้อความ และตั้งเตือนนัดหมาย".to_string(),
            category: "ai".to_string(),
            icon_name: "auto_awesome".to_string(),
            color_hex: "#812920".to_string(),
            entry_url: format!("{}/miniapp/ai", base_url),
            is_active: true,
            sort_order: 0,
            created_at: now.clone(),
            updated_at: now.clone(),
        },
        MiniAppDoc {
            id: "mini_split_bill".to_string(),
            app_code: "split_bill".to_string(),
            title: "หารค่าข้าวกับเพื่อน".to_string(),
            subtitle: "คำนวณหารมื้ออร่อยกับแก๊งเพื่อน แล้วส่งการ์ดสรุปยอดเข้าแชททันที".to_string(),
            category: "lifestyle".to_string(),
            icon_name: "payments".to_string(),
            color_hex: "#A04035".to_string(),
            entry_url: format!("{}/miniapp/split", base_url),
            is_active: true,
            sort_order: 1,
            created_at: now.clone(),
            updated_at: now.clone(),
        },
        MiniAppDoc {
            id: "mini_trip_planner".to_string(),
            app_code: "trip_planner".to_string(),
            title: "จัดทริปเที่ยว".to_string(),
            subtitle: "วางแผนจุดแวะเที่ยว ที่พัก และงบทริปแชร์ให้ทุกคนในกลุ่ม".to_string(),
            category: "travel".to_string(),
            icon_name: "explore".to_string(),
            color_hex: "#B45309".to_string(),
            entry_url: format!("{}/miniapp/trip", base_url),
            is_active: true,
            sort_order: 2,
            created_at: now.clone(),
            updated_at: now.clone(),
        },
        MiniAppDoc {
            id: "mini_gift_wishlist".to_string(),
            app_code: "gift_wishlist".to_string(),
            title: "ลิสต์ของฝาก / ช้อปปิ้ง".to_string(),
            subtitle: "จดรายการของฝากและของเข้าบ้าน แชร์ให้ครอบครัวช่วยกันเช็ก".to_string(),
            category: "lifestyle".to_string(),
            icon_name: "redeem".to_string(),
            color_hex: "#13795B".to_string(),
            entry_url: format!("{}/miniapp/wishlist", base_url),
            is_active: true,
            sort_order: 3,
            created_at: now.clone(),
            updated_at: now.clone(),
        },
        MiniAppDoc {
            id: "mini_hangout_invite".to_string(),
            app_code: "hangout_invite".to_string(),
            title: "การ์ดชวนนัดเจอ".to_string(),
            subtitle: "ส่งการ์ดชวนกินข้าว ดูหนัง หรือสังสรรค์วันหยุดให้เพื่อนกดตอบรับ".to_string(),
            category: "social".to_string(),
            icon_name: "celebration".to_string(),
            color_hex: "#1E40AF".to_string(),
            entry_url: format!("{}/miniapp/hangout", base_url),
            is_active: true,
            sort_order: 4,
            created_at: now.clone(),
            updated_at: now.clone(),
        },
    ];

    for app in initial_mini_apps {
        mini_coll
            .replace_one(doc! { "_id": &app.id }, &app)
            .upsert(true)
            .await
            .map_err(|e| e.to_string())?;
    }

    // Seed family & neighbors group conversation ("กลุ่มครอบครัว & เพื่อนบ้าน")
    let conv_coll = state.db.collection::<ConversationDoc>("conversations");
    let msg_coll = state.db.collection::<MessageDoc>("messages");

    let family_pinned_msg = PinnedMessageSummary {
        id: "msg_group_welcome_1".to_string(),
        sender_id: "user_jead".to_string(),
        sender_name: "ลุงจืด".to_string(),
        msg_type: "text".to_string(),
        content: "📌 ยินดีต้อนรับสู่กลุ่มครอบครัว & เพื่อนบ้าน: รูปถ่ายและไฟล์ในห้องนี้เก็บถาวรบน MinIO ไม่มีวันหมดอายุ และรองรับข้อความลับส่วนตัวล็อก PIN (ส่งผิดกดยกเลิกหรือลบทำลายไฟล์ออกจากเซิร์ฟเวอร์ได้ทันที)".to_string(),
        created_at: now.clone(),
    };

    let family_last_msg = LastMessageSummary {
        id: "msg_group_welcome_3".to_string(),
        sender_id: "user_somchai".to_string(),
        sender_name: "สมชาย เพื่อนบ้าน".to_string(),
        msg_type: "file".to_string(),
        content: "แนบไฟล์: แผนเที่ยววันหยุดสุดสัปดาห์_เขาใหญ่.txt (ดูได้ที่คลังไฟล์ หรือลิงก์ https://bcaichat.local/trips/weekend)".to_string(),
        created_at: now.clone(),
        read_count: 3,
    };

    if conv_coll
        .find_one(doc! { "_id": FAMILY_CHAT_ROOM_ID })
        .await
        .map_err(|e| e.to_string())?
        .is_none()
    {
        let group_conv = ConversationDoc {
            id: FAMILY_CHAT_ROOM_ID.to_string(),
            conv_type: "group".to_string(),
            name: "กลุ่มครอบครัว & เพื่อนบ้าน".to_string(),
            avatar_url: "https://ui-avatars.com/api/?name=BC+Family&background=812920&color=fff&bold=true".to_string(),
            folder: "family".to_string(),
            is_pinned: true,
            is_muted: false,
            is_archived: false,
            invite_token: "BCJOIN-FAMILY".to_string(),
            admin_ids: vec!["user_jead".to_string()],
            member_ids: vec![
                "user_jead".to_string(),
                "user_somchai".to_string(),
                "user_nida".to_string(),
                "user_official".to_string(),
                "user_ai".to_string(),
            ],
            user_meta: HashMap::new(),
            pinned_message: Some(family_pinned_msg.clone()),
            last_message: Some(family_last_msg),
            created_at: now.clone(),
            updated_at: now.clone(),
        };
        conv_coll
            .insert_one(group_conv)
            .await
            .map_err(|e| e.to_string())?;
    } else {
        let _ = conv_coll
            .update_one(
                doc! { "_id": FAMILY_CHAT_ROOM_ID },
                doc! {
                    "$set": {
                        "name": "กลุ่มครอบครัว & เพื่อนบ้าน",
                        "folder": "family",
                        "avatar_url": "https://ui-avatars.com/api/?name=BC+Family&background=812920&color=fff&bold=true",
                        "invite_token": "BCJOIN-FAMILY",
                    },
                    "$addToSet": {
                        "member_ids": {
                            "$each": ["user_jead", "user_somchai", "user_nida", "user_official", "user_ai"]
                        }
                    }
                },
            )
            .await;
    }

    let family_seed_messages = vec![
        MessageDoc {
            id: "msg_group_welcome_1".to_string(),
            conversation_id: FAMILY_CHAT_ROOM_ID.to_string(),
            sender_id: "user_jead".to_string(),
            sender_name: "ลุงจืด".to_string(),
            sender_avatar: "https://ui-avatars.com/api/?name=Lung+Jead&background=812920&color=fff&bold=true".to_string(),
            msg_type: "text".to_string(),
            content: family_pinned_msg.content.clone(),
            sticker_code: None,
            attachment: None,
            card_payload: None,
            flex_payload: None,
            reply_to: None,
            read_by: vec![
                "user_jead".to_string(),
                "user_somchai".to_string(),
                "user_nida".to_string(),
                "user_official".to_string(),
            ],
            is_unsent: false,
            is_confidential: false,
            confidential_pin: None,
            expire_at: None,
            priority: "normal".to_string(),
            task_status: None,
            accepted_by: None,
            accepted_at: None,
            reactions: HashMap::from([(
                "👍".to_string(),
                vec!["user_somchai".to_string(), "user_nida".to_string()],
            )]),
            mentions: Vec::new(),
            audio_duration_sec: None,
            poll: None,
            event_data: None,
            deleted_for: Vec::new(),
            created_at: now.clone(),
        },
        MessageDoc {
            id: "msg_group_welcome_2".to_string(),
            conversation_id: FAMILY_CHAT_ROOM_ID.to_string(),
            sender_id: "user_nida".to_string(),
            sender_name: "นิดา พี่สาว".to_string(),
            sender_avatar: "https://ui-avatars.com/api/?name=Nida&background=13795B&color=fff&bold=true".to_string(),
            msg_type: "image".to_string(),
            content: "ส่งโปสการ์ดทริปพักผ่อนสุดสัปดาห์เก็บเข้าคลังภาพถาวรเรียบร้อยค่ะ".to_string(),
            sticker_code: None,
            attachment: Some(sample_img_attachment.clone()),
            card_payload: None,
            flex_payload: None,
            reply_to: None,
            read_by: vec![
                "user_jead".to_string(),
                "user_somchai".to_string(),
                "user_nida".to_string(),
            ],
            is_unsent: false,
            is_confidential: true,
            confidential_pin: None,
            expire_at: None,
            priority: "normal".to_string(),
            task_status: None,
            accepted_by: None,
            accepted_at: None,
            reactions: HashMap::new(),
            mentions: Vec::new(),
            audio_duration_sec: None,
            poll: None,
            event_data: None,
            deleted_for: Vec::new(),
            created_at: now.clone(),
        },
        MessageDoc {
            id: "msg_group_welcome_3".to_string(),
            conversation_id: FAMILY_CHAT_ROOM_ID.to_string(),
            sender_id: "user_somchai".to_string(),
            sender_name: "สมชาย เพื่อนบ้าน".to_string(),
            sender_avatar: "https://ui-avatars.com/api/?name=Somchai&background=B45309&color=fff&bold=true".to_string(),
            msg_type: "file".to_string(),
            content: "แนบไฟล์: แผนเที่ยววันหยุดสุดสัปดาห์_เขาใหญ่.txt (ดูได้ที่คลังไฟล์ หรือลิงก์ https://bcaichat.local/trips/weekend)".to_string(),
            sticker_code: None,
            attachment: Some(AttachmentInfo {
                key: sample_doc_key.to_string(),
                url: sample_doc_url,
                file_name: "แผนเที่ยววันหยุดสุดสัปดาห์_เขาใหญ่.txt".to_string(),
                mime_type: "text/plain".to_string(),
                file_size: doc_bytes.len() as u64,
            }),
            card_payload: None,
            flex_payload: None,
            reply_to: None,
            read_by: vec![
                "user_jead".to_string(),
                "user_somchai".to_string(),
                "user_nida".to_string(),
            ],
            is_unsent: false,
            is_confidential: false,
            confidential_pin: None,
            expire_at: None,
            priority: "normal".to_string(),
            task_status: None,
            accepted_by: None,
            accepted_at: None,
            reactions: HashMap::new(),
            mentions: Vec::new(),
            audio_duration_sec: None,
            poll: None,
            event_data: None,
            deleted_for: Vec::new(),
            created_at: now.clone(),
        },
        MessageDoc {
            id: "msg_group_urgent_task".to_string(),
            conversation_id: FAMILY_CHAT_ROOM_ID.to_string(),
            sender_id: "user_jead".to_string(),
            sender_name: "ลุงจืด".to_string(),
            sender_avatar: "https://ui-avatars.com/api/?name=Lung+Jead&background=812920&color=fff&bold=true".to_string(),
            msg_type: "text".to_string(),
            content: "🚨 เรื่องด่วน: ฝากสมชายช่วยรับพัสดุผลไม้สดหน้าบ้านให้หน่อยนะครับ เย็นนี้แวะไปรับครับ".to_string(),
            sticker_code: None,
            attachment: None,
            card_payload: None,
            flex_payload: None,
            reply_to: None,
            read_by: vec![
                "user_jead".to_string(),
                "user_somchai".to_string(),
                "user_nida".to_string(),
            ],
            is_unsent: false,
            is_confidential: false,
            confidential_pin: None,
            expire_at: None,
            priority: "urgent".to_string(),
            task_status: Some("accepted".to_string()),
            accepted_by: Some("สมชาย เพื่อนบ้าน".to_string()),
            accepted_at: Some(now.clone()),
            reactions: HashMap::new(),
            mentions: Vec::new(),
            audio_duration_sec: None,
            poll: None,
            event_data: None,
            deleted_for: Vec::new(),
            created_at: now.clone(),
        },
        {
            let card = serde_json::json!({
                "app_code": "split_bill",
                "title": "หารค่าข้าวกับเพื่อน — มื้อเย็นวันเสาร์",
                "color_hex": "#A04035",
                "heading": "ร้านครัวบ้านสวน ริมน้ำ",
                "subtitle": "มื้อเย็นครอบครัวและเพื่อนบ้าน (4 คน)",
                "highlight_value": "คนละ 350 บาท (รวม 1,400 บาท)",
                "status": "รอโอน",
                "status_label": "รอโอน"
            });
            MessageDoc {
                id: "msg_group_rich_card".to_string(),
                conversation_id: FAMILY_CHAT_ROOM_ID.to_string(),
                sender_id: "user_somchai".to_string(),
                sender_name: "สมชาย เพื่อนบ้าน".to_string(),
                sender_avatar: "https://ui-avatars.com/api/?name=Somchai&background=B45309&color=fff&bold=true".to_string(),
                msg_type: "rich_card".to_string(),
                content: "[หารค่าข้าวกับเพื่อน] ร้านครัวบ้านสวน ริมน้ำ — คนละ 350 บาท".to_string(),
                sticker_code: None,
                attachment: None,
                card_payload: Some(card.clone()),
                flex_payload: Some(card),
                reply_to: None,
                read_by: vec!["user_jead".to_string(), "user_somchai".to_string()],
                is_unsent: false,
                is_confidential: false,
                confidential_pin: None,
                expire_at: None,
                priority: "normal".to_string(),
                task_status: None,
                accepted_by: None,
                accepted_at: None,
                reactions: HashMap::new(),
                mentions: Vec::new(),
                audio_duration_sec: None,
                poll: None,
                event_data: None,
                deleted_for: Vec::new(),
                created_at: now.clone(),
            }
        },
    ];

    for m in family_seed_messages {
        let _ = msg_coll
            .replace_one(doc! { "_id": &m.id }, &m)
            .upsert(true)
            .await;
    }

    // Ensure 5 Demo accounts + conv_group_demo5 + sample album, group note, poll, and event!
    ensure_demo_chat_room(state, &sample_img_attachment).await?;

    // Onboard default admin user ("user_jead") and 5 Demo accounts so personal notes & starter 1-1 chats exist on boot
    let mut onboard_ids = vec!["user_jead"];
    for (id, ..) in DEMO_ACCOUNTS.iter() {
        onboard_ids.push(*id);
    }
    for uid in onboard_ids {
        if let Some(u) = users_coll
            .find_one(doc! { "_id": uid })
            .await
            .map_err(|e| e.to_string())?
        {
            ensure_user_onboarding(state, &u).await?;
        }
    }

    Ok(())
}

pub async fn ensure_demo_chat_room(
    state: &AppState,
    sample_img: &AttachmentInfo,
) -> Result<(), String> {
    let users_coll = state.db.collection::<UserDoc>("users");
    let now = Utc::now().to_rfc3339();

    for (i, (id, email, name, bc_id, dept, bg)) in DEMO_ACCOUNTS.iter().enumerate() {
        let (job_title, status_msg) = DEMO_PERSONA_DETAILS[i];
        let user = UserDoc {
            id: id.to_string(),
            email: email.to_string(),
            display_name: name.to_string(),
            bc_id: bc_id.to_string(),
            avatar_url: format!(
                "https://ui-avatars.com/api/?name=Demo+{}&background={}&color=fff&bold=true",
                i + 1,
                bg
            ),
            status_message: status_msg.to_string(),
            qr_token: format!("BCQR_DEMO{}", i + 1),
            role: "user".to_string(),
            department: dept.to_string(),
            job_title: job_title.to_string(),
            google_id: None,
            created_at: now.clone(),
        };
        upsert_seeded_user(&users_coll, &user).await?;
    }

    // All 5 Demo users are friends with each other
    for (a, ..) in DEMO_ACCOUNTS.iter() {
        for (b, ..) in DEMO_ACCOUNTS.iter() {
            if a < b {
                ensure_friendship_pair(state, a, b, false).await?;
            }
        }
    }

    let conv_coll = state.db.collection::<ConversationDoc>("conversations");
    let msg_coll = state.db.collection::<MessageDoc>("messages");
    let notes_coll = state.db.collection::<NoteDoc>("notes");
    let albums_coll = state.db.collection::<AlbumDoc>("albums");

    let mut member_ids: Vec<String> = DEMO_ACCOUNTS
        .iter()
        .map(|(id, ..)| id.to_string())
        .collect();
    member_ids.push("user_ai".to_string());

    let welcome_msg_id = "msg_demo5_welcome".to_string();
    let welcome_text =
        "สวัสดีเพื่อนๆ ครบแก๊งทั้ง 5 คนเลย! ห้องนี้มี 🤖 BC AI ผู้ช่วยส่วนตัว อยู่ด้วย พิมพ์ @ai ให้ช่วยจัดทริป เลือกร้านอร่อย หรือหารค่าข้าวได้ทันทีเลยนะ"
            .to_string();
    let demo_pinned = PinnedMessageSummary {
        id: welcome_msg_id.clone(),
        sender_id: "user_demo1".to_string(),
        sender_name: "ก้อง (Demo 1)".to_string(),
        msg_type: "text".to_string(),
        content: welcome_text.clone(),
        created_at: now.clone(),
    };
    let demo_last = LastMessageSummary {
        id: welcome_msg_id.clone(),
        sender_id: "user_demo1".to_string(),
        sender_name: "ก้อง (Demo 1)".to_string(),
        msg_type: "text".to_string(),
        content: welcome_text.clone(),
        created_at: now.clone(),
        read_count: 4,
    };

    if conv_coll
        .find_one(doc! { "_id": DEMO_CHAT_ROOM_ID })
        .await
        .map_err(|e| e.to_string())?
        .is_none()
    {
        let room = ConversationDoc {
            id: DEMO_CHAT_ROOM_ID.to_string(),
            conv_type: "group".to_string(),
            name: "แก๊งเพื่อนสนิท 5 คน + BC AI".to_string(),
            avatar_url: "https://ui-avatars.com/api/?name=BC+5&background=812920&color=fff&bold=true"
                .to_string(),
            folder: "group".to_string(),
            is_pinned: true,
            is_muted: false,
            is_archived: false,
            invite_token: "BCJOIN-DEMO5".to_string(), // pragma: allowlist secret
            admin_ids: vec!["user_demo1".to_string()],
            member_ids,
            user_meta: HashMap::new(),
            pinned_message: Some(demo_pinned),
            last_message: Some(demo_last),
            created_at: now.clone(),
            updated_at: now.clone(),
        };
        conv_coll
            .insert_one(room)
            .await
            .map_err(|e| e.to_string())?;
    } else {
        let pinned_bson = bson::to_bson(&demo_pinned).unwrap_or(bson::Bson::Null);
        let last_bson = bson::to_bson(&demo_last).unwrap_or(bson::Bson::Null);
        let _ = conv_coll
            .update_one(
                doc! { "_id": DEMO_CHAT_ROOM_ID },
                doc! {
                    "$set": {
                        "name": "แก๊งเพื่อนสนิท 5 คน + BC AI",
                        "folder": "group",
                        "avatar_url": "https://ui-avatars.com/api/?name=BC+5&background=812920&color=fff&bold=true",
                        "invite_token": "BCJOIN-DEMO5", // pragma: allowlist secret
                        "pinned_message": pinned_bson,
                        "last_message": last_bson,
                        "member_ids": &member_ids,
                    }
                },
            )
            .await;
    }

    let welcome_doc = MessageDoc {
        id: welcome_msg_id,
        conversation_id: DEMO_CHAT_ROOM_ID.to_string(),
        sender_id: "user_demo1".to_string(),
        sender_name: "ก้อง (Demo 1)".to_string(),
        sender_avatar:
            "https://ui-avatars.com/api/?name=Demo+1&background=812920&color=fff&bold=true"
                .to_string(),
        msg_type: "text".to_string(),
        content: welcome_text,
        sticker_code: None,
        attachment: None,
        card_payload: None,
        flex_payload: None,
        reply_to: None,
        read_by: vec![
            "user_demo1".to_string(),
            "user_demo2".to_string(),
            "user_demo3".to_string(),
            "user_demo4".to_string(),
            "user_demo5".to_string(),
        ],
        is_unsent: false,
        is_confidential: false,
        confidential_pin: None,
        expire_at: None,
        priority: "normal".to_string(),
        task_status: None,
        accepted_by: None,
        accepted_at: None,
        reactions: HashMap::from([(
            "👍".to_string(),
            vec!["user_demo2".to_string(), "user_demo3".to_string()],
        )]),
        mentions: vec!["user_ai".to_string()],
        audio_duration_sec: None,
        poll: None,
        event_data: None,
        deleted_for: Vec::new(),
        created_at: now.clone(),
    };
    let _ = msg_coll
        .replace_one(doc! { "_id": "msg_demo5_welcome" }, &welcome_doc)
        .upsert(true)
        .await;

    // Seed 1 Sample Poll in conv_group_demo5 ("เสาร์นี้ไปกินข้าวร้านไหนดี?")
    let poll_msg = MessageDoc {
        id: "msg_demo5_seed_poll".to_string(),
        conversation_id: DEMO_CHAT_ROOM_ID.to_string(),
        sender_id: "user_demo1".to_string(),
        sender_name: "ก้อง (Demo 1)".to_string(),
        sender_avatar:
            "https://ui-avatars.com/api/?name=Demo+1&background=812920&color=fff&bold=true"
                .to_string(),
        msg_type: "poll".to_string(),
        content: "📊 โพล: เสาร์นี้ไปกินข้าวร้านไหนดี?".to_string(),
        sticker_code: None,
        attachment: None,
        card_payload: None,
        flex_payload: None,
        reply_to: None,
        read_by: vec!["user_demo1".to_string(), "user_demo2".to_string()],
        is_unsent: false,
        is_confidential: false,
        confidential_pin: None,
        expire_at: None,
        priority: "normal".to_string(),
        task_status: None,
        accepted_by: None,
        accepted_at: None,
        reactions: HashMap::new(),
        mentions: Vec::new(),
        audio_duration_sec: None,
        poll: Some(PollData {
            question: "เสาร์นี้ไปกินข้าวร้านไหนดี?".to_string(),
            options: vec![
                PollOption {
                    id: "opt_1".to_string(),
                    text: "หมูกระทะริมน้ำ บรรยากาศชิล".to_string(),
                    voter_ids: vec!["user_demo1".to_string(), "user_demo2".to_string()],
                },
                PollOption {
                    id: "opt_2".to_string(),
                    text: "ชาบูหม้อไฟ ซุปใส-น้ำดำ".to_string(),
                    voter_ids: vec!["user_demo3".to_string()],
                },
                PollOption {
                    id: "opt_3".to_string(),
                    text: "คาเฟ่โฮมมี่ กาแฟดริป & เค้กส้ม".to_string(),
                    voter_ids: vec!["user_demo4".to_string()],
                },
            ],
            allow_multiple: false,
            is_anonymous: false,
            is_closed: false,
            closed_at: None,
        }),
        event_data: None,
        deleted_for: Vec::new(),
        created_at: now.clone(),
    };
    let _ = msg_coll
        .replace_one(doc! { "_id": "msg_demo5_seed_poll" }, &poll_msg)
        .upsert(true)
        .await;

    // Seed 1 Sample Event in conv_group_demo5 ("นัดกินหมูกระทะ & คาเฟ่เสาร์นี้")
    let starts = (Utc::now() + Duration::days(2)).to_rfc3339();
    let ends = (Utc::now() + Duration::days(2) + Duration::hours(3)).to_rfc3339();
    let event_msg = MessageDoc {
        id: "msg_demo5_seed_event".to_string(),
        conversation_id: DEMO_CHAT_ROOM_ID.to_string(),
        sender_id: "user_demo2".to_string(),
        sender_name: "แพร (Demo 2)".to_string(),
        sender_avatar:
            "https://ui-avatars.com/api/?name=Demo+2&background=B45309&color=fff&bold=true"
                .to_string(),
        msg_type: "event".to_string(),
        content: "📅 นัดหมาย: นัดกินหมูกระทะ & คาเฟ่เสาร์นี้".to_string(),
        sticker_code: None,
        attachment: None,
        card_payload: None,
        flex_payload: None,
        reply_to: None,
        read_by: vec!["user_demo1".to_string(), "user_demo2".to_string()],
        is_unsent: false,
        is_confidential: false,
        confidential_pin: None,
        expire_at: None,
        priority: "normal".to_string(),
        task_status: None,
        accepted_by: None,
        accepted_at: None,
        reactions: HashMap::new(),
        mentions: Vec::new(),
        audio_duration_sec: None,
        poll: None,
        event_data: Some(EventData {
            title: "นัดกินหมูกระทะ & คาเฟ่เสาร์นี้".to_string(),
            description: "เจอกันบ่ายสามถ่ายรูปคาเฟ่ ต่อด้วยหมูกระทะริมน้ำตอนเย็นครบแก๊ง 5 คน".to_string(),
            starts_at: starts,
            ends_at: Some(ends),
            location: "ย่านอารีย์ - สะพานควาย".to_string(),
            going_ids: vec![
                "user_demo1".to_string(),
                "user_demo2".to_string(),
                "user_demo3".to_string(),
            ],
            maybe_ids: vec!["user_demo4".to_string()],
            not_going_ids: Vec::new(),
        }),
        deleted_for: Vec::new(),
        created_at: now.clone(),
    };
    let _ = msg_coll
        .replace_one(doc! { "_id": "msg_demo5_seed_event" }, &event_msg)
        .upsert(true)
        .await;

    // Seed 1 Sample Group Note in conv_group_demo5 ("ลิสต์ร้านอร่อยและแผนเที่ยว")
    let demo_note = NoteDoc {
        id: "note_demo5_seed_1".to_string(),
        conversation_id: Some(DEMO_CHAT_ROOM_ID.to_string()),
        owner_id: "user_demo1".to_string(),
        owner_name: "ก้อง (Demo 1)".to_string(),
        title: "ลิสต์ร้านอร่อยและแผนเที่ยว".to_string(),
        content: "1. ร้านหมูกระทะริมน้ำ จองโต๊ะ 18:00 น.\n2. คาเฟ่โฮมมี่ แวะถ่ายรูปก่อนมื้อเย็น\n3. ทริปหน้าเขาใหญ่ เตรียมเต็นท์และกล้องถ่ายรูป\n4. เรียก @ai ช่วยหารค่าข้าวและสรุปนัดหมายได้ตลอด".to_string(),
        attachments: Vec::new(),
        is_pinned: true,
        liked_by: vec!["user_demo2".to_string(), "user_demo4".to_string()],
        comments: vec![NoteComment {
            id: "comment_demo5_1".to_string(),
            user_id: "user_demo2".to_string(),
            user_name: "แพร (Demo 2)".to_string(),
            content: "ปักหมุดไว้เลยค่ะ รูปทริปอัปโหลดเข้าอัลบั้มถาวรเรียบร้อยไม่กลัวรูปหายแล้ว!".to_string(),
            created_at: now.clone(),
        }],
        created_at: now.clone(),
        updated_at: now.clone(),
    };
    let _ = notes_coll
        .replace_one(doc! { "_id": "note_demo5_seed_1" }, &demo_note)
        .upsert(true)
        .await;

    // Seed Personal Albums in conv_group_demo5 & conv_group_family
    for (album_id, conv_id, title, desc, creator_id, creator_name) in [
        (
            "album_demo5_seed_1",
            DEMO_CHAT_ROOM_ID,
            "อัลบั้มทริปเที่ยวและมื้ออร่อย",
            "รวมภาพความทรงจำแก๊งเพื่อน เก็บความละเอียดเต็มถาวรบน MinIO ไม่หมดอายุ",
            "user_demo2",
            "แพร (Demo 2)",
        ),
        (
            "album_family_seed_1",
            FAMILY_CHAT_ROOM_ID,
            "อัลบั้มภาพครอบครัวและวันหยุด",
            "รวมรูปถ่ายครอบครัวและทริปพักผ่อนจัดเก็บถาวรบน MinIO",
            "user_nida",
            "นิดา พี่สาว",
        ),
    ] {
        let album = AlbumDoc {
            id: album_id.to_string(),
            conversation_id: conv_id.to_string(),
            title: title.to_string(),
            description: desc.to_string(),
            photos: vec![sample_img.clone()],
            created_by: creator_id.to_string(),
            created_by_name: creator_name.to_string(),
            created_at: now.clone(),
            updated_at: now.clone(),
        };
        let _ = albums_coll
            .replace_one(doc! { "_id": album_id }, &album)
            .upsert(true)
            .await;
    }

    Ok(())
}

pub async fn ensure_friendship_pair(
    state: &AppState,
    uid_a: &str,
    uid_b: &str,
    fav_a: bool,
) -> Result<(), String> {
    if uid_a == uid_b {
        return Ok(());
    }
    let friends_coll = state.db.collection::<FriendshipDoc>("friendships");
    let now = Utc::now().to_rfc3339();

    if friends_coll
        .find_one(doc! { "user_id": uid_a, "friend_id": uid_b })
        .await
        .map_err(|e| e.to_string())?
        .is_none()
    {
        let f1 = FriendshipDoc {
            id: Uuid::new_v4().to_string(),
            user_id: uid_a.to_string(),
            friend_id: uid_b.to_string(),
            is_favorite: fav_a,
            is_blocked: false,
            is_hidden: false,
            created_at: now.clone(),
        };
        let _ = friends_coll.insert_one(f1).await;
    }

    if friends_coll
        .find_one(doc! { "user_id": uid_b, "friend_id": uid_a })
        .await
        .map_err(|e| e.to_string())?
        .is_none()
    {
        let f2 = FriendshipDoc {
            id: Uuid::new_v4().to_string(),
            user_id: uid_b.to_string(),
            friend_id: uid_a.to_string(),
            is_favorite: false,
            is_blocked: false,
            is_hidden: false,
            created_at: now,
        };
        let _ = friends_coll.insert_one(f2).await;
    }

    Ok(())
}

pub async fn ensure_direct_conversation(
    state: &AppState,
    user: &UserDoc,
    partner: &UserDoc,
    conv_type: &str,
    folder: &str,
    is_pinned: bool,
    welcome_text: &str,
) -> Result<ConversationDoc, String> {
    let conv_coll = state.db.collection::<ConversationDoc>("conversations");
    let msg_coll = state.db.collection::<MessageDoc>("messages");

    if let Some(existing) = conv_coll
        .find_one(doc! {
            "type": { "$in": ["direct", "official"] },
            "member_ids": { "$all": [&user.id, &partner.id], "$size": 2 }
        })
        .await
        .map_err(|e| e.to_string())?
    {
        return Ok(existing);
    }

    let now = Utc::now().to_rfc3339();
    let conv_id = Uuid::new_v4().to_string();
    let msg_id = Uuid::new_v4().to_string();

    let last_msg = LastMessageSummary {
        id: msg_id.clone(),
        sender_id: partner.id.clone(),
        sender_name: partner.display_name.clone(),
        msg_type: "text".to_string(),
        content: welcome_text.to_string(),
        created_at: now.clone(),
        read_count: 0,
    };

    let conv = ConversationDoc {
        id: conv_id.clone(),
        conv_type: conv_type.to_string(),
        name: partner.display_name.clone(),
        avatar_url: partner.avatar_url.clone(),
        folder: folder.to_string(),
        is_pinned,
        is_muted: false,
        is_archived: false,
        invite_token: String::new(),
        admin_ids: Vec::new(),
        member_ids: vec![user.id.clone(), partner.id.clone()],
        user_meta: HashMap::new(),
        pinned_message: None,
        last_message: Some(last_msg),
        created_at: now.clone(),
        updated_at: now.clone(),
    };

    conv_coll
        .insert_one(&conv)
        .await
        .map_err(|e| e.to_string())?;

    let msg = MessageDoc {
        id: msg_id,
        conversation_id: conv_id,
        sender_id: partner.id.clone(),
        sender_name: partner.display_name.clone(),
        sender_avatar: partner.avatar_url.clone(),
        msg_type: "text".to_string(),
        content: welcome_text.to_string(),
        sticker_code: None,
        attachment: None,
        card_payload: None,
        flex_payload: None,
        reply_to: None,
        read_by: vec![partner.id.clone()],
        is_unsent: false,
        is_confidential: false,
        confidential_pin: None,
        expire_at: None,
        priority: "normal".to_string(),
        task_status: None,
        accepted_by: None,
        accepted_at: None,
        reactions: HashMap::new(),
        mentions: Vec::new(),
        audio_duration_sec: None,
        poll: None,
        event_data: None,
        deleted_for: Vec::new(),
        created_at: now,
    };

    msg_coll
        .insert_one(msg)
        .await
        .map_err(|e| e.to_string())?;

    Ok(conv)
}

pub async fn ensure_user_onboarding(state: &AppState, user: &UserDoc) -> Result<(), String> {
    let users_coll = state.db.collection::<UserDoc>("users");
    let conv_coll = state.db.collection::<ConversationDoc>("conversations");
    let notes_coll = state.db.collection::<NoteDoc>("notes");

    let starter_contacts = vec![
        (
            "user_ai",
            "official",
            "personal",
            true,
            true,
            "สวัสดีครับ! ผมคือ 🤖 BC AI ผู้ช่วยส่วนตัวของคุณ พิมพ์คุยปรึกษาได้ทุกเรื่องในห้องนี้ หรือพิมพ์ @ai ในกลุ่มเพื่อนและครอบครัวให้ช่วยจัดทริป แนะนำร้านอร่อย หารค่าข้าว หรือสรุปนัดหมายได้เลยครับ!",
        ),
        (
            "user_official",
            "official",
            "personal",
            true,
            true,
            "ยินดีต้อนรับสู่ BC Ai Chat! ซิงค์แชทข้ามอุปกรณ์, เก็บรูปและไฟล์ความทรงจำถาวรบน MinIO พร้อมโหมดข้อความลับส่วนตัวล็อก PIN ส่งผิดลบทำลายไฟล์ได้ทันทีครับ",
        ),
        (
            "user_somchai",
            "direct",
            "family",
            false,
            true,
            "สวัสดีครับ มีธุระแถวบ้านหรือชวนกินข้าวมื้อเย็น ทักแชทหรือส่งการ์ดชวนนัดเจอมาได้เลยครับ!",
        ),
        (
            "user_nida",
            "direct",
            "family",
            false,
            false,
            "สวัสดีจ้า ส่งรูปทริปครอบครัวหรือสูตรอาหารไว้ในแชทนี้ได้เลยนะ รูปเก็บถาวรในคลังไม่มีวันหมดอายุจ้า",
        ),
        (
            "user_jead",
            "direct",
            "family",
            false,
            true,
            "ยินดีต้อนรับสู่พื้นที่แชทส่วนตัวของครอบครัวและแก๊งเพื่อนบน BC Ai Chat ครับ",
        ),
    ];

    for (contact_id, conv_type, folder, is_pinned, is_fav, welcome) in starter_contacts {
        if contact_id == user.id {
            continue;
        }
        ensure_friendship_pair(state, &user.id, contact_id, is_fav).await?;
        if let Some(partner) = users_coll
            .find_one(doc! { "_id": contact_id })
            .await
            .map_err(|e| e.to_string())?
        {
            ensure_direct_conversation(
                state,
                user,
                &partner,
                conv_type,
                folder,
                is_pinned,
                welcome,
            )
            .await?;
        }
    }

    // Ensure user is a member of "conv_group_family"
    let _ = conv_coll
        .update_one(
            doc! { "_id": FAMILY_CHAT_ROOM_ID },
            doc! { "$addToSet": { "member_ids": &user.id } },
        )
        .await;

    // If user is one of Demo 1..5, ensure they are friends with all Demo 1..5 and in conv_group_demo5 + user_ai
    let is_demo = DEMO_ACCOUNTS.iter().any(|(id, ..)| *id == user.id);
    if is_demo {
        for (other_id, ..) in DEMO_ACCOUNTS.iter() {
            if *other_id != user.id {
                ensure_friendship_pair(state, &user.id, other_id, false).await?;
            }
        }
        let _ = conv_coll
            .update_one(
                doc! { "_id": DEMO_CHAT_ROOM_ID },
                doc! { "$addToSet": { "member_ids": { "$each": [&user.id, "user_ai"] } } },
            )
            .await;
    }

    // Ensure initial personal note in สมุดบันทึก BC and group note in conv_group_family exist
    let now = Utc::now().to_rfc3339();
    let personal_seed_id = format!("note_personal_seed_{}", user.id);
    if notes_coll
        .find_one(doc! { "_id": &personal_seed_id })
        .await
        .map_err(|e| e.to_string())?
        .is_none()
    {
        let personal_note = NoteDoc {
            id: personal_seed_id.clone(),
            conversation_id: None,
            owner_id: user.id.clone(),
            owner_name: user.display_name.clone(),
            title: "บันทึกส่วนตัวของฉัน — รหัส Wi-Fi บ้าน & ลิสต์หนังน่าดู".to_string(),
            content: "🏠 รหัส Wi-Fi บ้าน: BanChiang_Home5G / รหัส: cozy2026\n🎬 ลิสต์หนัง & ซีรีส์น่าดูวันหยุด: ทริปตามล่าแสงเหนือ, สูตรลับครัวโฮมเมด\n🎒 ของต้องเตรียมออกทริป: กล้องถ่ายรูป, พาวเวอร์แบงก์, เสื้อกันลม\n(บันทึกส่วนตัวในสมุดบันทึก BC ซิงค์อัตโนมัติทุกอุปกรณ์ ไม่มีวันหมดอายุ)".to_string(),
            attachments: vec![],
            is_pinned: true,
            liked_by: vec![],
            comments: vec![],
            created_at: now.clone(),
            updated_at: now.clone(),
        };
        let _ = notes_coll
            .replace_one(doc! { "_id": &personal_seed_id }, personal_note)
            .upsert(true)
            .await;
    } else {
        let _ = notes_coll
            .update_one(
                doc! { "_id": &personal_seed_id },
                doc! { "$set": { "owner_name": &user.display_name } },
            )
            .await;
    }

    let family_note = NoteDoc {
        id: "note_group_family_1".to_string(),
        conversation_id: Some(FAMILY_CHAT_ROOM_ID.to_string()),
        owner_id: "user_jead".to_string(),
        owner_name: "ลุงจืด".to_string(),
        title: "เบอร์ติดต่อฉุกเฉินและข้อตกลงประจำบ้าน".to_string(),
        content: "1. รูปถ่ายและไฟล์ในกลุ่มครอบครัวเก็บถาวรบน MinIO ไม่หมดอายุ\n2. รหัสหรือข้อมูลสำคัญเปิดโหมดข้อความลับส่วนตัวล็อก PIN ได้\n3. หากส่งข้อความหรือรูปผิดห้อง สามารถกดยกเลิกหรือลบทำลายไฟล์ออกจาก MinIO ได้ทันที".to_string(),
        attachments: vec![],
        is_pinned: true,
        liked_by: vec!["user_somchai".to_string(), "user_nida".to_string()],
        comments: vec![],
        created_at: now.clone(),
        updated_at: now,
    };
    let _ = notes_coll
        .replace_one(doc! { "_id": "note_group_family_1" }, &family_note)
        .upsert(true)
        .await;

    Ok(())
}
