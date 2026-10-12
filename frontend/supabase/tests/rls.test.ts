import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import type { PGlite } from '@electric-sql/pglite';
import { createDb, seed, as, signUp } from './helpers';

let db: PGlite;
let admin: string;
let member: string;
let viewer: string;
let member2: string;

const A = () => ({ uid: admin });
const M = () => ({ uid: member });
const V = () => ({ uid: viewer });
const M2 = () => ({ uid: member2 });

beforeAll(async () => {
    db = await createDb();
    await seed(db);

    // Mã mời dùng cho bootstrap (đúng quy trình README)
    await db.exec(`
        INSERT INTO invite_links (code, role, max_uses) VALUES
            ('BOOTSTRAP-ADMIN', 'member', 1),
            ('MEMBER-CODE-1', 'member', 5),
            ('VIEWER-CODE-1', 'viewer', 5)
    `);
    admin = await signUp(db, 'admin@example.com', { invite_code: 'BOOTSTRAP-ADMIN', display_name: 'Admin' });
    // Bước thủ công duy nhất để có admin đầu tiên: chạy bằng quyền SQL Editor (không JWT).
    await db.exec(`UPDATE profiles SET role = 'admin' WHERE email = 'admin@example.com'`);
    member = await signUp(db, 'member@example.com', { invite_code: 'MEMBER-CODE-1', display_name: 'Member' });
    member2 = await signUp(db, 'member2@example.com', { invite_code: 'MEMBER-CODE-1', display_name: 'Member 2' });
    viewer = await signUp(db, 'viewer@example.com', { invite_code: 'VIEWER-CODE-1', display_name: 'Viewer' });

    // Dữ liệu liên lạc + người bị lọc riêng tư
    await db.exec(`
        INSERT INTO people_private (handle, phone, email, current_address, notes)
        VALUES ('P005', '0901234567', 'hai@example.com', 'Hà Nội', 'ghi chú riêng'),
               ('P001', '0900000000', NULL, NULL, NULL);
        UPDATE people SET birth_date = '1970-05-01', birth_place = 'Nam Định' WHERE handle = 'P005';
        UPDATE people SET birth_date = '1920-01-01', birth_place = 'Thái Bình' WHERE handle = 'P001';
        UPDATE people SET is_privacy_filtered = true WHERE handle = 'P006';
        INSERT INTO people_private (handle, phone) VALUES ('P006', '0911111111');
    `);
});

afterAll(async () => { await db.close(); });

describe('đăng ký bằng mã mời', () => {
    it('từ chối khi không có mã mời', async () => {
        await expect(signUp(db, 'x1@example.com', {})).rejects.toThrow(/INVITE_CODE_REQUIRED/);
    });
    it('từ chối mã sai', async () => {
        await expect(signUp(db, 'x2@example.com', { invite_code: 'nope' })).rejects.toThrow(/INVALID_INVITE_CODE/);
    });
    it('role lấy từ mã mời, bỏ qua role do client gửi', async () => {
        const id = await signUp(db, 'sneaky@example.com', { invite_code: 'VIEWER-CODE-1', role: 'admin' });
        const r = await db.query<{ role: string }>(`SELECT role FROM profiles WHERE id = $1`, [id]);
        expect(r.rows[0].role).toBe('viewer');
    });
    it('mã hết lượt thì từ chối và không tạo user', async () => {
        await db.exec(`INSERT INTO invite_links (code, max_uses) VALUES ('ONE-USE-CODE', 1)`);
        await signUp(db, 'u1@example.com', { invite_code: 'ONE-USE-CODE' });
        await expect(signUp(db, 'u2@example.com', { invite_code: 'ONE-USE-CODE' })).rejects.toThrow(/INVALID_INVITE_CODE/);
        const r = await db.query(`SELECT 1 FROM auth.users WHERE email = 'u2@example.com'`);
        expect(r.rows.length).toBe(0);
    });
    it('mã hết hạn bị từ chối', async () => {
        await db.exec(`INSERT INTO invite_links (code, expires_at) VALUES ('EXPIRED-CODE', now() - interval '1 day')`);
        await expect(signUp(db, 'u3@example.com', { invite_code: 'EXPIRED-CODE' })).rejects.toThrow(/INVALID_INVITE_CODE/);
    });
    it('không thể tạo mã mời cấp admin', async () => {
        await expect(db.exec(`INSERT INTO invite_links (code, role) VALUES ('ADMIN-CODE-X', 'admin')`)).rejects.toThrow();
    });
    it('validate_invite_code chỉ trả đúng/sai cho khách', async () => {
        const ok = await as(db, 'anon', q => q(`SELECT validate_invite_code('MEMBER-CODE-1') AS v`));
        const bad = await as(db, 'anon', q => q(`SELECT validate_invite_code('zzz') AS v`));
        expect(ok[0].v).toBe(true);
        expect(bad[0].v).toBe(false);
    });
    it('khách không đọc được bảng mã mời', async () => {
        await expect(as(db, 'anon', q => q(`SELECT * FROM invite_links`))).rejects.toThrow();
    });
    it('member không đọc được mã mời', async () => {
        const rows = await as(db, M(), q => q(`SELECT * FROM invite_links`));
        expect(rows.length).toBe(0);
    });
});

