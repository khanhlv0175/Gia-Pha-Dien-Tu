import { describe, it, expect } from 'vitest';
import { PGlite } from '@electric-sql/pglite';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { execFileSync } from 'node:child_process';

describe('database-setup.sql', () => {
    it('được sinh từ migrations (chạy npm run db:bundle nếu test này đỏ) và chạy được trên DB trống', async () => {
        const root = join(__dirname, '..', '..');
        const file = join(root, 'supabase', 'database-setup.sql');
        const committed = readFileSync(file, 'utf-8');
        execFileSync('node', [join(root, 'scripts', 'bundle-db.mjs')], { cwd: root });
        const fresh = readFileSync(file, 'utf-8');
        expect(committed).toBe(fresh);

        const db = new PGlite();
        await db.exec(readFileSync(join(__dirname, 'auth-stub.sql'), 'utf-8'));
        await db.exec(fresh);
        const r = await db.query<{ n: number }>('SELECT count(*)::int AS n FROM people');
        expect(r.rows[0].n).toBe(15);
        await db.close();
    });
});
