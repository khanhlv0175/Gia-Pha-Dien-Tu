'use client';

import { createContext, useContext, useEffect, useState, useCallback, type ReactNode } from 'react';
import { supabase } from '@/lib/supabase';
import type { User, Session } from '@supabase/supabase-js';

export type UserRole = 'admin' | 'member' | 'viewer' | null;

interface Profile {
    id: string;
    email: string;
    display_name: string | null;
    role: UserRole;
    person_handle: string | null;
    avatar_url: string | null;
}

interface AuthState {
    user: User | null;
    session: Session | null;
    profile: Profile | null;
    role: UserRole;
    loading: boolean;
    isAdmin: boolean;
    /** member hoặc admin: được đăng bài, bình luận, đề xuất chỉnh sửa */
    isMember: boolean;
    isLoggedIn: boolean;
    signIn: (email: string, password: string) => Promise<{ error?: string }>;
    signOut: () => Promise<void>;
    refreshProfile: () => Promise<void>;
}

const AuthContext = createContext<AuthState | null>(null);

export function AuthProvider({ children }: { children: ReactNode }) {
    const [user, setUser] = useState<User | null>(null);
    const [session, setSession] = useState<Session | null>(null);
    const [profile, setProfile] = useState<Profile | null>(null);
    const [loading, setLoading] = useState(true);

    // Profile do trigger DB tạo khi đăng ký bằng mã mời; client chỉ đọc.
    const fetchProfile = useCallback(async (userId: string) => {
        try {
            const { data, error } = await supabase
                .from('profiles')
                .select('id, email, display_name, role, person_handle, avatar_url')
                .eq('id', userId)
                .maybeSingle();
            if (!error && data) {
                setProfile(data as Profile);
            } else {
                setProfile(null);
            }
        } catch {
            setProfile(null);
        }
    }, []);

    useEffect(() => {
        supabase.auth.getSession().then(({ data: { session: s } }) => {
            setSession(s);
            setUser(s?.user ?? null);
            if (s?.user) fetchProfile(s.user.id);
            setLoading(false);
        });

        const { data: { subscription } } = supabase.auth.onAuthStateChange((_event, s) => {
            setSession(s);
            setUser(s?.user ?? null);
            if (s?.user) {
                fetchProfile(s.user.id);
            } else {
                setProfile(null);
            }
        });

        return () => subscription.unsubscribe();
    }, [fetchProfile]);

    const signIn = useCallback(async (email: string, password: string) => {
        const { error } = await supabase.auth.signInWithPassword({ email, password });
        if (error) {
            if (error.message.includes('Invalid login credentials')) {
                return { error: 'Email hoặc mật khẩu không đúng' };
            }
            return { error: error.message };
        }
        return {};
    }, []);

    const signOut = useCallback(async () => {
        await supabase.auth.signOut();
        setProfile(null);
    }, []);

    const refreshProfile = useCallback(async () => {
        if (user) await fetchProfile(user.id);
    }, [user, fetchProfile]);

    const role = profile?.role ?? null;

    return (
        <AuthContext.Provider value={{
            user, session, profile, role, loading,
            isAdmin: role === 'admin',
            isMember: role === 'member' || role === 'admin',
            isLoggedIn: !!user,
            signIn, signOut, refreshProfile,
        }}>
            {children}
        </AuthContext.Provider>
    );
}

export function useAuth() {
    const ctx = useContext(AuthContext);
    if (!ctx) throw new Error('useAuth must be used within AuthProvider');
    return ctx;
}