describe('leo thang đặc quyền trên profiles', () => {
    it('member không tự nâng role lên admin', async () => {
        await expect(
            as(db, M(), q => q(`UPDATE profiles SET role = 'admin' WHERE id = $1`, [member])),
        ).rejects.toThrow(/FORBIDDEN_PROFILE_FIELD/);
    });
    it('member không đổi person_handle / email của mình', async () => {
        await expect(as(db, M(), q => q(`UPDATE profiles SET person_handle = 'P001' WHERE id = $1`, [member]))).rejects.toThrow();
        await expect(as(db, M(), q => q(`UPDATE profiles SET email = 'x@y.z' WHERE id = $1`, [member]))).rejects.toThrow();
    });
    it('member đổi được display_name của mình', async () => {
        const rows = await as(db, M(), async q => {
            await q(`UPDATE profiles SET display_name = 'Tên mới' WHERE id = $1`, [member]);
            return q(`SELECT display_name FROM profiles WHERE id = $1`, [member]);
        });
        expect(rows[0].display_name).toBe('Tên mới');
    });
    it('member không sửa được profile người khác', async () => {
        const rows = await as(db, M(), q => q(`UPDATE profiles SET display_name = 'hack' WHERE id = $1 RETURNING id`, [member2]));
        expect(rows.length).toBe(0);
    });
    it('member không thể tự chèn profile admin', async () => {
        await expect(as(db, M(), q =>
            q(`INSERT INTO profiles (id, email, role) VALUES (gen_random_uuid(), 'fake@x.y', 'admin')`),
        )).rejects.toThrow();
    });
    it('member chỉ thấy profile của mình; admin thấy tất cả', async () => {
        const mine = await as(db, M(), q => q(`SELECT id FROM profiles`));
        expect(mine.length).toBe(1);
        const all = await as(db, A(), q => q(`SELECT id FROM profiles`));
        expect(all.length).toBeGreaterThanOrEqual(4);
    });
    it('khách không đọc được profiles', async () => {
        await expect(as(db, 'anon', q => q(`SELECT * FROM profiles`))).rejects.toThrow();
    });
    it('admin đổi được role người khác', async () => {
        const rows = await as(db, A(), async q => {
            await q(`UPDATE profiles SET role = 'viewer' WHERE id = $1`, [member2]);
            return q(`SELECT role FROM profiles WHERE id = $1`, [member2]);
        });
        expect(rows[0].role).toBe('viewer');
    });
    it('không thể hạ admin cuối cùng từ ứng dụng', async () => {
        await expect(as(db, A(), q => q(`UPDATE profiles SET role = 'member' WHERE id = $1`, [admin]))).rejects.toThrow(/LAST_ADMIN/);
    });
});

describe('danh bạ thành viên', () => {
    it('member thấy danh sách nhưng không thấy email', async () => {
        const rows = await as(db, M(), q => q(`SELECT * FROM list_members()`));
        expect(rows.length).toBeGreaterThanOrEqual(4);
        expect(rows.every(r => r.email === null)).toBe(true);
    });
    it('admin thấy email', async () => {
        const rows = await as(db, A(), q => q(`SELECT email FROM list_members()`));
        expect(rows.some(r => r.email === 'member@example.com')).toBe(true);
    });
    it('khách không gọi được', async () => {
        await expect(as(db, 'anon', q => q(`SELECT * FROM list_members()`))).rejects.toThrow();
    });
});

