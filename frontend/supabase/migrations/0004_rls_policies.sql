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

-- ── RPC: danh bạ thành viên ────────────────────────────────
-- Cho mọi người dùng đã đăng nhập xem danh sách thành viên mà KHÔNG lộ email
-- (profiles bị khóa theo từng người). Email chỉ trả về cho admin.
CREATE FUNCTION list_members()
RETURNS TABLE (
    id UUID, display_name TEXT, avatar_url TEXT, role TEXT,
    person_handle TEXT, email TEXT, created_at TIMESTAMPTZ
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT p.id, p.display_name, p.avatar_url, p.role, p.person_handle,
           CASE WHEN is_admin() THEN p.email END,
           p.created_at
      FROM profiles p
     WHERE is_user()
     ORDER BY p.created_at
$$;

-- ── Quyền ở mức bảng ───────────────────────────────────────
-- Thu hồi mặc định rộng của Supabase cho `anon`, rồi cấp lại đúng thứ cần.
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM anon;
GRANT SELECT ON people_view, families TO anon;
GRANT SELECT ON people_view TO authenticated;

REVOKE EXECUTE ON FUNCTION review_contribution(UUID, BOOLEAN, TEXT) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION review_contribution(UUID, BOOLEAN, TEXT) TO authenticated;
GRANT  EXECUTE ON FUNCTION validate_invite_code(TEXT) TO anon, authenticated;
REVOKE EXECUTE ON FUNCTION list_members() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION list_members() TO authenticated;
