'use client';

import { useState } from 'react';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { TreePine, Eye, EyeOff, LogIn } from 'lucide-react';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { z } from 'zod';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { useAuth } from '@/components/auth-provider';

const loginSchema = z.object({
    email: z.string().email('Email không hợp lệ'),
    password: z.string().min(6, 'Mật khẩu tối thiểu 6 ký tự'),
});

type LoginForm = z.infer<typeof loginSchema>;

export default function LoginPage() {
    const router = useRouter();
    const { signIn } = useAuth();
    const [showPassword, setShowPassword] = useState(false);
    const [error, setError] = useState('');
    const [loading, setLoading] = useState(false);

    const {
        register,
        handleSubmit,
        formState: { errors },
    } = useForm<LoginForm>({ resolver: zodResolver(loginSchema) });

    const onSubmit = async (data: LoginForm) => {
        setError('');
        setLoading(true);

        try {
            const result = await signIn(data.email, data.password);
            if (result.error) {
                setError(result.error);
            } else {
                router.push('/tree');
            }
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
                <CardTitle className="text-2xl font-bold">Gia phả họ Lê</CardTitle>
                <CardDescription>
                    Đăng nhập để quản lý & đóng góp thông tin
                </CardDescription>
            </CardHeader>
            <CardContent>
                <form onSubmit={handleSubmit(onSubmit)} className="space-y-4">
                    {error && (
                        <div className="rounded-md bg-destructive/10 p-3 text-sm text-destructive">{error}</div>
                    )}
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
                                placeholder="••••••••"
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

                    <Button type="submit" className="w-full" disabled={loading}>
                        {loading ? 'Đang đăng nhập...' : <><LogIn className="h-4 w-4 mr-2" /> Đăng nhập</>}
                    </Button>

                    <p className="text-center text-xs text-muted-foreground">
                        Chưa có tài khoản? Đăng ký cần mã mời từ quản trị viên —{' '}
                        <Link href="/register" className="underline">nhập mã mời</Link>
                    </p>
                </form>
            </CardContent>
        </Card>
    );
}