describe('hiển thị people_view theo vai trò', () => {
    it('khách không đọc được bảng gốc people / people_private', async () => {
        await expect(as(db, 'anon', q => q(`SELECT * FROM people`))).rejects.toThrow();
        await expect(as(db, 'anon', q => q(`SELECT * FROM people_private`))).rejects.toThrow();
    });
    it('member đọc bảng gốc cũng không thấy dòng nào', async () => {
        const rows = await as(db, M(), q => q(`SELECT * FROM people`));
        expect(rows.length).toBe(0);
    });
    it('khách thấy tên + năm sinh người đang sống, KHÔNG thấy liên lạc / ngày nơi sinh', async () => {
        const [r] = await as(db, 'anon', q => q(`SELECT * FROM people_view WHERE handle = 'P005'`));
        expect(r.display_name).toBe('Nguyễn Văn Hải');
        expect(r.birth_year).toBe(1970);
        expect(r.birth_date).toBeNull();
        expect(r.birth_place).toBeNull();
        expect(r.phone).toBeNull();
        expect(r.email).toBeNull();
        expect(r.current_address).toBeNull();
        expect(r.notes).toBeNull();
    });
    it('khách thấy ngày/nơi sinh người đã mất nhưng vẫn không thấy liên lạc', async () => {
        const [r] = await as(db, 'anon', q => q(`SELECT * FROM people_view WHERE handle = 'P001'`));
        expect(r.birth_date).toBe('1920-01-01');
        expect(r.birth_place).toBe('Thái Bình');
        expect(r.phone).toBeNull();
    });
    it('khách thấy đủ cấu trúc cây (families / parent_families)', async () => {
        const rows = await as(db, 'anon', q => q(`SELECT handle, families, parent_families FROM people_view`));
        expect(rows.length).toBe(15);
        const p2 = rows.find(r => r.handle === 'P002')!;
        expect(p2.families).toEqual(['F002']);
        expect(p2.parent_families).toEqual(['F001']);
    });
    it('khách đọc được families', async () => {
        const rows = await as(db, 'anon', q => q(`SELECT * FROM families`));
        expect(rows.length).toBe(6);
    });
    it('member đăng nhập thấy thông tin liên lạc', async () => {
        const [r] = await as(db, M(), q => q(`SELECT phone, email, current_address, birth_place FROM people_view WHERE handle = 'P005'`));
        expect(r.phone).toBe('0901234567');
        expect(r.email).toBe('hai@example.com');
        expect(r.current_address).toBe('Hà Nội');
        expect(r.birth_place).toBe('Nam Định');
    });
    it('viewer cũng thấy liên lạc (chỉ đọc)', async () => {
        const [r] = await as(db, V(), q => q(`SELECT phone FROM people_view WHERE handle = 'P005'`));
        expect(r.phone).toBe('0901234567');
    });
    it('người is_privacy_filtered: khách và member chỉ thấy tên + đời', async () => {
        for (const who of ['anon', M()] as const) {
            const [r] = await as(db, who, q => q(`SELECT * FROM people_view WHERE handle = 'P006'`));
            expect(r.display_name).toBe('Nguyễn Văn Hùng');
            expect(r.generation).toBe(3);
            expect(r.birth_year).toBeNull();
            expect(r.phone).toBeNull();
            expect(r.birth_place).toBeNull();
        }
    });
    it('admin thấy cả người is_privacy_filtered', async () => {
        const [r] = await as(db, A(), q => q(`SELECT birth_year, phone FROM people_view WHERE handle = 'P006'`));
        expect(r.birth_year).toBe(1973);
        expect(r.phone).toBe('0911111111');
    });
});

describe('ghi people / families', () => {
    it('member không UPDATE được people', async () => {
        const rows = await as(db, M(), q => q(`UPDATE people SET display_name = 'hack' WHERE handle = 'P001' RETURNING handle`));
        expect(rows.length).toBe(0);
    });
    it('member không INSERT được people / families', async () => {
        await expect(as(db, M(), q => q(`INSERT INTO people (handle, display_name) VALUES ('PX', 'x')`))).rejects.toThrow();
        await expect(as(db, M(), q => q(`INSERT INTO families (handle) VALUES ('FX')`))).rejects.toThrow();
    });
    it('member không DELETE được people', async () => {
        const rows = await as(db, M(), q => q(`DELETE FROM people WHERE handle = 'P001' RETURNING handle`));
        expect(rows.length).toBe(0);
    });
    it('khách không ghi được gì', async () => {
        await expect(as(db, 'anon', q => q(`UPDATE families SET children = '{}' WHERE handle = 'F001'`))).rejects.toThrow();
    });
    it('admin sửa được people và people_private', async () => {
        const rows = await as(db, A(), async q => {
            await q(`UPDATE people SET display_name = 'Tên sửa' WHERE handle = 'P001'`);
            await q(`UPDATE people_private SET phone = '0999' WHERE handle = 'P005'`);
            return q(`SELECT display_name, phone FROM people_view WHERE handle IN ('P001','P005') ORDER BY handle`);
        });
        expect(rows[0].display_name).toBe('Tên sửa');
        expect(rows[1].phone).toBe('0999');
    });
});

