'use client';

import { useState, Suspense } from 'react';
import { useRouter, useSearchParams } from 'next/navigation';
import { TreePine, Eye, EyeOff } from 'lucide-react';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { z } from 'zod';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { supabase } from '@/lib/supabase';

const registerSchema = z.object({
    email: z.string().email('Email không hợp lệ'),
    displayName: z.string().min(2, 'Tên tối thiểu 2 ký tự').max(100),
    password: z.string().min(8, 'Mật khẩu tối thiểu 8 ký tự'),
    confirmPassword: z.string(),
    inviteCode: z.string().min(6, 'Bạn cần có mã mời từ quản trị viên'),
}).refine((data) => data.password === data.confirmPassword, {
    message: 'Mật khẩu xác nhận không khớp',
    path: ['confirmPassword'],
});

type RegisterForm = z.infer<typeof registerSchema>;

function RegisterContent() {
    const router = useRouter();
    const searchParams = useSearchParams();
    const inviteCode = searchParams.get('code') || '';
    const [showPassword, setShowPassword] = useState(false);
    const [error, setError] = useState('');
    const [notice, setNotice] = useState('');
    const [loading, setLoading] = useState(false);

    const {
        register,
        handleSubmit,
        formState: { errors },
    } = useForm<RegisterForm>({
        resolver: zodResolver(registerSchema),
        defaultValues: { inviteCode },
    });

    const onSubmit = async (data: RegisterForm) => {
        const code = data.inviteCode.trim();
        try {
            setError('');
            setLoading(true);

            // Kiểm tra sớm để báo lỗi dễ hiểu; việc thực thi thật nằm ở trigger DB.
            const { data: valid, error: rpcErr } = await supabase.rpc('validate_invite_code', { p_code: code });
            if (rpcErr || !valid) {
                setError('Mã mời không hợp lệ, đã hết hạn hoặc đã hết lượt sử dụng');
                return;
            }

            // Vai trò và lượt dùng do DB xử lý trong trigger khi tạo tài khoản.
            const { data: authData, error: authErr } = await supabase.auth.signUp({
                email: data.email,
                password: data.password,
                options: {
                    data: { display_name: data.displayName, invite_code: code },
                },
            });

            if (authErr) {
                setError(
                    /database error|invite/i.test(authErr.message)
                        ? 'Mã mời không hợp lệ, đã hết hạn hoặc đã hết lượt sử dụng'
                        : authErr.message,
                );
                return;
            }

            if (authData.session) {
                router.push('/');
            } else {
                setNotice('Đã đăng ký! Kiểm tra email để xác nhận tài khoản, sau đó đăng nhập.');
            }
        } catch {
            setError('Đăng ký thất bại. Vui lòng thử lại.');
        } finally {
            setLoading(false);
        }
    };

    return (
        <Card className="border-0 shadow-2xl">
            <CardHeader className="text-center space-y-2">
                <div className="flex justify-center">
                    <div className="rounded-full bg-primary/10 p-3">
                        <TreePine className="h-8 w-8 text-primary" />
                    </div>
                </div>
                <CardTitle className="text-2xl font-bold">Tham gia Gia phả họ Lê</CardTitle>
                <CardDescription>Đăng ký tham gia nền tảng gia phả dòng họ</CardDescription>
            </CardHeader>
            <CardContent>
                <form onSubmit={handleSubmit(onSubmit)} className="space-y-4">
                    {notice && (
                        <div className="rounded-md bg-green-50 dark:bg-green-950/30 p-3 text-sm text-green-700 dark:text-green-400">{notice}</div>
                    )}

                    <div className="space-y-2">
                        <label className="text-sm font-medium" htmlFor="inviteCode">Mã mời</label>
                        <Input id="inviteCode" placeholder="Mã do quản trị viên cung cấp" {...register('inviteCode')} />
                        {errors.inviteCode && <p className="text-xs text-destructive">{errors.inviteCode.message}</p>}
                    </div>

                    {error && (
                        <div className="rounded-md bg-destructive/10 p-3 text-sm text-destructive">{error}</div>
                    )}

                    <div className="space-y-2">
                        <label className="text-sm font-medium" htmlFor="displayName">Tên hiển thị</label>
                        <Input id="displayName" placeholder="Nguyễn Văn A" {...register('displayName')} />
                        {errors.displayName && <p className="text-xs text-destructive">{errors.displayName.message}</p>}
                    </div>

                    <div className="space-y-2">
                        <label className="text-sm font-medium" htmlFor="email">Email</label>
                        <Input id="email" type="email" placeholder="email@example.com" {...register('email')} />
                        {errors.email && <p className="text-xs text-destructive">{errors.email.message}</p>}
                    </div>

                    <div className="space-y-2">
                        <label className="text-sm font-medium" htmlFor="password">Mật khẩu</label>
                        <div className="relative">
                            <Input
                                id="password"
                                type={showPassword ? 'text' : 'password'}
                                placeholder="Tối thiểu 8 ký tự"
                                {...register('password')}
                            />
                            <button
                                type="button"
                                className="absolute right-3 top-1/2 -translate-y-1/2 text-muted-foreground hover:text-foreground"
                                onClick={() => setShowPassword(!showPassword)}
                            >
                                {showPassword ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
                            </button>
                        </div>
                        {errors.password && <p className="text-xs text-destructive">{errors.password.message}</p>}
                    </div>

                    <div className="space-y-2">
                        <label className="text-sm font-medium" htmlFor="confirmPassword">Xác nhận mật khẩu</label>
                        <Input
                            id="confirmPassword"
                            type="password"
                            placeholder="Nhập lại mật khẩu"
                            {...register('confirmPassword')}
                        />
                        {errors.confirmPassword && <p className="text-xs text-destructive">{errors.confirmPassword.message}</p>}
                    </div>

                    <Button type="submit" className="w-full" disabled={loading}>
                        {loading ? 'Đang đăng ký...' : 'Đăng ký'}
                    </Button>
                </form>
            </CardContent>
        </Card>
    );
}

export default function RegisterPage() {
    return (
        <Suspense fallback={<div className="flex items-center justify-center h-48"><div className="animate-spin rounded-full h-8 w-8 border-b-2 border-primary" /></div>}>
            <RegisterContent />
        </Suspense>
    );
}
