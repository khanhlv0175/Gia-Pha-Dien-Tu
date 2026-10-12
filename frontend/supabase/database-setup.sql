-- ============================================================
-- 🌳 Gia Phả Điện Tử — Database Setup (FILE SINH TỰ ĐỘNG)
-- Sinh bởi: npm run db:bundle — KHÔNG sửa tay, hãy sửa trong supabase/migrations/
-- Bao gồm dữ liệu mẫu demo (xóa bằng: npm run db:bundle -- --no-seed)
-- Chạy trên project Supabase MỚI (schema trống).
-- ============================================================

-- ───── migrations/0001_core_schema.sql ─────

-- ============================================================
-- 0001 — Core schema: people, people_private, families, profiles
-- ============================================================
-- Nguyên tắc: bảng `people` chỉ chứa thông tin ít nhạy cảm; mọi thông tin
-- liên lạc/đời tư nằm ở `people_private`. Người dùng KHÔNG đọc trực tiếp
-- hai bảng này mà đọc qua view `people_view` (xem 0004) để áp dụng che dữ liệu.

CREATE TABLE people (
    handle TEXT PRIMARY KEY,
    gramps_id TEXT,
    gender INT NOT NULL DEFAULT 1 CHECK (gender IN (1, 2)),   -- 1=Nam, 2=Nữ
    display_name TEXT NOT NULL CHECK (char_length(display_name) BETWEEN 1 AND 200),
    surname TEXT,
    first_name TEXT,
    generation INT DEFAULT 1,
    chi INT,
    birth_year INT,
    birth_date TEXT,
    birth_place TEXT,
    death_year INT,
    death_date TEXT,
    death_place TEXT,
    is_living BOOLEAN NOT NULL DEFAULT true,
    is_privacy_filtered BOOLEAN NOT NULL DEFAULT false,
    is_patrilineal BOOLEAN NOT NULL DEFAULT true,             -- true=chính tộc, false=ngoại tộc
    families TEXT[] NOT NULL DEFAULT '{}',                    -- family handles mà người này là cha/mẹ
    parent_families TEXT[] NOT NULL DEFAULT '{}',             -- family handles mà người này là con
    nick_name TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE people_private (
    handle TEXT PRIMARY KEY REFERENCES people(handle) ON DELETE CASCADE ON UPDATE CASCADE,
    phone TEXT,
    email TEXT,
    zalo TEXT,
    facebook TEXT,
    current_address TEXT,
    hometown TEXT,
    occupation TEXT,
    company TEXT,
    education TEXT,
    notes TEXT,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE families (
    handle TEXT PRIMARY KEY,
    father_handle TEXT,
    mother_handle TEXT,
    children TEXT[] NOT NULL DEFAULT '{}',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_people_generation ON people (generation);
CREATE INDEX idx_people_surname ON people (surname);
CREATE INDEX idx_families_father ON families (father_handle);
CREATE INDEX idx_families_mother ON families (mother_handle);

CREATE FUNCTION set_updated_at() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$;

CREATE TRIGGER people_updated_at BEFORE UPDATE ON people
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER people_private_updated_at BEFORE UPDATE ON people_private
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER families_updated_at BEFORE UPDATE ON families
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ── profiles ────────────────────────────────────────────────
-- Dòng profile CHỈ được tạo bởi trigger handle_new_user (0002), không từ client.
CREATE TABLE profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email TEXT UNIQUE NOT NULL,
    display_name TEXT CHECK (char_length(display_name) <= 100),
    role TEXT NOT NULL DEFAULT 'member' CHECK (role IN ('admin', 'member', 'viewer')),
    person_handle TEXT,
    avatar_url TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ── Helper: vai trò của người đang gọi ─────────────────────
-- SECURITY DEFINER để dùng được bên trong policy của chính `profiles`
-- mà không bị đệ quy RLS.
CREATE FUNCTION current_app_role() RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT role FROM profiles WHERE id = auth.uid()
$$;

CREATE FUNCTION is_admin() RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT coalesce((SELECT role = 'admin' FROM profiles WHERE id = auth.uid()), false)
$$;

-- member hoặc admin (có quyền tạo nội dung)
CREATE FUNCTION is_member() RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT coalesce((SELECT role IN ('admin', 'member') FROM profiles WHERE id = auth.uid()), false)
$$;

-- Đã đăng nhập và có profile
CREATE FUNCTION is_user() RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid())
$$;

-- 'admin' | 'user' | 'guest' — dùng cho view che dữ liệu
CREATE FUNCTION viewer_tier() RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT CASE
        WHEN auth.uid() IS NULL THEN 'guest'
        WHEN (SELECT role FROM profiles WHERE id = auth.uid()) = 'admin' THEN 'admin'
        WHEN EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid()) THEN 'user'
        ELSE 'guest'
    END
$$;

-- ───── migrations/0002_auth_and_invites.sql ─────

-- ============================================================
-- 0002 — Đăng ký bằng mã mời (thực thi trong DB) + bảo vệ profiles
-- ============================================================

CREATE TABLE invite_links (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code TEXT UNIQUE NOT NULL CHECK (char_length(code) BETWEEN 6 AND 64),
    -- Mã mời KHÔNG thể cấp admin: admin chỉ được gán bằng SQL / trang quản trị.
    role TEXT NOT NULL DEFAULT 'member' CHECK (role IN ('member', 'viewer')),
    max_uses INT NOT NULL DEFAULT 1 CHECK (max_uses > 0),
    used_count INT NOT NULL DEFAULT 0 CHECK (used_count >= 0),
    expires_at TIMESTAMPTZ NOT NULL DEFAULT (now() + interval '7 days'),
    created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Tạo profile khi có user mới. Từ chối đăng ký nếu mã mời không hợp lệ.
CREATE FUNCTION handle_new_user() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_code  TEXT;
    v_inv   invite_links%ROWTYPE;
    v_email TEXT;
    v_name  TEXT;
BEGIN
    v_email := coalesce(NEW.email, '');
    IF v_email = '' THEN
        RAISE EXCEPTION 'EMAIL_REQUIRED';
    END IF;

    v_code := nullif(trim(NEW.raw_user_meta_data ->> 'invite_code'), '');
    IF v_code IS NULL THEN
        RAISE EXCEPTION 'INVITE_CODE_REQUIRED';
    END IF;

    -- Khóa dòng để hai đăng ký đồng thời không cùng dùng lượt cuối.
    SELECT * INTO v_inv FROM invite_links WHERE code = v_code FOR UPDATE;
    IF NOT FOUND OR v_inv.expires_at < now() OR v_inv.used_count >= v_inv.max_uses THEN
        RAISE EXCEPTION 'INVALID_INVITE_CODE';
    END IF;

    UPDATE invite_links SET used_count = used_count + 1 WHERE id = v_inv.id;

    v_name := left(
        coalesce(nullif(trim(NEW.raw_user_meta_data ->> 'display_name'), ''), split_part(v_email, '@', 1)),
        100
    );

    -- Vai trò lấy từ mã mời, không bao giờ từ metadata do client gửi.
    INSERT INTO profiles (id, email, display_name, role)
    VALUES (NEW.id, v_email, v_name, v_inv.role);

    RETURN NEW;
END;
$$;

CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION handle_new_user();

-- Cho trang đăng ký báo lỗi sớm mà không lộ thông tin gì ngoài đúng/sai.
CREATE FUNCTION validate_invite_code(p_code TEXT) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT EXISTS (
        SELECT 1 FROM invite_links
        WHERE code = p_code AND expires_at > now() AND used_count < max_uses
    )
$$;

-- Chặn người dùng thường tự đổi role / email / person_handle của mình.
-- Tin tưởng: service role và SQL Editor (không có JWT subject), và admin.
CREATE FUNCTION guard_profile_update() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    IF auth.uid() IS NOT NULL AND NOT is_admin() THEN
        IF NEW.id            IS DISTINCT FROM OLD.id
        OR NEW.email         IS DISTINCT FROM OLD.email
        OR NEW.role          IS DISTINCT FROM OLD.role
        OR NEW.person_handle IS DISTINCT FROM OLD.person_handle
        OR NEW.created_at    IS DISTINCT FROM OLD.created_at THEN
            RAISE EXCEPTION 'FORBIDDEN_PROFILE_FIELD' USING ERRCODE = '42501';
        END IF;
    END IF;

    -- Không để hệ thống không còn admin nào qua thao tác từ ứng dụng.
    IF auth.uid() IS NOT NULL
       AND OLD.role = 'admin' AND NEW.role <> 'admin'
       AND NOT EXISTS (SELECT 1 FROM profiles WHERE role = 'admin' AND id <> OLD.id) THEN
        RAISE EXCEPTION 'LAST_ADMIN' USING ERRCODE = '42501';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER profiles_guard BEFORE UPDATE ON profiles
    FOR EACH ROW EXECUTE FUNCTION guard_profile_update();

-- ───── migrations/0003_content_tables.sql ─────

-- ============================================================
-- 0003 — Bảng nội dung: contributions, comments, posts, events, media, notifications
-- ============================================================

-- ── contributions (đề xuất chỉnh sửa) ───────────────────────
CREATE TABLE contributions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    author_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    author_email TEXT,
    person_handle TEXT NOT NULL REFERENCES people(handle) ON DELETE CASCADE,
    person_name TEXT,
    -- Danh sách trắng: chỉ các trường không mang tính cấu trúc.
    field_name TEXT NOT NULL CHECK (field_name IN (
        'display_name', 'birth_year', 'death_year', 'occupation',
        'address', 'phone', 'biography', 'other'
    )),
    field_label TEXT,
    old_value TEXT,
    new_value TEXT NOT NULL CHECK (char_length(new_value) BETWEEN 1 AND 5000),
    note TEXT CHECK (char_length(note) <= 2000),
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
    admin_note TEXT,
    reviewed_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    reviewed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_contributions_status ON contributions(status);
CREATE INDEX idx_contributions_person ON contributions(person_handle);

-- ── comments (bình luận trên hồ sơ người) ──────────────────
CREATE TABLE comments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    author_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    author_email TEXT,
    author_name TEXT,
    person_handle TEXT NOT NULL REFERENCES people(handle) ON DELETE CASCADE,
    content TEXT NOT NULL CHECK (char_length(content) BETWEEN 1 AND 2000),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_comments_person ON comments(person_handle);

-- ── posts + post_comments (bảng tin) ───────────────────────
CREATE TABLE posts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    author_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    author_name TEXT,
    type TEXT NOT NULL DEFAULT 'general',
    title TEXT CHECK (char_length(title) <= 300),
    body TEXT NOT NULL CHECK (char_length(body) BETWEEN 1 AND 10000),
    is_pinned BOOLEAN NOT NULL DEFAULT false,
    status TEXT NOT NULL DEFAULT 'published',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_posts_created ON posts(created_at DESC);

CREATE TABLE post_comments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    post_id UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    author_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    author_name TEXT,
    body TEXT NOT NULL CHECK (char_length(body) BETWEEN 1 AND 2000),
    parent_id UUID REFERENCES post_comments(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_post_comments_post ON post_comments(post_id);

CREATE TRIGGER posts_updated_at BEFORE UPDATE ON posts
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ── events + event_rsvps ───────────────────────────────────
CREATE TABLE events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title TEXT NOT NULL CHECK (char_length(title) BETWEEN 1 AND 300),
    description TEXT CHECK (char_length(description) <= 5000),
    start_at TIMESTAMPTZ NOT NULL,
    end_at TIMESTAMPTZ,
    location TEXT,
    type TEXT NOT NULL DEFAULT 'MEETING',
    is_recurring BOOLEAN NOT NULL DEFAULT false,
    creator_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    creator_name TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_events_start ON events(start_at);

CREATE TABLE event_rsvps (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id UUID NOT NULL REFERENCES events(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    user_name TEXT,
    status TEXT NOT NULL CHECK (status IN ('GOING', 'MAYBE', 'NOT_GOING')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (event_id, user_id)
);

-- ── media (chỉ metadata; chưa có upload Storage) ───────────
CREATE TABLE media (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    file_name TEXT NOT NULL,
    mime_type TEXT,
    file_size BIGINT,
    title TEXT,
    description TEXT,
    state TEXT NOT NULL DEFAULT 'PENDING' CHECK (state IN ('PENDING', 'PUBLISHED', 'REJECTED')),
    uploader_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    uploader_name TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_media_state ON media(state);

-- ── notifications ──────────────────────────────────────────
CREATE TABLE notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    type TEXT NOT NULL DEFAULT 'SYSTEM',
    title TEXT NOT NULL,
    message TEXT NOT NULL DEFAULT '',
    link_url TEXT,
    is_read BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_notifications_user ON notifications(user_id, is_read);

-- ── audit_logs (chỉ trigger ghi; xem 0005) ─────────────────
CREATE TABLE audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    actor_id UUID REFERENCES profiles(id) ON DELETE SET NULL,
    action TEXT NOT NULL,                 -- CREATE | UPDATE | DELETE
    entity_type TEXT NOT NULL,
    entity_id TEXT,
    changed_fields TEXT[],                -- chỉ TÊN trường, không lưu giá trị
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_audit_created ON audit_logs(created_at DESC);

-- ── Điền tên tác giả từ profile (chống giả mạo, thay cho embed profiles) ──
CREATE FUNCTION fill_actor_name() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_id UUID;
    v_name TEXT;
    v_email TEXT;
BEGIN
    -- Tra cột theo tên qua JSONB (biểu thức NEW.<cột> được plan sớm nên không
    -- dùng được cho cột chỉ tồn tại ở một số bảng).
    v_id := (to_jsonb(NEW) ->> CASE TG_TABLE_NAME
        WHEN 'events' THEN 'creator_id'
        WHEN 'event_rsvps' THEN 'user_id'
        WHEN 'media' THEN 'uploader_id'
        ELSE 'author_id'
    END)::uuid;

    SELECT coalesce(display_name, split_part(email, '@', 1)), email
      INTO v_name, v_email
      FROM profiles WHERE id = v_id;

    CASE TG_TABLE_NAME
        WHEN 'posts' THEN NEW.author_name := v_name;
        WHEN 'post_comments' THEN NEW.author_name := v_name;
        WHEN 'comments' THEN NEW.author_name := v_name; NEW.author_email := v_email;
        WHEN 'contributions' THEN NEW.author_email := v_email;
        WHEN 'events' THEN NEW.creator_name := v_name;
        WHEN 'event_rsvps' THEN NEW.user_name := v_name;
        WHEN 'media' THEN NEW.uploader_name := v_name;
    END CASE;

    RETURN NEW;
END;
$$;

CREATE TRIGGER posts_actor BEFORE INSERT ON posts FOR EACH ROW EXECUTE FUNCTION fill_actor_name();
CREATE TRIGGER post_comments_actor BEFORE INSERT ON post_comments FOR EACH ROW EXECUTE FUNCTION fill_actor_name();
CREATE TRIGGER comments_actor BEFORE INSERT ON comments FOR EACH ROW EXECUTE FUNCTION fill_actor_name();
CREATE TRIGGER contributions_actor BEFORE INSERT ON contributions FOR EACH ROW EXECUTE FUNCTION fill_actor_name();
CREATE TRIGGER events_actor BEFORE INSERT ON events FOR EACH ROW EXECUTE FUNCTION fill_actor_name();
CREATE TRIGGER event_rsvps_actor BEFORE INSERT ON event_rsvps FOR EACH ROW EXECUTE FUNCTION fill_actor_name();
CREATE TRIGGER media_actor BEFORE INSERT ON media FOR EACH ROW EXECUTE FUNCTION fill_actor_name();

-- ── Chặn đổi trường đặc quyền bởi người không phải admin ───
CREATE FUNCTION guard_post_update() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    IF auth.uid() IS NOT NULL AND NOT is_admin() THEN
        IF NEW.is_pinned IS DISTINCT FROM OLD.is_pinned
        OR NEW.author_id IS DISTINCT FROM OLD.author_id
        OR NEW.status    IS DISTINCT FROM OLD.status THEN
            RAISE EXCEPTION 'FORBIDDEN_POST_FIELD' USING ERRCODE = '42501';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER posts_guard BEFORE UPDATE ON posts FOR EACH ROW EXECUTE FUNCTION guard_post_update();

CREATE FUNCTION guard_notification_update() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    IF auth.uid() IS NOT NULL THEN
        IF NEW.user_id IS DISTINCT FROM OLD.user_id
        OR NEW.type    IS DISTINCT FROM OLD.type
        OR NEW.title   IS DISTINCT FROM OLD.title
        OR NEW.message IS DISTINCT FROM OLD.message
        OR NEW.link_url IS DISTINCT FROM OLD.link_url THEN
            RAISE EXCEPTION 'FORBIDDEN_NOTIFICATION_FIELD' USING ERRCODE = '42501';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER notifications_guard BEFORE UPDATE ON notifications FOR EACH ROW EXECUTE FUNCTION guard_notification_update();

-- ───── migrations/0004_rls_policies.sql ─────

-- ============================================================
-- 0004 — RLS, view che dữ liệu, RPC duyệt đóng góp
-- ============================================================
-- Vai trò: admin (toàn quyền) | member (đọc + tạo nội dung + đề xuất sửa) | viewer (chỉ đọc)
-- Khách (chưa đăng nhập) chỉ đọc view people_view (đã che) và bảng families.

ALTER TABLE people          ENABLE ROW LEVEL SECURITY;
ALTER TABLE people_private  ENABLE ROW LEVEL SECURITY;
ALTER TABLE families        ENABLE ROW LEVEL SECURITY;
ALTER TABLE profiles        ENABLE ROW LEVEL SECURITY;
ALTER TABLE invite_links    ENABLE ROW LEVEL SECURITY;
ALTER TABLE contributions   ENABLE ROW LEVEL SECURITY;
ALTER TABLE comments        ENABLE ROW LEVEL SECURITY;
ALTER TABLE posts           ENABLE ROW LEVEL SECURITY;
ALTER TABLE post_comments   ENABLE ROW LEVEL SECURITY;
ALTER TABLE events          ENABLE ROW LEVEL SECURITY;
ALTER TABLE event_rsvps     ENABLE ROW LEVEL SECURITY;
ALTER TABLE media           ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications   ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_logs      ENABLE ROW LEVEL SECURITY;

-- ── people / people_private / families ─────────────────────
-- Bảng gốc: chỉ admin. Mọi người khác đọc qua people_view.
CREATE POLICY people_admin_all ON people
    FOR ALL USING (is_admin()) WITH CHECK (is_admin());
CREATE POLICY people_private_admin_all ON people_private
    FOR ALL USING (is_admin()) WITH CHECK (is_admin());

-- families chỉ là cấu trúc (mã cha/mẹ/con): ai cũng đọc, chỉ admin ghi.
CREATE POLICY families_read ON families FOR SELECT USING (true);
CREATE POLICY families_admin_write ON families
    FOR ALL USING (is_admin()) WITH CHECK (is_admin());

-- ── View che dữ liệu ───────────────────────────────────────
-- Chạy với quyền chủ sở hữu (bỏ qua RLS bảng gốc) nhưng tự quyết định
-- trường nào được thấy theo viewer_tier():
--   admin : thấy tất cả
--   user  : thấy tất cả, trừ người is_privacy_filtered (chỉ tên + đời + cấu trúc)
--   guest : người đã mất  -> thông tin cơ bản + ngày/nơi sinh mất, không liên lạc
--           người đang sống -> tên + năm sinh + cấu trúc; không ngày/nơi sinh, không liên lạc
--           is_privacy_filtered -> chỉ tên + đời + cấu trúc
CREATE VIEW people_view WITH (security_invoker = false) AS
SELECT
    p.handle,
    p.gender,
    p.display_name,
    p.generation,
    p.chi,
    p.is_living,
    p.is_privacy_filtered,
    p.is_patrilineal,
    p.families,
    p.parent_families,
    CASE WHEN f.see_basic THEN p.surname END      AS surname,
    CASE WHEN f.see_basic THEN p.first_name END   AS first_name,
    CASE WHEN f.see_basic THEN p.nick_name END    AS nick_name,
    CASE WHEN f.see_basic THEN p.birth_year END   AS birth_year,
    CASE WHEN f.see_basic THEN p.death_year END   AS death_year,
    CASE WHEN f.see_detail THEN p.birth_date END  AS birth_date,
    CASE WHEN f.see_detail THEN p.birth_place END AS birth_place,
    CASE WHEN f.see_detail THEN p.death_date END  AS death_date,
    CASE WHEN f.see_detail THEN p.death_place END AS death_place,
    CASE WHEN f.see_contact THEN pr.phone END           AS phone,
    CASE WHEN f.see_contact THEN pr.email END           AS email,
    CASE WHEN f.see_contact THEN pr.zalo END            AS zalo,
    CASE WHEN f.see_contact THEN pr.facebook END        AS facebook,
    CASE WHEN f.see_contact THEN pr.current_address END AS current_address,
    CASE WHEN f.see_contact THEN pr.hometown END        AS hometown,
    CASE WHEN f.see_contact THEN pr.occupation END      AS occupation,
    CASE WHEN f.see_contact THEN pr.company END         AS company,
    CASE WHEN f.see_contact THEN pr.education END       AS education,
    CASE WHEN f.see_contact THEN pr.notes END           AS notes,
    p.updated_at
FROM people p
LEFT JOIN people_private pr ON pr.handle = p.handle
CROSS JOIN LATERAL (SELECT viewer_tier() AS tier) v
CROSS JOIN LATERAL (
    SELECT
        (v.tier = 'admin' OR NOT p.is_privacy_filtered) AS see_basic,
        (v.tier = 'admin'
            OR (v.tier = 'user'  AND NOT p.is_privacy_filtered)
            OR (v.tier = 'guest' AND NOT p.is_privacy_filtered AND NOT p.is_living)) AS see_detail,
        (v.tier = 'admin'
            OR (v.tier = 'user' AND NOT p.is_privacy_filtered)) AS see_contact
) f;

-- ── profiles ───────────────────────────────────────────────
-- Không có policy INSERT/DELETE: profile chỉ tạo qua trigger, xóa qua auth.users.
CREATE POLICY profiles_select ON profiles
    FOR SELECT USING (id = auth.uid() OR is_admin());
CREATE POLICY profiles_update ON profiles
    FOR UPDATE USING (id = auth.uid() OR is_admin())
    WITH CHECK (id = auth.uid() OR is_admin());

-- ── invite_links (admin) ───────────────────────────────────
CREATE POLICY invite_links_admin_all ON invite_links
    FOR ALL USING (is_admin()) WITH CHECK (is_admin());

-- ── contributions ──────────────────────────────────────────
-- Không có policy UPDATE/DELETE: duyệt chỉ qua RPC review_contribution.
CREATE POLICY contributions_select ON contributions
    FOR SELECT USING (author_id = auth.uid() OR is_admin());
CREATE POLICY contributions_insert ON contributions
    FOR INSERT WITH CHECK (is_member() AND author_id = auth.uid() AND status = 'pending');

-- ── comments (hồ sơ người) ─────────────────────────────────
CREATE POLICY comments_select ON comments FOR SELECT USING (is_user());
CREATE POLICY comments_insert ON comments
    FOR INSERT WITH CHECK (is_member() AND author_id = auth.uid());
CREATE POLICY comments_delete ON comments
    FOR DELETE USING (author_id = auth.uid() OR is_admin());

-- ── posts / post_comments ──────────────────────────────────
CREATE POLICY posts_select ON posts FOR SELECT USING (is_user());
CREATE POLICY posts_insert ON posts
    FOR INSERT WITH CHECK (is_member() AND author_id = auth.uid() AND NOT is_pinned);
CREATE POLICY posts_update ON posts
    FOR UPDATE USING (author_id = auth.uid() OR is_admin())
    WITH CHECK (author_id = auth.uid() OR is_admin());
CREATE POLICY posts_delete ON posts
    FOR DELETE USING (author_id = auth.uid() OR is_admin());

CREATE POLICY post_comments_select ON post_comments FOR SELECT USING (is_user());
CREATE POLICY post_comments_insert ON post_comments
    FOR INSERT WITH CHECK (is_member() AND author_id = auth.uid());
CREATE POLICY post_comments_delete ON post_comments
    FOR DELETE USING (author_id = auth.uid() OR is_admin());

-- ── events / event_rsvps ───────────────────────────────────
CREATE POLICY events_select ON events FOR SELECT USING (is_user());
CREATE POLICY events_admin_write ON events
    FOR ALL USING (is_admin()) WITH CHECK (is_admin());

CREATE POLICY event_rsvps_select ON event_rsvps FOR SELECT USING (is_user());
CREATE POLICY event_rsvps_insert ON event_rsvps
    FOR INSERT WITH CHECK (is_member() AND user_id = auth.uid());
CREATE POLICY event_rsvps_update ON event_rsvps
    FOR UPDATE USING (user_id = auth.uid()) WITH CHECK (is_member() AND user_id = auth.uid());
CREATE POLICY event_rsvps_delete ON event_rsvps
    FOR DELETE USING (user_id = auth.uid() OR is_admin());

-- ── media ──────────────────────────────────────────────────
CREATE POLICY media_select ON media
    FOR SELECT USING (
        (state = 'PUBLISHED' AND is_user())
        OR uploader_id = auth.uid()
        OR is_admin()
    );
CREATE POLICY media_insert ON media
    FOR INSERT WITH CHECK (is_member() AND uploader_id = auth.uid() AND state = 'PENDING');
CREATE POLICY media_admin_update ON media
    FOR UPDATE USING (is_admin()) WITH CHECK (is_admin());
CREATE POLICY media_delete ON media
    FOR DELETE USING (uploader_id = auth.uid() OR is_admin());

-- ── notifications (mỗi người chỉ thấy của mình; do trigger tạo) ──
CREATE POLICY notifications_select ON notifications FOR SELECT USING (user_id = auth.uid());
CREATE POLICY notifications_update ON notifications
    FOR UPDATE USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
CREATE POLICY notifications_delete ON notifications FOR DELETE USING (user_id = auth.uid());

-- ── audit_logs (chỉ admin đọc; không ai ghi trực tiếp) ─────
CREATE POLICY audit_logs_admin_select ON audit_logs FOR SELECT USING (is_admin());

-- ── RPC: duyệt / từ chối đóng góp ──────────────────────────
-- Áp dụng thay đổi và cập nhật trạng thái trong một transaction.
CREATE FUNCTION review_contribution(p_id UUID, p_approve BOOLEAN, p_note TEXT DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    c contributions%ROWTYPE;
BEGIN
    IF NOT is_admin() THEN
        RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO c FROM contributions WHERE id = p_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'CONTRIBUTION_NOT_FOUND';
    END IF;
    IF c.status <> 'pending' THEN
        RAISE EXCEPTION 'ALREADY_REVIEWED';
    END IF;

    IF p_approve THEN
        IF NOT EXISTS (SELECT 1 FROM people WHERE handle = c.person_handle) THEN
            RAISE EXCEPTION 'PERSON_NOT_FOUND';
        END IF;

        IF c.field_name IN ('birth_year', 'death_year') AND c.new_value !~ '^\d{3,4}$' THEN
            RAISE EXCEPTION 'INVALID_YEAR';
        END IF;

        IF c.field_name = 'display_name' THEN
            UPDATE people SET display_name = left(trim(c.new_value), 200) WHERE handle = c.person_handle;
        ELSIF c.field_name = 'birth_year' THEN
            UPDATE people SET birth_year = c.new_value::int WHERE handle = c.person_handle;
        ELSIF c.field_name = 'death_year' THEN
            UPDATE people SET death_year = c.new_value::int, is_living = false WHERE handle = c.person_handle;
        ELSE
            INSERT INTO people_private (handle) VALUES (c.person_handle) ON CONFLICT (handle) DO NOTHING;
            IF c.field_name = 'occupation' THEN
                UPDATE people_private SET occupation = c.new_value WHERE handle = c.person_handle;
            ELSIF c.field_name = 'address' THEN
                UPDATE people_private SET current_address = c.new_value WHERE handle = c.person_handle;
            ELSIF c.field_name = 'phone' THEN
                UPDATE people_private SET phone = c.new_value WHERE handle = c.person_handle;
            ELSE -- biography, other: nối vào ghi chú, không ghi đè
                UPDATE people_private
                   SET notes = coalesce(notes || E'\n\n', '') || '[Đóng góp] ' || c.new_value
                 WHERE handle = c.person_handle;
            END IF;
        END IF;
    END IF;

    UPDATE contributions
       SET status = CASE WHEN p_approve THEN 'approved' ELSE 'rejected' END,
           admin_note = p_note,
           reviewed_by = auth.uid(),
           reviewed_at = now()
     WHERE id = p_id;
END;
$$;

-- ── Quyền ở mức bảng ───────────────────────────────────────
-- Thu hồi mặc định rộng của Supabase cho `anon`, rồi cấp lại đúng thứ cần.
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM anon;
GRANT SELECT ON people_view, families TO anon;
GRANT SELECT ON people_view TO authenticated;

REVOKE EXECUTE ON FUNCTION review_contribution(UUID, BOOLEAN, TEXT) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION review_contribution(UUID, BOOLEAN, TEXT) TO authenticated;
GRANT  EXECUTE ON FUNCTION validate_invite_code(TEXT) TO anon, authenticated;

-- ───── migrations/0005_audit_and_notifications.sql ─────

-- ============================================================
-- 0005 — Nhật ký kiểm toán và thông báo do trigger sinh ra
-- ============================================================

-- Ghi TÊN trường thay đổi, không ghi giá trị (tránh log thành nơi rò rỉ SĐT/email...).
CREATE FUNCTION log_audit() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_new JSONB;
    v_old JSONB;
    v_row JSONB;
    v_fields TEXT[];
BEGIN
    IF TG_OP = 'DELETE' THEN
        v_row := to_jsonb(OLD);
    ELSE
        v_row := to_jsonb(NEW);
    END IF;

    IF TG_OP = 'UPDATE' THEN
        v_new := to_jsonb(NEW);
        v_old := to_jsonb(OLD);
        SELECT coalesce(array_agg(k ORDER BY k), '{}') INTO v_fields
          FROM jsonb_object_keys(v_new) AS k
         WHERE k NOT IN ('updated_at') AND v_new -> k IS DISTINCT FROM v_old -> k;
        IF cardinality(v_fields) = 0 THEN
            RETURN NEW;
        END IF;
    END IF;

    INSERT INTO audit_logs (actor_id, action, entity_type, entity_id, changed_fields)
    VALUES (
        (SELECT id FROM profiles WHERE id = auth.uid()),
        CASE TG_OP WHEN 'INSERT' THEN 'CREATE' WHEN 'UPDATE' THEN 'UPDATE' ELSE 'DELETE' END,
        TG_TABLE_NAME,
        coalesce(v_row ->> 'handle', v_row ->> 'id'),
        v_fields
    );

    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER audit_people AFTER INSERT OR UPDATE OR DELETE ON people
    FOR EACH ROW EXECUTE FUNCTION log_audit();
CREATE TRIGGER audit_people_private AFTER INSERT OR UPDATE OR DELETE ON people_private
    FOR EACH ROW EXECUTE FUNCTION log_audit();
CREATE TRIGGER audit_families AFTER INSERT OR UPDATE OR DELETE ON families
    FOR EACH ROW EXECUTE FUNCTION log_audit();
CREATE TRIGGER audit_profiles AFTER INSERT OR UPDATE OR DELETE ON profiles
    FOR EACH ROW EXECUTE FUNCTION log_audit();
CREATE TRIGGER audit_contributions AFTER UPDATE ON contributions
    FOR EACH ROW EXECUTE FUNCTION log_audit();
CREATE TRIGGER audit_invite_links AFTER INSERT OR DELETE ON invite_links
    FOR EACH ROW EXECUTE FUNCTION log_audit();

-- ── Thông báo ──────────────────────────────────────────────
CREATE FUNCTION notify_contribution_reviewed() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    IF OLD.status = 'pending' AND NEW.status IN ('approved', 'rejected') AND NEW.author_id IS NOT NULL THEN
        INSERT INTO notifications (user_id, type, title, message, link_url)
        VALUES (
            NEW.author_id,
            'SYSTEM',
            CASE NEW.status WHEN 'approved' THEN 'Đóng góp của bạn đã được duyệt'
                            ELSE 'Đóng góp của bạn bị từ chối' END,
            coalesce(NEW.field_label, NEW.field_name) || ' — ' || coalesce(NEW.person_name, NEW.person_handle)
                || coalesce(E'\nGhi chú: ' || NEW.admin_note, ''),
            '/people/' || NEW.person_handle
        );
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER contributions_notify AFTER UPDATE OF status ON contributions
    FOR EACH ROW EXECUTE FUNCTION notify_contribution_reviewed();

CREATE FUNCTION notify_new_event() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    INSERT INTO notifications (user_id, type, title, message, link_url)
    SELECT p.id, 'NEW_EVENT', 'Sự kiện mới: ' || NEW.title,
           to_char(NEW.start_at, 'DD/MM/YYYY HH24:MI') || coalesce(' · ' || NEW.location, ''),
           '/events/' || NEW.id
      FROM profiles p
     WHERE p.role IN ('admin', 'member') AND p.id IS DISTINCT FROM NEW.creator_id;
    RETURN NEW;
END;
$$;
CREATE TRIGGER events_notify AFTER INSERT ON events
    FOR EACH ROW EXECUTE FUNCTION notify_new_event();

-- ───── seed.sql ─────

-- ============================================================
-- Dữ liệu mẫu demo — Họ Nguyễn Văn, 4 thế hệ, 15 thành viên
-- Chỉ chạy cho dev/demo. KHÔNG chạy trên dữ liệu thật.
-- ============================================================
INSERT INTO people (handle, display_name, gender, generation, birth_year, death_year, is_living, is_patrilineal, families, parent_families) VALUES
('P001', 'Nguyễn Văn An',    1, 1, 1920, 1995, false, true, '{"F001"}', '{}'),
('P002', 'Nguyễn Văn Bình',  1, 2, 1945, NULL, true,  true, '{"F002"}', '{"F001"}'),
('P003', 'Nguyễn Văn Cường', 1, 2, 1948, NULL, true,  true, '{"F003"}', '{"F001"}'),
('P004', 'Nguyễn Văn Dũng',  1, 2, 1951, 2020, false, true, '{"F004"}', '{"F001"}'),
('P005', 'Nguyễn Văn Hải',   1, 3, 1970, NULL, true,  true, '{"F005"}', '{"F002"}'),
('P006', 'Nguyễn Văn Hùng',  1, 3, 1973, NULL, true,  true, '{}',       '{"F002"}'),
('P007', 'Nguyễn Văn Khoa',  1, 3, 1975, NULL, true,  true, '{"F006"}', '{"F003"}'),
('P008', 'Nguyễn Văn Khánh', 1, 3, 1978, NULL, true,  true, '{}',       '{"F003"}'),
('P009', 'Nguyễn Văn Long',  1, 3, 1980, NULL, true,  true, '{}',       '{"F004"}'),
('P010', 'Nguyễn Văn Minh',  1, 4, 1995, NULL, true,  true, '{}',       '{"F005"}'),
('P011', 'Nguyễn Văn Nam',   1, 4, 1998, NULL, true,  true, '{}',       '{"F005"}'),
('P012', 'Nguyễn Văn Phúc',  1, 4, 2000, NULL, true,  true, '{}',       '{"F006"}'),
('P013', 'Trần Thị Lan',     2, 1, 1925, 2000, false, false, '{}', '{}'),
('P014', 'Lê Thị Mai',       2, 2, 1948, NULL, true,  false, '{}', '{}'),
('P015', 'Phạm Thị Hoa',     2, 3, 1972, NULL, true,  false, '{}', '{}')
ON CONFLICT (handle) DO NOTHING;

INSERT INTO families (handle, father_handle, mother_handle, children) VALUES
('F001', 'P001', 'P013', '{"P002","P003","P004"}'),
('F002', 'P002', 'P014', '{"P005","P006"}'),
('F003', 'P003', NULL,   '{"P007","P008"}'),
('F004', 'P004', NULL,   '{"P009"}'),
('F005', 'P005', 'P015', '{"P010","P011"}'),
('F006', 'P007', NULL,   '{"P012"}')
ON CONFLICT (handle) DO NOTHING;

SELECT '✅ Database setup complete!' AS status;

