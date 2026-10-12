import { PGlite } from '@electric-sql/pglite';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';

const root = join(__dirname, '..');

export async function createDb(): Promise<PGlite> {
    const db = new PGlite();
    await db.exec(readFileSync(join(__dirname, 'auth-stub.sql'), 'utf-8'));
    const files = readdirSync(join(root, 'migrations')).filter(f => f.endsWith('.sql')).sort();
    for (const f of files) {
        await db.exec(readFileSync(join(root, 'migrations', f), 'utf-8'));
    }
    return db;
}

export async function seed(db: PGlite) {
    await db.exec(readFileSync(join(root, 'seed.sql'), 'utf-8'));
}

export type Who = { uid: string } | 'anon' | 'service';

/**
 * Chạy `fn` trong một transaction với role/JWT của `who`, luôn ROLLBACK.
 * Trả về kết quả hoặc ném lỗi của DB.
 */
export async function as<T>(db: PGlite, who: Who, fn: (q: Query) => Promise<T>): Promise<T> {
    await db.exec('BEGIN');
    try {
        if (who === 'anon') {
            await db.exec(`SET LOCAL ROLE anon`);
        } else if (who === 'service') {
            await db.exec(`SET LOCAL ROLE service_role`);
        } else {
            await db.exec(`SET LOCAL ROLE authenticated`);
            const claims = JSON.stringify({ sub: who.uid, role: 'authenticated' });
            await db.query(`SELECT set_config('request.jwt.claims', $1, true)`, [claims]);
        }
        return await fn((sql, params) => db.query(sql, params as unknown[]).then(r => r.rows as Record<string, unknown>[]));
    } finally {
        await db.exec('ROLLBACK');
    }
}

export type Query = (sql: string, params?: unknown[]) => Promise<Record<string, unknown>[]>;

/** Tạo user qua auth.users (kích hoạt trigger handle_new_user) với quyền superuser. */
export async function signUp(db: PGlite, email: string, meta: Record<string, unknown>) {
    const r = await db.query<{ id: string }>(
        `INSERT INTO auth.users (email, raw_user_meta_data) VALUES ($1, $2::jsonb) RETURNING id`,
        [email, JSON.stringify(meta)],
    );
    return r.rows[0].id;
}
