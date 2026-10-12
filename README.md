# 🌳 Gia Phả Điện Tử

**Website gia phả điện tử** — hiển thị cây gia phả toàn cảnh, quản lý thành viên, và lưu trữ thông tin dòng họ qua nhiều thế hệ. **Miễn phí hoàn toàn** (Supabase free tier + Vercel free tier).

🔗 **Demo:** [gia-pha-demo.vercel.app/tree](https://gia-pha-demo.vercel.app/tree)

![Demo cây gia phả toàn cảnh](demo.jpeg)

---

## 📋 Mục lục

- [Tính năng](#-tính-năng)
- [Tech Stack](#-tech-stack)
- [Cấu trúc project](#-cấu-trúc-project)
- [Cài đặt & chạy local](#-cài-đặt--chạy-local)
- [Biến môi trường](#-biến-môi-trường)
- [Database Setup](#-database-setup)
- [Deploy lên Vercel](#-deploy-lên-vercel)
- [Tái sử dụng cho dòng họ khác](#-tái-sử-dụng-cho-dòng-họ-khác)

---

## ✨ Tính năng

### 🌲 Cây Gia Phả (Interactive Tree)
- **Toàn cảnh:** Hiển thị toàn bộ cây gia phả với auto-collapse thông minh, zoom/pan tự do
- **Tổ tiên:** Xem dòng dõi từ một người lên tổ tiên
- **Hậu duệ:** Xem tất cả con cháu từ một người
- **Tìm kiếm:** Search bar tìm nhanh theo tên
- **Thu gọn/Mở rộng:** Click toggle để ẩn/hiện nhánh, hiển thị summary "📦 X người"
- **Editor Mode (Admin):** Chỉnh sửa tên, năm sinh/mất, trạng thái, đổi cha (searchable combobox), sắp xếp thứ tự con

### 📖 Sách Gia Phả
- Tự động generate nội dung sách gia phả từ dữ liệu cây
- Xuất theo thế hệ, chi tiết từng nhánh

### 📇 Danh Bạ (Directory)
- Tra cứu thông tin liên lạc thành viên (SĐT, email, Zalo, Facebook)
- Filter theo thế hệ, tìm kiếm theo tên

### 📅 Sự Kiện · 📰 Bảng Tin · 🖼️ Thư Viện
- Lịch sự kiện, tin tức, hình ảnh dòng họ

### 🔐 Auth & 🛡️ Admin Panel
- Đăng nhập (Supabase Auth); **đăng ký chỉ bằng mã mời** do Admin tạo, kiểm tra ngay trong database
- Phân quyền: **Admin** (toàn quyền) · **Member** (xem, đăng bài, bình luận, đề xuất chỉnh sửa) · **Viewer** (chỉ xem)
- Quản lý users, kiểm duyệt đóng góp, audit log (do trigger ghi), backup

### 🔒 Quyền riêng tư
- Cây gia phả đọc qua view `people_view`, che dữ liệu theo vai trò:
  - **Khách (chưa đăng nhập):** thấy tên + năm sinh người đang sống, không thấy ngày/nơi sinh và thông tin liên lạc; người đã mất hiển thị đầy đủ (trừ liên lạc)
  - **Member/Viewer:** thấy cả thông tin liên lạc
  - Người đánh dấu `is_privacy_filtered`: chỉ hiện tên + đời (trừ Admin)
- SĐT, email, Zalo, địa chỉ, ghi chú nằm ở bảng riêng `people_private`

### 💬 Đóng Góp & Bình Luận
- Thành viên đề xuất chỉnh sửa → Admin review & approve/reject
- Hệ thống comment cho từng profile

---

## 🛠 Tech Stack

| Layer | Technology |
|-------|-----------|
| **Framework** | Next.js 16 (App Router, Turbopack) |
| **Language** | TypeScript |
| **UI** | TailwindCSS 4 + shadcn/ui (Radix UI) |
| **State** | Zustand, React Query |
| **Animation** | Framer Motion |
| **Auth & DB** | Supabase (PostgreSQL + Auth) |
| **Forms** | React Hook Form + Zod |
| **Deploy** | Vercel |

---

## 📁 Cấu trúc project

```
Gia-Pha-Dien-Tu/
├── README.md
└── frontend/
    ├── .env.local.example        # ← Copy thành .env.local
    ├── package.json
    ├── supabase/
    │   ├── migrations/           # Schema + RLS + trigger (0001…0005)
    │   ├── seed.sql              # Dữ liệu mẫu demo
    │   ├── database-setup.sql    # Sinh bởi `npm run db:bundle`
    │   └── tests/                # Test RLS (PGlite)
    └── src/
        ├── app/
        │   ├── (auth)/           # Login, Register, Forgot Password
        │   ├── (main)/           # App chính (sidebar)
        │   │   ├── tree/         # 🌲 Cây gia phả
        │   │   ├── book/         # 📖 Sách gia phả
        │   │   ├── directory/    # 📇 Danh bạ
        │   │   ├── events/       # 📅 Sự kiện
        │   │   ├── feed/         # 📰 Bảng tin
        │   │   ├── media/        # 🖼️ Thư viện
        │   │   ├── people/       # 👥 Thành viên
        │   │   └── admin/        # 🛡️ Admin panel
        ├── components/
        │   ├── auth-provider.tsx  # Auth context
        │   ├── layout/           # Sidebar + Header
        │   └── ui/               # shadcn/ui (13 components)
        └── lib/
            ├── supabase.ts       # Supabase client
            ├── supabase-data.ts  # CRUD operations
            ├── tree-layout.ts    # Thuật toán layout cây
            └── book-generator.ts # Tạo nội dung sách
```

### Core Files

| File | Vai trò |
|------|---------|
| `tree-client.tsx` | Component chính — zoom/pan, collapse, editor panel |
| `tree-layout.ts` | Thuật toán: BFS generation, anchor positioning, orthogonal connections |
| `supabase-data.ts` | Data layer: fetch, update, add, delete people/families |
| `auth-provider.tsx` | Auth: login/logout, role checking, session |

---

## 🚀 Cài đặt & chạy local

### Yêu cầu
- **Node.js** ≥ 18
- Tài khoản **Supabase** (free tier OK)

### Setup

```bash
# 1. Clone
git clone https://github.com/0xAstroAlpha/Gia-Pha-Dien-Tu.git
cd Gia-Pha-Dien-Tu/frontend

# 2. Install
npm install

# 3. Config
cp .env.local.example .env.local
# Sửa .env.local với Supabase keys của bạn

# 4. Run
npm run dev
```

Mở [http://localhost:3000](http://localhost:3000)

---

## 🔑 Biến môi trường

Copy `frontend/.env.local.example` → `frontend/.env.local`:

| Biến | Mô tả | Lấy từ |
|------|--------|--------|
| `NEXT_PUBLIC_SUPABASE_URL` | Project URL | Supabase → Settings → API |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | Anonymous key (public) | Supabase → Settings → API |
| `SUPABASE_SERVICE_ROLE_KEY` | Service role key (⚠️ SECRET) | Supabase → Settings → API |
| `NEXT_PUBLIC_DEMO_MODE` | `true` = chạy bằng dữ liệu mẫu, không cần Supabase (mặc định tắt) | — |

> Thiếu cấu hình Supabase mà không bật `NEXT_PUBLIC_DEMO_MODE` thì app báo lỗi cấu hình rõ ràng, không hiển thị dữ liệu giả.

---

## 🗄 Database Setup

Schema nằm trong `frontend/supabase/migrations/` (theo thứ tự `0001` → `0005`). Để dán một lần vào **Supabase Dashboard → SQL Editor** (trên project **mới, trống**):

```
frontend/supabase/database-setup.sql
```

File này được sinh tự động từ migrations (+ dữ liệu mẫu `seed.sql`):

```bash
cd frontend
npm run db:bundle                    # kèm dữ liệu mẫu demo
npm run db:bundle -- --no-seed       # chỉ schema, dùng cho dữ liệu thật
```

| Bảng | Mô tả |
|------|-------|
| `people` | Thành viên (tên, đời, năm sinh/mất, trạng thái) |
| `people_private` | Thông tin liên lạc / đời tư (chỉ đọc qua view `people_view`) |
| `families` | Quan hệ gia đình (cha, mẹ, danh sách con) |
| `profiles` | Tài khoản + vai trò (`admin`/`member`/`viewer`), tạo bởi trigger khi đăng ký |
| `invite_links` | Mã mời đăng ký (hết hạn sau 7 ngày, không cấp được admin) |
| `contributions` | Đề xuất chỉnh sửa (pending → approved/rejected qua RPC `review_contribution`) |
| `comments` / `post_comments` | Bình luận hồ sơ / bình luận bài viết |
| `posts`, `events`, `event_rsvps`, `media` | Bảng tin, sự kiện, thư viện |
| `notifications`, `audit_logs` | Do trigger sinh ra, client không ghi trực tiếp |

### Tạo Admin đầu tiên (một lần, thủ công)

Không có đường nào trong ứng dụng để tự thành admin. Sau khi chạy SQL setup, trong SQL Editor:

```sql
-- 1) Tạo mã mời để chính bạn đăng ký
INSERT INTO invite_links (code, role, max_uses) VALUES ('MA-MOI-CUA-BAN', 'member', 1);
```

Mở `/register`, đăng ký bằng mã đó. Sau đó:

```sql
-- 2) Nâng tài khoản vừa đăng ký lên admin
UPDATE profiles SET role = 'admin' WHERE email = 'email-cua-ban@example.com';
```

Từ đó Admin tạo mã mời cho người khác và cấp quyền tại `/admin/users`.

### Kiểm thử RLS

Test bảo mật chạy trên Postgres nhúng (PGlite), không cần Docker hay Supabase:

```bash
cd frontend
npm test
```

> PGlite dùng phần `auth` giả lập, nên vẫn nên thử vài kịch bản chính (đăng ký bằng mã mời, đổi role, khách đọc cây) trên project Supabase thật sau khi setup.

## 🌐 Deploy lên Vercel

1. [vercel.com](https://vercel.com) → New Project → Import repo
2. **Root Directory:** `frontend`
3. Thêm 3 Environment Variables (giống `.env.local`)
4. Deploy! Auto-deploy mỗi khi push lên `main`

---

## 🔄 Tái sử dụng cho dòng họ khác

### 1. Fork & Clone → npm install
### 2. Tạo Supabase project → chạy `database-setup.sql`
### 3. Tạo admin đầu tiên (xem mục "Tạo Admin đầu tiên")
### 4. Cập nhật branding:

| File | Thay đổi |
|------|----------|
| `src/app/(main)/page.tsx` | Tên dòng họ |
| `src/components/layout/sidebar.tsx` | Logo, tên sidebar |
| `src/app/layout.tsx` | SEO title |

### 5. Nhập dữ liệu gia phả

```sql
-- Thêm người
INSERT INTO people (handle, display_name, gender, generation, families, parent_families)
VALUES ('P001', 'Nguyễn Văn A', 1, 1, '{"F001"}', '{}');

-- Thêm gia đình
INSERT INTO families (handle, father_handle, children)
VALUES ('F001', 'P001', '{"P002","P003"}');
```

**Quy tắc:** `gender`: 1=Nam, 2=Nữ · `generation`: 1=tổ tiên xa nhất · `is_patrilineal`: true=chính tộc

### 6. Deploy lên Vercel → Done! 🎉

---

## 📝 License

MIT — Free to use for any family.

## 🤝 Đóng góp

Fork repo, submit Pull Request, hoặc mở Issue.
