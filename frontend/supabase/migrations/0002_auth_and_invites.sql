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