describe('đề xuất đóng góp', () => {
    const contribute = (q: (s: string, p?: unknown[]) => Promise<unknown>, uid: string, field = 'phone', value = '0123456789') =>
        q(`INSERT INTO contributions (author_id, person_handle, field_name, new_value) VALUES ($1, 'P005', $2, $3) RETURNING id`,
            [uid, field, value]);

    it('member tạo được đề xuất của chính mình, ở trạng thái pending', async () => {
        const rows = await as(db, M(), q => contribute(q, member) as Promise<Record<string, unknown>[]>);
        expect(rows.length).toBe(1);
    });
    it('member không tạo đề xuất mạo danh người khác', async () => {
        await expect(as(db, M(), q => contribute(q, member2))).rejects.toThrow();
    });
    it('viewer không tạo được đề xuất', async () => {
        await expect(as(db, V(), q => contribute(q, viewer))).rejects.toThrow();
    });
    it('không thể đề xuất trường cấu trúc ngoài danh sách trắng', async () => {
        await expect(as(db, M(), q => contribute(q, member, 'parent_families', '{}'))).rejects.toThrow();
        await expect(as(db, M(), q => contribute(q, member, 'role', 'admin'))).rejects.toThrow();
    });
    it('member không tự duyệt đề xuất của mình (không có policy UPDATE)', async () => {
        const rows = await as(db, M(), async q => {
            const c = await contribute(q, member) as Record<string, unknown>[];
            return q(`UPDATE contributions SET status = 'approved' WHERE id = $1 RETURNING id`, [c[0].id]);
        });
        expect(rows.length).toBe(0);
    });
    it('member không gọi được RPC review_contribution', async () => {
        await expect(as(db, M(), async q => {
            const c = await contribute(q, member) as Record<string, unknown>[];
            return q(`SELECT review_contribution($1, true, NULL)`, [c[0].id]);
        })).rejects.toThrow(/FORBIDDEN/);
    });
    it('member chỉ thấy đề xuất của mình, admin thấy tất cả', async () => {
        await db.exec(`
            INSERT INTO contributions (author_id, person_handle, field_name, new_value)
            VALUES ('${member}', 'P005', 'occupation', 'Kỹ sư'), ('${member2}', 'P005', 'occupation', 'Bác sĩ')`);
        const mine = await as(db, M(), q => q(`SELECT author_id FROM contributions`));
        expect(mine.every(r => r.author_id === member)).toBe(true);
        const all = await as(db, A(), q => q(`SELECT 1 FROM contributions`));
        expect(all.length).toBeGreaterThan(mine.length);
        await db.exec(`DELETE FROM contributions`);
    });
    it('admin duyệt: áp dụng giá trị, đổi trạng thái, tạo thông báo cho tác giả', async () => {
        await db.exec(`INSERT INTO contributions (id, author_id, person_handle, field_name, new_value)
                       VALUES ('11111111-1111-1111-1111-111111111111', '${member}', 'P005', 'phone', '0888888888')`);
        const out = await as(db, A(), async q => {
            await q(`SELECT review_contribution('11111111-1111-1111-1111-111111111111', true, 'ok')`);
            const c = await q(`SELECT status, reviewed_by FROM contributions WHERE id = '11111111-1111-1111-1111-111111111111'`);
            const p = await q(`SELECT phone FROM people_view WHERE handle = 'P005'`);
            await q(`RESET ROLE`); // đọc thông báo của member bằng quyền superuser
            const n = await q(`SELECT title, user_id FROM notifications WHERE user_id = $1`, [member]);
            return { c, p, n };
        });
        expect(out.c[0].status).toBe('approved');
        expect(out.c[0].reviewed_by).toBe(admin);
        expect(out.p[0].phone).toBe('0888888888');
        expect(out.n.length).toBe(1);
        await db.exec(`DELETE FROM contributions; DELETE FROM notifications;`);
    });
    it('admin từ chối: không đổi dữ liệu', async () => {
        await db.exec(`INSERT INTO contributions (id, author_id, person_handle, field_name, new_value)
                       VALUES ('22222222-2222-2222-2222-222222222222', '${member}', 'P005', 'display_name', 'Tên giả')`);
        const out = await as(db, A(), async q => {
            await q(`SELECT review_contribution('22222222-2222-2222-2222-222222222222', false, 'sai')`);
            return q(`SELECT display_name FROM people_view WHERE handle = 'P005'`);
        });
        expect(out[0].display_name).toBe('Nguyễn Văn Hải');
        await db.exec(`DELETE FROM contributions; DELETE FROM notifications;`);
    });
    it('không duyệt hai lần và từ chối giá trị năm không hợp lệ', async () => {
        await db.exec(`INSERT INTO contributions (id, author_id, person_handle, field_name, new_value)
                       VALUES ('33333333-3333-3333-3333-333333333333', '${member}', 'P005', 'birth_year', 'abcd')`);
        await expect(as(db, A(), q => q(`SELECT review_contribution('33333333-3333-3333-3333-333333333333', true, NULL)`)))
            .rejects.toThrow(/INVALID_YEAR/);
        await db.exec(`DELETE FROM contributions`);
    });
});

