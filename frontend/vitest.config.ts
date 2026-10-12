import { defineConfig } from 'vitest/config';

export default defineConfig({
    test: {
        include: ['supabase/tests/**/*.test.ts'],
        testTimeout: 30000,
        hookTimeout: 60000,
    },
});
