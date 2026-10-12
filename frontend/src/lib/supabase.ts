import { createClient, type SupabaseClient } from '@supabase/supabase-js';

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL || '';
const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || '';

/**
 * Chế độ demo: chạy không cần Supabase, dùng dữ liệu mẫu trong mock-data.ts.
 * Chỉ bật khi đặt NEXT_PUBLIC_DEMO_MODE=true. Mặc định TẮT — khi tắt mà thiếu
 * cấu hình Supabase thì báo lỗi rõ ràng thay vì âm thầm hiển thị dữ liệu giả.
 */
export const isDemoMode = process.env.NEXT_PUBLIC_DEMO_MODE === 'true';

export const isSupabaseConfigured = Boolean(supabaseUrl && supabaseAnonKey);

const CONFIG_ERROR =
    'Thiếu cấu hình Supabase: đặt NEXT_PUBLIC_SUPABASE_URL và NEXT_PUBLIC_SUPABASE_ANON_KEY ' +
    '(hoặc NEXT_PUBLIC_DEMO_MODE=true để chạy bằng dữ liệu mẫu).';

/** Client rỗng cho chế độ demo: mọi truy vấn trả về không có dữ liệu. */
function createDemoClient(): SupabaseClient {
    const result = { data: [], error: null, count: 0 };
    const query: unknown = new Proxy(function () { }, {
        get(_t, prop) {
            if (prop === 'then') return (resolve: (v: unknown) => unknown) => resolve(result);
            if (prop === 'single' || prop === 'maybeSingle') return () => Promise.resolve({ data: null, error: null });
            return query;
        },
        apply() { return query; },
    });
    const auth = {
        getSession: () => Promise.resolve({ data: { session: null } }),
        onAuthStateChange: () => ({ data: { subscription: { unsubscribe: () => { } } } }),
        signInWithPassword: () => Promise.resolve({ error: { message: 'Chế độ demo: chưa kết nối Supabase' } }),
        signUp: () => Promise.resolve({ error: { message: 'Chế độ demo: chưa kết nối Supabase' } }),
        signOut: () => Promise.resolve({}),
    };
    return new Proxy({} as SupabaseClient, {
        get(_t, prop) {
            if (prop === 'auth') return auth;
            if (prop === 'rpc') return () => query;
            return () => query;
        },
    });
}

let _client: SupabaseClient | null = null;

function getClient(): SupabaseClient {
    if (_client) return _client;
    if (isSupabaseConfigured) {
        _client = createClient(supabaseUrl, supabaseAnonKey);
    } else if (isDemoMode) {
        _client = createDemoClient();
    } else {
        throw new Error(CONFIG_ERROR);
    }
    return _client;
}

// Truy cập chậm (lazy) để việc import không làm vỡ build khi chưa có biến môi trường.
export const supabase: SupabaseClient = new Proxy({} as SupabaseClient, {
    get(_target, prop) {
        return (getClient() as unknown as Record<string | symbol, unknown>)[prop];
    },
});

/** Client service-role cho tác vụ admin phía server. KHÔNG dùng trong code chạy ở browser. */
export function createServiceClient() {
    const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
    if (!serviceKey) throw new Error('SUPABASE_SERVICE_ROLE_KEY not set');
    return createClient(supabaseUrl, serviceKey);
}