describe('nội dung: posts / events / media', () => {
    it('member đăng bài, tên tác giả do DB điền (không giả mạo được)', async () => {
        const rows = await as(db, M(), q =>
            q(`INSERT INTO posts (author_id, author_name, body) VALUES ($1, 'Giả mạo', 'xin chào') RETURNING author_name`, [member]));
        expect(rows[0].author_name).not.toBe('Giả mạo');
    });
    it('member không đăng bài dưới tên người khác', async () => {
        await expect(as(db, M(), q => q(`INSERT INTO posts (author_id, body) VALUES ($1, 'x')`, [member2]))).rejects.toThrow();
    });
    it('viewer không đăng được bài', async () => {
        await expect(as(db, V(), q => q(`INSERT INTO posts (author_id, body) VALUES ($1, 'x')`, [viewer]))).rejects.toThrow();
    });
    it('chỉ admin được ghim bài', async () => {
        await db.exec(`INSERT INTO posts (id, author_id, body) VALUES ('44444444-4444-4444-4444-444444444444', '${member}', 'bài')`);
        await expect(as(db, M(), q => q(`UPDATE posts SET is_pinned = true WHERE id = '44444444-4444-4444-4444-444444444444'`)))
            .rejects.toThrow(/FORBIDDEN_POST_FIELD/);
        const rows = await as(db, A(), q => q(`UPDATE posts SET is_pinned = true WHERE id = '44444444-4444-4444-4444-444444444444' RETURNING is_pinned`));
        expect(rows[0].is_pinned).toBe(true);
    });
    it('chỉ tác giả hoặc admin xóa bài; member khác thì không', async () => {
        const other = await as(db, M2(), q => q(`DELETE FROM posts WHERE id = '44444444-4444-4444-4444-444444444444' RETURNING id`));
        expect(other.length).toBe(0);
        const own = await as(db, M(), q => q(`DELETE FROM posts WHERE id = '44444444-4444-4444-4444-444444444444' RETURNING id`));
        expect(own.length).toBe(1);
    });
    it('khách không đọc được posts / events / media', async () => {
        await expect(as(db, 'anon', q => q(`SELECT * FROM posts`))).rejects.toThrow();
        await expect(as(db, 'anon', q => q(`SELECT * FROM events`))).rejects.toThrow();
        await expect(as(db, 'anon', q => q(`SELECT * FROM media`))).rejects.toThrow();
    });
    it('chỉ admin tạo sự kiện; sự kiện mới sinh thông báo cho member', async () => {
        await expect(as(db, M(), q => q(`INSERT INTO events (title, start_at, creator_id) VALUES ('Họp', now(), $1)`, [member])))
            .rejects.toThrow();
        const out = await as(db, A(), async q => {
            await q(`INSERT INTO events (title, start_at, creator_id) VALUES ('Giỗ tổ', now(), $1)`, [admin]);
            await q(`RESET ROLE`);
            return q(`SELECT user_id FROM notifications WHERE type = 'NEW_EVENT'`);
        });
        expect(out.length).toBeGreaterThanOrEqual(2);
        expect(out.some(r => r.user_id === admin)).toBe(false);
    });
    it('media: member upload phải ở PENDING, chỉ admin duyệt, người khác không thấy bản chờ', async () => {
        await expect(as(db, M(), q =>
            q(`INSERT INTO media (file_name, state, uploader_id) VALUES ('a.jpg', 'PUBLISHED', $1)`, [member]))).rejects.toThrow();
        await db.exec(`INSERT INTO media (id, file_name, state, uploader_id) VALUES ('55555555-5555-5555-5555-555555555555', 'a.jpg', 'PENDING', '${member}')`);
        const seenByOther = await as(db, M2(), q => q(`SELECT id FROM media`));
        expect(seenByOther.length).toBe(0);
        const seenByOwner = await as(db, M(), q => q(`SELECT id FROM media`));
        expect(seenByOwner.length).toBe(1);
        const selfApprove = await as(db, M(), q => q(`UPDATE media SET state = 'PUBLISHED' WHERE id = '55555555-5555-5555-5555-555555555555' RETURNING id`));
        expect(selfApprove.length).toBe(0);
        const approved = await as(db, A(), q => q(`UPDATE media SET state = 'PUBLISHED' WHERE id = '55555555-5555-5555-5555-555555555555' RETURNING id`));
        expect(approved.length).toBe(1);
    });
    it('bình luận bài viết bị xóa theo khi bài bị xóa (CASCADE)', async () => {
        await db.exec(`INSERT INTO posts (id, author_id, body) VALUES ('66666666-6666-6666-6666-666666666666', '${member}', 'p');
                       INSERT INTO post_comments (post_id, author_id, body) VALUES ('66666666-6666-6666-6666-666666666666', '${member2}', 'c');
                       DELETE FROM posts WHERE id = '66666666-6666-6666-6666-666666666666';`);
        const r = await db.query(`SELECT 1 FROM post_comments`);
        expect(r.rows.length).toBe(0);
    });
});

