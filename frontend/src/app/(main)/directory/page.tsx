'use client';

import { useEffect, useState, useCallback } from 'react';
import { useRouter } from 'next/navigation';
import { Contact, Search, MapPin, GitBranch, User } from 'lucide-react';
import { Input } from '@/components/ui/input';
import { Card, CardContent } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { supabase } from '@/lib/supabase';

interface DirectoryMember {
    id: string;
    email: string | null; // chỉ admin mới nhận được email
    display_name: string | null;
    avatar_url: string | null;
    role: string;
    created_at: string;
}

export default function DirectoryPage() {
    const router = useRouter();
    const [members, setMembers] = useState<DirectoryMember[]>([]);
    const [loading, setLoading] = useState(true);
    const [search, setSearch] = useState('');

    const fetchMembers = useCallback(async () => {
        setLoading(true);
        try {
            const { data } = await supabase.rpc('list_members');
            if (data) setMembers(data as DirectoryMember[]);
        } catch { /* ignore */ }
        finally { setLoading(false); }
    }, []);

    useEffect(() => { fetchMembers(); }, [fetchMembers]);

    const filtered = members.filter(m =>
        (m.display_name || '').toLowerCase().includes(search.toLowerCase()) ||
        (m.email || '').toLowerCase().includes(search.toLowerCase())
    );

    const getRoleBadge = (role: string) => {
        const colors: Record<string, string> = {
            admin: 'bg-red-100 text-red-800',
            viewer: 'bg-slate-100 text-slate-800',
            member: 'bg-green-100 text-green-800',
        };
        return <Badge variant="secondary" className={colors[role] || ''}>{role.toUpperCase()}</Badge>;
    };

    return (
        <div className="space-y-6">
            <div>
                <h1 className="text-2xl font-bold tracking-tight flex items-center gap-2">
                    <Contact className="h-6 w-6" />
                    Danh bạ
                </h1>
                <p className="text-muted-foreground">Thành viên đã đăng ký</p>
            </div>

            <div className="relative max-w-sm">
                <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
                <Input placeholder="Tìm theo tên..." value={search} onChange={e => setSearch(e.target.value)} className="pl-9" />
            </div>

            {loading ? (
                <div className="flex items-center justify-center h-48">
                    <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-primary" />
                </div>
            ) : filtered.length === 0 ? (
                <Card>
                    <CardContent className="flex flex-col items-center justify-center py-12">
                        <Contact className="h-12 w-12 text-muted-foreground mb-4" />
                        <p className="text-muted-foreground">Chưa có thành viên nào</p>
                    </CardContent>
                </Card>
            ) : (
                <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
                    {filtered.map(m => (
                        <Card key={m.id} className="hover:shadow-md transition-shadow cursor-pointer" onClick={() => router.push(`/directory/${m.id}`)}>
                            <CardContent className="p-4">
                                <div className="flex items-center gap-3">
                                    <div className="h-10 w-10 rounded-full bg-primary/10 flex items-center justify-center">
                                        <User className="h-5 w-5 text-primary" />
                                    </div>
                                    <div className="flex-1 min-w-0">
                                        <p className="font-medium truncate">{m.display_name || m.email?.split('@')[0] || 'Thành viên'}</p>
                                        {m.email && <p className="text-xs text-muted-foreground truncate">{m.email}</p>}
                                    </div>
                                    {getRoleBadge(m.role)}
                                </div>
                            </CardContent>
                        </Card>
                    ))}
                </div>
            )}
        </div>
    );
}
