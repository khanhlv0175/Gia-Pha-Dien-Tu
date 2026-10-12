'use client';

import { ThemeProvider as NextThemesProvider } from 'next-themes';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { useState } from 'react';
import { AuthProvider } from '@/components/auth-provider';
import { isDemoMode, isSupabaseConfigured } from '@/lib/supabase';

export function Providers({ children }: { children: React.ReactNode }) {
    const [queryClient] = useState(
        () =>
            new QueryClient({
                defaultOptions: {
                    queries: {
                        staleTime: 60 * 1000,
                        retry: 1,
                    },
                },
            }),
    );

    // Thiếu cấu hình (và không ở chế độ demo): báo rõ nguyên nhân thay vì để app sập.
    if (!isSupabaseConfigured && !isDemoMode) {
        return (
            <div className="flex min-h-screen items-center justify-center p-6">
                <div className="max-w-lg space-y-3 rounded-lg border border-destructive/40 bg-destructive/5 p-6">
                    <h1 className="text-lg font-semibold text-destructive">Chưa cấu hình Supabase</h1>
                    <p className="text-sm">
                        Đặt <code>NEXT_PUBLIC_SUPABASE_URL</code> và <code>NEXT_PUBLIC_SUPABASE_ANON_KEY</code> trong
                        <code> .env.local</code> (xem <code>.env.local.example</code>), rồi khởi động lại.
                    </p>
                    <p className="text-sm text-muted-foreground">
                        Muốn chạy thử bằng dữ liệu mẫu: đặt <code>NEXT_PUBLIC_DEMO_MODE=true</code>.
                    </p>
                </div>
            </div>
        );
    }

    return (
        <QueryClientProvider client={queryClient}>
            <NextThemesProvider attribute="class" defaultTheme="light" enableSystem disableTransitionOnChange>
                <AuthProvider>{children}</AuthProvider>
            </NextThemesProvider>
        </QueryClientProvider>
    );
}