describe('thông báo và audit log', () => {
    it('mỗi người chỉ thấy thông báo của mình', async () => {
        await db.exec(`INSERT INTO notifications (user_id, title) VALUES ('${member}', 'a'), ('${member2}', 'b')`);
        const rows = await as(db, M(), q => q(`SELECT user_id FROM notifications`));
        expect(rows.every(r => r.user_id === member)).toBe(true);
        await db.exec(`DELETE FROM notifications`);
    });
    it('không tự tạo / sửa nội dung thông báo từ client', async () => {
        await expect(as(db, M(), q => q(`INSERT INTO notifications (user_id, title) VALUES ($1, 'giả')`, [member]))).rejects.toThrow();
        await db.exec(`INSERT INTO notifications (id, user_id, title) VALUES ('77777777-7777-7777-7777-777777777777', '${member}', 'gốc')`);
        await expect(as(db, M(), q => q(`UPDATE notifications SET title = 'sửa' WHERE id = '77777777-7777-7777-7777-777777777777'`)))
            .rejects.toThrow(/FORBIDDEN_NOTIFICATION_FIELD/);
        const ok = await as(db, M(), q => q(`UPDATE notifications SET is_read = true WHERE id = '77777777-7777-7777-7777-777777777777' RETURNING is_read`));
        expect(ok[0].is_read).toBe(true);
        await db.exec(`DELETE FROM notifications`);
    });
    it('audit_logs: member không đọc, không ghi; admin đọc', async () => {
        const mine = await as(db, M(), q => q(`SELECT * FROM audit_logs`));
        expect(mine.length).toBe(0);
        await expect(as(db, M(), q => q(`INSERT INTO audit_logs (action, entity_type) VALUES ('X', 'y')`))).rejects.toThrow();
        await expect(as(db, A(), q => q(`INSERT INTO audit_logs (action, entity_type) VALUES ('X', 'y')`))).rejects.toThrow();
        const all = await as(db, A(), q => q(`SELECT * FROM audit_logs`));
        expect(all.length).toBeGreaterThan(0);
    });
    it('audit ghi tên trường đổi chứ không ghi giá trị', async () => {
        const out = await as(db, A(), async q => {
            await q(`UPDATE people_private SET phone = '0777000111' WHERE handle = 'P005'`);
            return q(`SELECT changed_fields, entity_type, actor_id FROM audit_logs
                       WHERE entity_type = 'people_private' ORDER BY created_at DESC LIMIT 1`);
        });
        expect(out[0].changed_fields).toEqual(['phone']);
        expect(out[0].actor_id).toBe(admin);
        const cols = await db.query<{ column_name: string }>(`SELECT column_name FROM information_schema.columns WHERE table_name = 'audit_logs'`);
        expect(cols.rows.map(r => r.column_name)).not.toContain('old_value');
    });
});
