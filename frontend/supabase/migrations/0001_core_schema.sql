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
