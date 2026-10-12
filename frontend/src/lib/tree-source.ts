/**
 * Nguồn dữ liệu cho cây / sách gia phả.
 *
 * - Mặc định: đọc Supabase; lỗi thì NÉM LỖI để UI báo cho người dùng
 *   (không âm thầm hiển thị dữ liệu giả).
 * - Chỉ khi NEXT_PUBLIC_DEMO_MODE=true và không có dữ liệu thật mới dùng dữ liệu mẫu.
 */
import { fetchTreeData } from './supabase-data';
import { isDemoMode, isSupabaseConfigured } from './supabase';
import { getMockTreeData } from './mock-data';
import type { TreeNode, TreeFamily } from './tree-layout';

export interface LoadedTree {
    people: TreeNode[];
    families: TreeFamily[];
    /** true khi đang hiển thị dữ liệu mẫu (chế độ demo) */
    demo: boolean;
}

export async function loadTreeData(): Promise<LoadedTree> {
    if (isDemoMode && !isSupabaseConfigured) {
        return { ...getMockTreeData(), demo: true };
    }
    const data = await fetchTreeData();
    if (isDemoMode && data.people.length === 0) {
        return { ...getMockTreeData(), demo: true };
    }
    return { ...data, demo: false };
}
