#!/usr/bin/env node
// Ghép supabase/migrations/*.sql (+ seed.sql) thành supabase/database-setup.sql
// để dán một lần vào Supabase SQL Editor.
//   node scripts/bundle-db.mjs            # kèm dữ liệu mẫu
//   node scripts/bundle-db.mjs --no-seed  # chỉ schema, dùng cho dữ liệu thật
import { readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..', 'supabase');
const withSeed = !process.argv.includes('--no-seed');

const parts = [
    '-- ============================================================',
    '-- 🌳 Gia Phả Điện Tử — Database Setup (FILE SINH TỰ ĐỘNG)',
    '-- Sinh bởi: npm run db:bundle — KHÔNG sửa tay, hãy sửa trong supabase/migrations/',
    withSeed ? '-- Bao gồm dữ liệu mẫu demo (xóa bằng: npm run db:bundle -- --no-seed)' : '-- Không bao gồm dữ liệu mẫu',
    '-- Chạy trên project Supabase MỚI (schema trống).',
    '-- ============================================================',
];

for (const f of readdirSync(join(root, 'migrations')).filter(f => f.endsWith('.sql')).sort()) {
    parts.push(`\n-- ───── migrations/${f} ─────\n`, readFileSync(join(root, 'migrations', f), 'utf-8').trim());
}
if (withSeed) {
    parts.push('\n-- ───── seed.sql ─────\n', readFileSync(join(root, 'seed.sql'), 'utf-8').trim());
}
parts.push("\nSELECT '✅ Database setup complete!' AS status;\n");

writeFileSync(join(root, 'database-setup.sql'), parts.join('\n') + '\n');
console.log(`Wrote supabase/database-setup.sql (${withSeed ? 'with' : 'without'} seed)`);
