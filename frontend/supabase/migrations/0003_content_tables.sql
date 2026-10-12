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
