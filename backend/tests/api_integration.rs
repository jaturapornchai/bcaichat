use axum::{
    body::Body,
    http::{Request, StatusCode},
};
use base64::{engine::general_purpose::STANDARD as BASE64, Engine as _};
use bcaichat_backend::{config::AppConfig, create_router, seed::seed_initial_data, AppState};
use serde_json::{json, Value};
use tower::ServiceExt;

#[tokio::test]
async fn test_full_bcaichat_api_and_minio_mongo_flow() {
    let config = AppConfig::from_env();
    let state = AppState::init(config).await.expect("init AppState");
    seed_initial_data(&state).await.expect("seed initial data");

    let mut ws_rx = state.ws_hub.tx.subscribe();
    let app = create_router(state.clone());

    // 1. Health check
    let (status, health) = call(&app, "GET", "/api/health", None, None).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(health["status"], "ok");
    assert_eq!(health["mongodb"], true);
    assert_eq!(health["minio"], true);

    // 2. Admin Personal Login (both @bcaichat.local and @bcapp.local alias)
    let (status, alias_auth) = call(
        &app,
        "POST",
        "/api/auth/google",
        None,
        Some(json!({
            "email": "jead@bcapp.local",
            "id_token": "demo_jead"
        })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(alias_auth["user"]["id"], "user_jead");
    assert_eq!(alias_auth["user"]["role"], "admin");
    assert_eq!(alias_auth["user"]["display_name"], "ลุงจืด");
    assert_eq!(alias_auth["user"]["department"], "เจ้าของระบบ");
    assert_eq!(alias_auth["user"]["job_title"], "ผู้ดูแลระบบส่วนตัว");

    let (status, auth_json) = call(
        &app,
        "POST",
        "/api/auth/google",
        None,
        Some(json!({
            "email": "jead@bcaichat.local",
            "display_name": "ลุงจืด"
        })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let token = auth_json["token"].as_str().expect("jwt token").to_string();
    assert_eq!(auth_json["user"]["role"], "admin");

    // 3. Conversations list & family/work folder filter compatibility
    let (status, convs) = call(&app, "GET", "/api/conversations?folder=all", Some(&token), None).await;
    assert_eq!(status, StatusCode::OK);
    let conv_arr = convs.as_array().unwrap();
    assert!(!conv_arr.is_empty());
    assert!(
        !conv_arr.iter().any(|c| c["id"] == "conv_group_office"),
        "legacy conv_group_office must be migrated away"
    );
    let fam_room = conv_arr
        .iter()
        .find(|c| c["id"] == "conv_group_family")
        .expect("conv_group_family must exist");
    assert_eq!(fam_room["name"], "กลุ่มครอบครัว & เพื่อนบ้าน");
    assert_eq!(fam_room["folder"], "family");

    for folder_q in ["family", "work"] {
        let (st, filtered) = call(
            &app,
            "GET",
            &format!("/api/conversations?folder={folder_q}"),
            Some(&token),
            None,
        )
        .await;
        assert_eq!(st, StatusCode::OK);
        assert!(
            filtered.as_array().unwrap().iter().any(|c| c["id"] == "conv_group_family"),
            "folder={folder_q} must return conv_group_family"
        );
    }

    // 3b. Personal Mini-Apps & legacy route slug compatibility (zero 404s)
    let (status, mini_apps) = call(&app, "GET", "/api/mini-apps", None, None).await;
    assert_eq!(status, StatusCode::OK);
    let app_codes: Vec<&str> = mini_apps
        .as_array()
        .unwrap()
        .iter()
        .filter_map(|m| m["app_code"].as_str())
        .collect();
    for expected_code in [
        "ai_companion",
        "split_bill",
        "trip_planner",
        "gift_wishlist",
        "hangout_invite",
    ] {
        assert!(
            app_codes.contains(&expected_code),
            "missing personal mini-app {expected_code}: {app_codes:?}"
        );
    }
    for slug in [
        "ai",
        "split",
        "trip",
        "wishlist",
        "hangout",
        "leave",
        "quotation",
        "expense",
        "booking",
    ] {
        let res = app
            .clone()
            .oneshot(
                Request::builder()
                    .uri(format!("/miniapp/{slug}"))
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::OK, "/miniapp/{slug} must return 200 OK");
    }

    // 4. Upload file to MinIO and fetch back (+ verify seeded personal MinIO files)
    for seeded_key in ["seed_trip_postcard.svg", "seed_weekend_trip.txt"] {
        let res = app
            .clone()
            .oneshot(
                Request::builder()
                    .uri(format!("/api/files/{seeded_key}"))
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::OK, "{seeded_key} must exist in MinIO");
    }

    let sample_content = b"BC Ai Chat Permanent Personal Photo & File Vault Verification 100%";
    let (status, uploaded) = call(
        &app,
        "POST",
        "/api/upload",
        Some(&token),
        Some(json!({
            "file_name": "verify_vault.txt",
            "mime_type": "text/plain",
            "data_base64": BASE64.encode(sample_content),
            "conversation_id": "conv_group_family"
        })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let file_key = uploaded["key"].as_str().unwrap().to_string();

    let res = app
        .clone()
        .oneshot(
            Request::builder()
                .uri(format!("/api/files/{}", file_key))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(res.status(), StatusCode::OK);
    let downloaded_bytes = axum::body::to_bytes(res.into_body(), 1024 * 1024)
        .await
        .unwrap();
    assert_eq!(downloaded_bytes.as_ref(), sample_content);

    // 5. Send message & check vault
    let (status, link_msg) = call(
        &app,
        "POST",
        "/api/conversations/conv_group_family/messages",
        Some(&token),
        Some(json!({
            "type": "text",
            "content": "แชร์พิกัดคาเฟ่วันหยุด https://bcaichat.local/cafe-weekend"
        })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);

    // 6. Check Vault
    let (status, vault) = call(
        &app,
        "GET",
        "/api/conversations/conv_group_family/vault",
        Some(&token),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert!(!vault["images"].as_array().unwrap().is_empty());
    assert!(!vault["files"].as_array().unwrap().is_empty());
    assert!(!vault["links"].as_array().unwrap().is_empty());

    // Clean up uploaded verify_vault.txt so Vault stays clean
    let _ = state.minio.delete_object(&file_key).await;
    let _ = state
        .db
        .collection::<bson::Document>("files")
        .delete_many(bson::doc! { "key": &file_key })
        .await;

    // 7. Admin overview & seeded personal users
    let (status, overview) = call(&app, "GET", "/api/admin/overview", Some(&token), None).await;
    assert_eq!(status, StatusCode::OK);
    assert!(overview["total_users"].as_u64().unwrap() >= 10);
    assert!(overview["total_mini_apps"].as_u64().unwrap() >= 5);
    assert!(overview["mongo_db"].as_str().unwrap().starts_with("bcaichat"));
    assert_eq!(overview["minio_bucket"], "bcaichat-storage");

    let (status, all_users) = call(&app, "GET", "/api/admin/users", Some(&token), None).await;
    assert_eq!(status, StatusCode::OK);
    let users_arr = all_users.as_array().unwrap();
    for (uid, expected_name, expected_dept) in [
        ("user_jead", "ลุงจืด", "เจ้าของระบบ"),
        ("user_ai", "🤖 BC AI ผู้ช่วยส่วนตัว", "AI ส่วนตัว"),
        ("user_somchai", "สมชาย เพื่อนบ้าน", "เพื่อนบ้าน"),
        ("user_nida", "นิดา พี่สาว", "ครอบครัว"),
        ("user_official", "ข่าวสาร BC Ai Chat", "ข่าวสารแอป"),
    ] {
        let u = users_arr
            .iter()
            .find(|x| x["id"] == uid)
            .unwrap_or_else(|| panic!("missing user {uid}"));
        assert_eq!(u["display_name"], expected_name);
        assert_eq!(u["department"], expected_dept);
    }

    // 8. Confidential Personal File Message & Instant Purge
    let secret_bytes = b"PRIVATE WIFI & HOME DOOR PASSCODE - ACCIDENTAL SEND";
    let (status, secret_uploaded) = call(
        &app,
        "POST",
        "/api/upload",
        Some(&token),
        Some(json!({
            "file_name": "private_home_note.txt",
            "mime_type": "text/plain",
            "data_base64": BASE64.encode(secret_bytes),
            "conversation_id": "conv_group_family"
        })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let secret_key = secret_uploaded["key"].as_str().unwrap().to_string();
    let secret_url = secret_uploaded["url"].as_str().unwrap().to_string();

    let (status, sent_conf) = call(
        &app,
        "POST",
        "/api/conversations/conv_group_family/messages",
        Some(&token),
        Some(json!({
            "type": "file",
            "content": "รหัสลับส่วนตัวส่งผิดห้อง",
            "is_confidential": true,
            "confidential_pin": "1234",
            "attachment": {
                "key": secret_key,
                "url": secret_url,
                "file_name": "private_home_note.txt",
                "mime_type": "text/plain",
                "file_size": secret_bytes.len()
            }
        })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(sent_conf["is_confidential"], true);
    let conf_msg_id = sent_conf["id"].as_str().unwrap().to_string();

    let (status, purge_res) = call(
        &app,
        "DELETE",
        &format!("/api/messages/{}/purge", conf_msg_id),
        Some(&token),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(purge_res["hard_deleted"], true);
    assert_eq!(purge_res["file_purged"], true);

    let (status, _) = call(&app, "GET", &format!("/api/files/{}", secret_key), None, None).await;
    assert_eq!(status, StatusCode::NOT_FOUND);

    // 9. AI Summarize & Assist & @ai Companion + Secret Key Masking
    let (status, sum_json) = call(
        &app,
        "POST",
        "/api/ai/summarize",
        Some(&token),
        Some(json!({ "conversation_id": "conv_group_family" })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert!(!sum_json["summary"].as_str().unwrap().is_empty());
    assert!(!sum_json["action_items"].as_array().unwrap().is_empty());

    let (status, assist_json) = call(
        &app,
        "POST",
        "/api/ai/assist",
        Some(&token),
        Some(json!({
            "conversation_id": "conv_group_family",
            "prompt": "เสาร์นี้ชวนครอบครัวไปกินข้าวริมน้ำกันนะ",
            "mode": "polish"
        })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert!(!assist_json["result"].as_str().unwrap().is_empty());
    let live = assist_json["live_api"].as_bool().unwrap();
    assert_eq!(assist_json["suggestions"].as_array().unwrap().is_empty(), live);

    let (status, reply_json) = call(
        &app,
        "POST",
        "/api/ai/assist",
        Some(&token),
        Some(json!({ "conversation_id": "conv_group_family", "mode": "suggest_reply" })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let reply = reply_json["result"].as_str().unwrap();
    assert!(!reply.is_empty());
    if reply_json["live_api"].as_bool().unwrap() {
        assert!(
            !reply.chars().any(|c| ('\u{4e00}'..='\u{9fff}').contains(&c)),
            "Chinese in Thai reply: {reply}"
        );
    }

    // Mention @ai in group chat -> AI Companion auto-replies in the room
    let (status, mention_sent) = call(
        &app,
        "POST",
        "/api/conversations/conv_group_family/messages",
        Some(&token),
        Some(json!({
            "type": "text",
            "content": "@ai สรุปนัดหมายทริปวันหยุดในกลุ่มนี้ให้หน่อยครับ"
        })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);

    let (status, msgs_after_ai) = call(
        &app,
        "GET",
        "/api/conversations/conv_group_family/messages",
        Some(&token),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let last_msg = msgs_after_ai.as_array().unwrap().last().unwrap();
    assert_eq!(last_msg["sender_id"], "user_ai");
    let ai_reply_id = last_msg["id"].as_str().unwrap().to_string();

    // Clean up test messages posted to conv_group_family
    for mid in [
        link_msg["id"].as_str().unwrap(),
        mention_sent["id"].as_str().unwrap(),
        ai_reply_id.as_str(),
    ] {
        let _ = call(&app, "DELETE", &format!("/api/messages/{mid}/purge"), Some(&token), None).await;
    }

    // Verify AI Settings never leak raw api_key
    let (status, ai_settings) = call(&app, "GET", "/api/admin/ai-settings", Some(&token), None).await;
    assert_eq!(status, StatusCode::OK);
    assert!(ai_settings.get("api_key").is_none());
    assert!(!ai_settings["masked_key"].as_str().unwrap().contains("sk-"));
    assert_eq!(ai_settings["model"], "deepseek-chat");

    // 10. Urgent Reminder Action, Confirm Rich Card, and Room Care Handover
    let (status, updated_task) = call(
        &app,
        "POST",
        "/api/messages/msg_group_urgent_task/task-action",
        Some(&token),
        Some(json!({ "action": "done" })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(updated_task["task_status"], "done");

    let (status, approved_card) = call(
        &app,
        "POST",
        "/api/messages/msg_group_rich_card/approve-card",
        Some(&token),
        Some(json!({ "status": "โอนแล้ว", "comment": "โอนค่าข้าวเรียบร้อยครับ" })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(approved_card["type"], "rich_card");
    assert_eq!(approved_card["card_payload"]["status"], "โอนแล้ว");
    assert_eq!(approved_card["flex_payload"]["status"], "โอนแล้ว");

    let (status, handover_res) = call(
        &app,
        "POST",
        "/api/admin/handover",
        Some(&token),
        Some(json!({
            "from_user_id": "user_somchai",
            "to_user_id": "user_nida"
        })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(handover_res["status"], "ok");
    assert!(handover_res["transferred_conversations"].as_u64().unwrap() >= 1);
    assert!(handover_res["ai_briefed"].as_u64().is_some());

    // Clean up temporary handover system messages so seeded rooms stay clean
    let _ = state
        .db
        .collection::<bson::Document>("messages")
        .delete_many(bson::doc! { "content": { "$regex": "^🔄 ส่งต่อการดูแลห้องแชท" } })
        .await;

    // 11. Marking an already-read room must not broadcast message_read
    for _ in 0..2 {
        let (status, _) = call(
            &app,
            "POST",
            "/api/conversations/conv_group_family/read",
            Some(&token),
            None,
        )
        .await;
        assert_eq!(status, StatusCode::OK);
    }
    let mut noop_read_events = 0;
    while let Ok(text) = ws_rx.try_recv() {
        let event: Value = serde_json::from_str(&text).unwrap();
        if event["event"] == "message_read" && event["modified_count"] == 0 {
            noop_read_events += 1;
        }
    }
    assert_eq!(noop_read_events, 0, "no-op read must not be broadcast");

    // 12. Five seeded Personal Demo accounts share conv_group_demo5 ("แก๊งเพื่อนสนิท 5 คน + BC AI")
    let expected_demos = [
        ("ก้อง (Demo 1)", "@kong.bc", "เพื่อนสนิท", "สายเที่ยว & ถ่ายรูป"),
        ("แพร (Demo 2)", "@prae.bc", "เพื่อนสนิท", "สายคาเฟ่ & ชวนกินข้าว"),
        ("บอส (Demo 3)", "@boss.bc", "ครอบครัว", "สายแกดเจ็ต & เพลง"),
        ("มายด์ (Demo 4)", "@mind.bc", "เพื่อนสนิท", "สายดูหนัง & ซีรีส์"),
        ("ต้น (Demo 5)", "@ton.bc", "ก๊วนกีฬา", "สายวิ่ง & แคมป์ปิ้ง"),
    ];
    let mut demo_tokens = Vec::new();
    for (idx, (exp_name, exp_bc, exp_dept, exp_job)) in expected_demos.iter().enumerate() {
        let (status, demo_auth) = call(
            &app,
            "POST",
            "/api/auth/google",
            None,
            Some(json!({ "email": format!("demo{}@bcaichat.local", idx + 1) })),
        )
        .await;
        assert_eq!(status, StatusCode::OK);
        assert_eq!(demo_auth["user"]["role"], "user");
        assert_eq!(demo_auth["user"]["display_name"], *exp_name);
        assert_eq!(demo_auth["user"]["bc_id"], *exp_bc);
        assert_eq!(demo_auth["user"]["department"], *exp_dept);
        assert_eq!(demo_auth["user"]["job_title"], *exp_job);
        demo_tokens.push(demo_auth["token"].as_str().unwrap().to_string());
    }
    let demo1_token = &demo_tokens[0];
    let demo2_token = &demo_tokens[1];
    let demo4_token = &demo_tokens[3];

    let (_, convs) = call(&app, "GET", "/api/conversations?folder=all", Some(demo1_token), None).await;
    let room = convs
        .as_array()
        .unwrap()
        .iter()
        .find(|c| c["id"] == "conv_group_demo5")
        .cloned()
        .expect("demo1 sees conv_group_demo5");
    assert_eq!(room["name"], "แก๊งเพื่อนสนิท 5 คน + BC AI");
    assert_eq!(room["folder"], "group");
    assert_eq!(room["members"].as_array().unwrap().len(), 6);

    // Unsend/purge permission check
    let (status, owned) = call(
        &app,
        "POST",
        "/api/conversations/conv_group_family/messages",
        Some(&token),
        Some(json!({ "type": "text", "content": "ข้อความของลุงจืด" })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let owned_id = owned["id"].as_str().unwrap().to_string();
    for action in ["unsend", "purge"] {
        let (status, _) = call(
            &app,
            "POST",
            &format!("/api/messages/{owned_id}/{action}"),
            Some(demo1_token),
            None,
        )
        .await;
        assert_eq!(status, StatusCode::FORBIDDEN, "{action} by someone else");
    }
    let (status, _) = call(
        &app,
        "POST",
        &format!("/api/messages/{owned_id}/purge"),
        Some(&token),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);

    // 13. Ban Chiang 7 themes: anyone reads it, only admin changes it, WS broadcasts theme_changed
    let (status, before) = call(&app, "GET", "/api/settings/theme", None, None).await;
    assert_eq!(status, StatusCode::OK);
    let _original = before["preset"].as_str().unwrap_or("ban_chiang").to_string();
    for valid_theme in [
        "ban_chiang",
        "silk_amber",
        "indigo_kram",
        "jade_celadon",
        "lotus_rose",
        "spice_cinnamon",
        "royal_amethyst",
    ] {
        let (st, _) = call(
            &app,
            "PUT",
            "/api/settings/theme",
            Some(&token),
            Some(json!({ "preset": valid_theme })),
        )
        .await;
        assert_eq!(st, StatusCode::OK, "theme {valid_theme} must be accepted");
    }
    let (status, _) = call(
        &app,
        "PUT",
        "/api/settings/theme",
        Some(demo1_token),
        Some(json!({ "preset": "jade_celadon" })),
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN, "non-admin must not change theme");
    let (status, _) = call(
        &app,
        "PUT",
        "/api/settings/theme",
        Some(&token),
        Some(json!({ "preset": "not_a_theme" })),
    )
    .await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
    while ws_rx.try_recv().is_ok() {}
    let (status, _) = call(
        &app,
        "PUT",
        "/api/settings/theme",
        Some(&token),
        Some(json!({ "preset": "ban_chiang" })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let (_, after) = call(&app, "GET", "/api/settings/theme", None, None).await;
    assert_eq!(after["preset"], "ban_chiang");
    let mut pushed = false;
    while let Ok(text) = ws_rx.try_recv() {
        let event: Value = serde_json::from_str(&text).unwrap();
        pushed |= event["event"] == "theme_changed" && event["preset"] == "ban_chiang";
    }
    assert!(pushed, "theme change must be broadcast");

    // 14. Outsiders (even an admin not in conv_group_demo5) cannot read or post
    let demo_room_uri = "/api/conversations/conv_group_demo5";
    for (method, uri, body) in [
        ("GET", format!("{demo_room_uri}/messages"), None),
        (
            "POST",
            format!("{demo_room_uri}/messages"),
            Some(json!({ "type": "text", "content": "แอบส่ง" })),
        ),
        ("GET", format!("{demo_room_uri}/vault"), None),
        ("POST", format!("{demo_room_uri}/read"), None),
        (
            "POST",
            "/api/ai/summarize".to_string(),
            Some(json!({ "conversation_id": "conv_group_demo5" })),
        ),
    ] {
        let (status, _) = call(&app, method, &uri, Some(&token), body).await;
        assert_eq!(status, StatusCode::FORBIDDEN, "{method} {uri} must reject non-members");
    }

    // 15. Admin-only endpoints reject regular members; new sign-ups get default department "เพื่อน"
    for (method, uri) in [
        ("GET", "/api/admin/overview"),
        ("GET", "/api/admin/users"),
        ("GET", "/api/admin/ai-settings"),
        ("GET", "/api/admin/mini-apps"),
    ] {
        let (status, _) = call(&app, method, uri, Some(demo1_token), None).await;
        assert_eq!(status, StatusCode::FORBIDDEN, "{uri} must be admin only");
        let (status, _) = call(&app, method, uri, Some(&token), None).await;
        assert_eq!(status, StatusCode::OK, "{uri} must work for admin");
    }
    let newbie = format!("newbie_{}@bcaichat.local", uuid::Uuid::new_v4().simple());
    let (status, body) = call(
        &app,
        "POST",
        "/api/auth/google",
        None,
        Some(json!({ "email": newbie, "display_name": "เพื่อนใหม่สายคาเฟ่" })),
    )
    .await;
    let newbie_id = body["user"]["id"].as_str().unwrap_or_default().to_string();
    state
        .db
        .collection::<bson::Document>("users")
        .delete_one(bson::doc! { "email": &newbie })
        .await
        .unwrap();
    if !newbie_id.is_empty() {
        let _ = state
            .db
            .collection::<bson::Document>("friendships")
            .delete_many(bson::doc! { "$or": [{ "user_id": &newbie_id }, { "friend_id": &newbie_id }] })
            .await;
        let _ = state
            .db
            .collection::<bson::Document>("conversations")
            .delete_many(bson::doc! { "type": { "$in": ["direct", "official"] }, "member_ids": &newbie_id })
            .await;
        let _ = state
            .db
            .collection::<bson::Document>("conversations")
            .update_one(
                bson::doc! { "_id": "conv_group_family" },
                bson::doc! { "$pull": { "member_ids": &newbie_id } },
            )
            .await;
        let _ = state
            .db
            .collection::<bson::Document>("notes")
            .delete_many(bson::doc! { "owner_id": &newbie_id })
            .await;
    }
    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["user"]["role"], "user");
    assert_eq!(body["user"]["department"], "เพื่อน");
    assert_eq!(body["user"]["job_title"], "เพื่อน");

    // 16. Shared Personal Contract — Friends management (favorite, block, hide)
    let (status, updated_friend) = call(
        &app,
        "PUT",
        "/api/friends/user_demo2",
        Some(demo1_token),
        Some(json!({ "is_favorite": true, "is_blocked": true, "is_hidden": true })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(updated_friend["is_favorite"], true);
    assert_eq!(updated_friend["is_blocked"], true);
    assert_eq!(updated_friend["is_hidden"], true);

    let (status, restored_friend) = call(
        &app,
        "PUT",
        "/api/friends/user_demo2",
        Some(demo1_token),
        Some(json!({ "is_favorite": false, "is_blocked": false, "is_hidden": false })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(restored_friend["is_blocked"], false);

    // 17. Shared Personal Contract — Group create, meta, invite members (+ user_ai), join via token, leave
    let (status, temp_group) = call(
        &app,
        "POST",
        "/api/conversations/group",
        Some(demo1_token),
        Some(json!({
            "name": "แก๊งนัดเที่ยวสุดสัปดาห์",
            "member_ids": ["user_demo2"],
            "folder": "group"
        })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let gid = temp_group["id"].as_str().unwrap().to_string();
    let invite_tok = temp_group["invite_token"].as_str().unwrap().to_string();
    assert!(!invite_tok.is_empty());
    assert_eq!(temp_group["folder"], "group");
    assert!(temp_group["admin_ids"]
        .as_array()
        .unwrap()
        .iter()
        .any(|id| id == "user_demo1"));

    let (status, meta_updated) = call(
        &app,
        "PUT",
        &format!("/api/conversations/{gid}/meta"),
        Some(demo1_token),
        Some(json!({
            "is_muted": true,
            "is_archived": true,
            "is_pinned": true,
            "folder": "family",
            "name": "แก๊งนัดเที่ยวสุดสัปดาห์ (อัปเดต)"
        })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(meta_updated["is_muted"], true);
    assert_eq!(meta_updated["is_archived"], true);
    assert_eq!(meta_updated["is_pinned"], true);
    assert_eq!(meta_updated["folder"], "family");
    assert_eq!(meta_updated["name"], "แก๊งนัดเที่ยวสุดสัปดาห์ (อัปเดต)");

    let (status, after_invite) = call(
        &app,
        "POST",
        &format!("/api/conversations/{gid}/members"),
        Some(demo1_token),
        Some(json!({ "member_ids": ["user_demo3", "user_ai"] })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let mids: Vec<&str> = after_invite["member_ids"]
        .as_array()
        .unwrap()
        .iter()
        .filter_map(|v| v.as_str())
        .collect();
    assert!(mids.contains(&"user_demo3") && mids.contains(&"user_ai"));

    let (status, joined_conv) = call(
        &app,
        "POST",
        "/api/conversations/join",
        Some(demo4_token),
        Some(json!({ "invite_token": invite_tok })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(joined_conv["id"], gid);
    assert!(joined_conv["member_ids"]
        .as_array()
        .unwrap()
        .iter()
        .any(|v| v == "user_demo4"));

    let (status, after_leave) = call(
        &app,
        "DELETE",
        &format!("/api/conversations/{gid}/members/me"),
        Some(demo4_token),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert!(!after_leave["member_ids"]
        .as_array()
        .unwrap()
        .iter()
        .any(|v| v == "user_demo4"));

    // 18. Audio message, mentions, flex_card -> rich_card alias, reactions, and delete-for-me
    let (status, audio_msg) = call(
        &app,
        "POST",
        &format!("/api/conversations/{gid}/messages"),
        Some(demo1_token),
        Some(json!({
            "type": "audio",
            "content": "ข้อความเสียงชวนกินข้าว",
            "audio_duration_sec": 9,
            "mentions": ["user_demo2"]
        })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(audio_msg["type"], "audio");
    assert_eq!(audio_msg["audio_duration_sec"], 9);
    assert_eq!(audio_msg["mentions"], json!(["user_demo2"]));
    let audio_id = audio_msg["id"].as_str().unwrap().to_string();

    let (status, alias_card) = call(
        &app,
        "POST",
        &format!("/api/conversations/{gid}/messages"),
        Some(demo1_token),
        Some(json!({
            "type": "flex_card",
            "content": "การ์ดโต้ตอบหารค่าข้าว",
            "flex_payload": { "title": "หารค่าข้าวกับเพื่อน", "color_hex": "#812920" }
        })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(alias_card["type"], "rich_card");
    assert_eq!(alias_card["card_payload"]["title"], "หารค่าข้าวกับเพื่อน");

    let (status, reacted) = call(
        &app,
        "POST",
        &format!("/api/messages/{audio_id}/react"),
        Some(demo2_token),
        Some(json!({ "emoji": "❤️" })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(reacted["reactions"]["❤️"], json!(["user_demo2"]));

    let (status, unreacted) = call(
        &app,
        "POST",
        &format!("/api/messages/{audio_id}/react"),
        Some(demo2_token),
        Some(json!({ "emoji": "❤️" })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert!(unreacted["reactions"].get("❤️").is_none());

    let (status, _) = call(
        &app,
        "POST",
        &format!("/api/messages/{audio_id}/delete-for-me"),
        Some(demo1_token),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);

    let (_, demo1_msgs) = call(
        &app,
        "GET",
        &format!("/api/conversations/{gid}/messages"),
        Some(demo1_token),
        None,
    )
    .await;
    assert!(!demo1_msgs.as_array().unwrap().iter().any(|m| m["id"] == audio_id));

    let (_, demo2_msgs) = call(
        &app,
        "GET",
        &format!("/api/conversations/{gid}/messages"),
        Some(demo2_token),
        None,
    )
    .await;
    assert!(demo2_msgs.as_array().unwrap().iter().any(|m| m["id"] == audio_id));

    // 19. Polls: check seeded poll in conv_group_demo5 + create, vote, switch vote, close-poll
    let (status, demo5_msgs) = call(
        &app,
        "GET",
        "/api/conversations/conv_group_demo5/messages",
        Some(demo1_token),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert!(
        demo5_msgs
            .as_array()
            .unwrap()
            .iter()
            .any(|m| m["poll"]["question"] == "เสาร์นี้ไปกินข้าวร้านไหนดี?"),
        "seeded personal poll must exist in conv_group_demo5"
    );

    let (status, poll_msg) = call(
        &app,
        "POST",
        &format!("/api/conversations/{gid}/polls"),
        Some(demo1_token),
        Some(json!({
            "question": "เลือกเมนูมื้อเย็นวันอาทิตย์",
            "options": ["ส้มตำไก่ย่าง", "ชาบูหม้อไฟ"],
            "allow_multiple": false,
            "is_anonymous": false
        })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(poll_msg["type"], "poll");
    let poll_id = poll_msg["id"].as_str().unwrap().to_string();
    let opt1 = poll_msg["poll"]["options"][0]["id"].as_str().unwrap().to_string();
    let opt2 = poll_msg["poll"]["options"][1]["id"].as_str().unwrap().to_string();

    let (status, voted1) = call(
        &app,
        "POST",
        &format!("/api/messages/{poll_id}/vote"),
        Some(demo2_token),
        Some(json!({ "option_ids": [opt1] })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(voted1["poll"]["options"][0]["voter_ids"], json!(["user_demo2"]));

    let (status, voted2) = call(
        &app,
        "POST",
        &format!("/api/messages/{poll_id}/vote"),
        Some(demo2_token),
        Some(json!({ "option_ids": [opt2] })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert!(voted2["poll"]["options"][0]["voter_ids"].as_array().unwrap().is_empty());
    assert_eq!(voted2["poll"]["options"][1]["voter_ids"], json!(["user_demo2"]));

    let (status, closed_poll) = call(
        &app,
        "POST",
        &format!("/api/messages/{poll_id}/close-poll"),
        Some(demo1_token),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(closed_poll["poll"]["is_closed"], true);

    let (status, _) = call(
        &app,
        "POST",
        &format!("/api/messages/{poll_id}/vote"),
        Some(demo2_token),
        Some(json!({ "option_ids": [opt1] })),
    )
    .await;
    assert_eq!(status, StatusCode::BAD_REQUEST);

    // 20. Events: create, RSVP, list events (+ check seeded event in conv_group_demo5)
    let (status, seeded_events) = call(
        &app,
        "GET",
        "/api/conversations/conv_group_demo5/events",
        Some(demo1_token),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert!(
        seeded_events
            .as_array()
            .unwrap()
            .iter()
            .any(|m| m["event_data"]["title"] == "นัดกินหมูกระทะ & คาเฟ่เสาร์นี้"),
        "seeded personal event must exist in conv_group_demo5"
    );

    let (status, ev_msg) = call(
        &app,
        "POST",
        &format!("/api/conversations/{gid}/events"),
        Some(demo1_token),
        Some(json!({
            "title": "ทริปเดินป่าและกางเต็นท์เขาใหญ่",
            "description": "นัดเจอกันเช้าวันเสาร์พร้อมกล้องถ่ายรูป",
            "starts_at": "2026-11-20T07:00:00Z",
            "ends_at": "2026-11-21T16:00:00Z",
            "location": "จุดชมวิวเขาใหญ่"
        })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(ev_msg["type"], "event");
    let ev_id = ev_msg["id"].as_str().unwrap().to_string();

    let (status, rsvp_going) = call(
        &app,
        "POST",
        &format!("/api/messages/{ev_id}/rsvp"),
        Some(demo2_token),
        Some(json!({ "status": "going" })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert!(rsvp_going["event_data"]["going_ids"]
        .as_array()
        .unwrap()
        .iter()
        .any(|u| u == "user_demo2"));

    let (status, gid_events) = call(
        &app,
        "GET",
        &format!("/api/conversations/{gid}/events"),
        Some(demo1_token),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(gid_events.as_array().unwrap().len(), 1);

    // 21. Albums: check seeded album in conv_group_demo5 + create, add photos, delete
    let (status, seeded_albums) = call(
        &app,
        "GET",
        "/api/conversations/conv_group_demo5/albums",
        Some(demo1_token),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert!(
        seeded_albums
            .as_array()
            .unwrap()
            .iter()
            .any(|a| a["title"] == "อัลบั้มทริปเที่ยวและมื้ออร่อย"),
        "seeded personal album must exist in conv_group_demo5"
    );

    let photo1 = json!({
        "key": "seed_trip_postcard.svg",
        "url": "/api/files/seed_trip_postcard.svg",
        "file_name": "trip_photo1.svg",
        "mime_type": "image/svg+xml",
        "file_size": 512
    });
    let (status, created_album) = call(
        &app,
        "POST",
        &format!("/api/conversations/{gid}/albums"),
        Some(demo1_token),
        Some(json!({
            "title": "อัลบั้มรูปคาเฟ่วันหยุด",
            "description": "รวมภาพถ่ายกับเพื่อนสนิท",
            "photos": [photo1]
        })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let album_id = created_album["id"].as_str().unwrap().to_string();
    assert_eq!(created_album["photos"].as_array().unwrap().len(), 1);

    let photo2 = json!({
        "key": "seed_trip_postcard.svg",
        "url": "/api/files/seed_trip_postcard.svg",
        "file_name": "trip_photo2.svg",
        "mime_type": "image/svg+xml",
        "file_size": 512
    });
    let (status, updated_album) = call(
        &app,
        "POST",
        &format!("/api/albums/{album_id}/photos"),
        Some(demo2_token),
        Some(json!({ "photos": [photo2] })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(updated_album["photos"].as_array().unwrap().len(), 2);

    let (status, _) = call(
        &app,
        "DELETE",
        &format!("/api/albums/{album_id}"),
        Some(demo1_token),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);

    // 22. Group Notes & สมุดบันทึก BC: check seeded group & personal notes + CRUD
    let (status, seeded_notes) = call(
        &app,
        "GET",
        "/api/notes?conversation_id=conv_group_demo5",
        Some(demo1_token),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert!(
        seeded_notes
            .as_array()
            .unwrap()
            .iter()
            .any(|n| n["title"] == "ลิสต์ร้านอร่อยและแผนเที่ยว"),
        "seeded group note must exist in conv_group_demo5"
    );

    let (status, personal_notes) = call(&app, "GET", "/api/notes", Some(demo1_token), None).await;
    assert_eq!(status, StatusCode::OK);
    assert!(
        personal_notes
            .as_array()
            .unwrap()
            .iter()
            .any(|n| n["title"] == "บันทึกส่วนตัวของฉัน — รหัส Wi-Fi บ้าน & ลิสต์หนังน่าดู"),
        "seeded personal notebook entry must exist"
    );

    let (status, created_note) = call(
        &app,
        "POST",
        "/api/notes",
        Some(demo1_token),
        Some(json!({
            "conversation_id": gid,
            "title": "ลิสต์ของต้องเตรียมไปแคมป์",
            "content": "เต็นท์ ไฟฉาย และเก้าอี้สนาม",
            "tags": ["ทริป"],
            "is_pinned": false
        })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let note_id = created_note["id"].as_str().unwrap().to_string();

    let (status, edited_note) = call(
        &app,
        "PUT",
        &format!("/api/notes/{note_id}"),
        Some(demo1_token),
        Some(json!({
            "title": "ลิสต์ของต้องเตรียมไปแคมป์ (ครบแล้ว)",
            "content": "เพิ่มพาวเวอร์แบงก์และเสื้อกันลม",
            "is_pinned": true
        })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(edited_note["title"], "ลิสต์ของต้องเตรียมไปแคมป์ (ครบแล้ว)");
    assert_eq!(edited_note["is_pinned"], true);

    let (status, liked_note) = call(
        &app,
        "POST",
        &format!("/api/notes/{note_id}/like"),
        Some(demo2_token),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(liked_note["liked_by"], json!(["user_demo2"]));

    let (status, commented_note) = call(
        &app,
        "POST",
        &format!("/api/notes/{note_id}/comments"),
        Some(demo2_token),
        Some(json!({ "content": "เดี๋ยวแพรเตรียมขนมกับกาแฟดริปไปเผื่อนะ!" })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(commented_note["comments"].as_array().unwrap().len(), 1);
    assert_eq!(
        commented_note["comments"][0]["content"],
        "เดี๋ยวแพรเตรียมขนมกับกาแฟดริปไปเผื่อนะ!"
    );

    let (status, _) = call(
        &app,
        "DELETE",
        &format!("/api/notes/{note_id}"),
        Some(demo1_token),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);

    // Clean up temporary test group from MongoDB
    let _ = state
        .db
        .collection::<bson::Document>("messages")
        .delete_many(bson::doc! { "conversation_id": &gid })
        .await;
    let _ = state
        .db
        .collection::<bson::Document>("conversations")
        .delete_one(bson::doc! { "_id": &gid })
        .await;
}

async fn call(
    app: &axum::Router,
    method: &str,
    uri: &str,
    token: Option<&str>,
    body: Option<Value>,
) -> (StatusCode, Value) {
    let mut req = Request::builder().method(method).uri(uri);
    if let Some(t) = token {
        req = req.header("authorization", format!("Bearer {}", t));
    }
    let req = match body {
        Some(b) => req
            .header("content-type", "application/json")
            .body(Body::from(b.to_string())),
        None => req.body(Body::empty()),
    }
    .unwrap();
    let res = app.clone().oneshot(req).await.unwrap();
    let status = res.status();
    let bytes = axum::body::to_bytes(res.into_body(), 1024 * 1024).await.unwrap();
    (status, serde_json::from_slice(&bytes).unwrap_or(Value::Null))
}
