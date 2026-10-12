-- ============================================================
-- Dữ liệu mẫu demo — Họ Nguyễn Văn, 4 thế hệ, 15 thành viên
-- Chỉ chạy cho dev/demo. KHÔNG chạy trên dữ liệu thật.
-- ============================================================
INSERT INTO people (handle, display_name, gender, generation, birth_year, death_year, is_living, is_patrilineal, families, parent_families) VALUES
('P001', 'Nguyễn Văn An',    1, 1, 1920, 1995, false, true, '{"F001"}', '{}'),
('P002', 'Nguyễn Văn Bình',  1, 2, 1945, NULL, true,  true, '{"F002"}', '{"F001"}'),
('P003', 'Nguyễn Văn Cường', 1, 2, 1948, NULL, true,  true, '{"F003"}', '{"F001"}'),
('P004', 'Nguyễn Văn Dũng',  1, 2, 1951, 2020, false, true, '{"F004"}', '{"F001"}'),
('P005', 'Nguyễn Văn Hải',   1, 3, 1970, NULL, true,  true, '{"F005"}', '{"F002"}'),
('P006', 'Nguyễn Văn Hùng',  1, 3, 1973, NULL, true,  true, '{}',       '{"F002"}'),
('P007', 'Nguyễn Văn Khoa',  1, 3, 1975, NULL, true,  true, '{"F006"}', '{"F003"}'),
('P008', 'Nguyễn Văn Khánh', 1, 3, 1978, NULL, true,  true, '{}',       '{"F003"}'),
('P009', 'Nguyễn Văn Long',  1, 3, 1980, NULL, true,  true, '{}',       '{"F004"}'),
('P010', 'Nguyễn Văn Minh',  1, 4, 1995, NULL, true,  true, '{}',       '{"F005"}'),
('P011', 'Nguyễn Văn Nam',   1, 4, 1998, NULL, true,  true, '{}',       '{"F005"}'),
('P012', 'Nguyễn Văn Phúc',  1, 4, 2000, NULL, true,  true, '{}',       '{"F006"}'),
('P013', 'Trần Thị Lan',     2, 1, 1925, 2000, false, false, '{}', '{}'),
('P014', 'Lê Thị Mai',       2, 2, 1948, NULL, true,  false, '{}', '{}'),
('P015', 'Phạm Thị Hoa',     2, 3, 1972, NULL, true,  false, '{}', '{}')
ON CONFLICT (handle) DO NOTHING;

INSERT INTO families (handle, father_handle, mother_handle, children) VALUES
('F001', 'P001', 'P013', '{"P002","P003","P004"}'),
('F002', 'P002', 'P014', '{"P005","P006"}'),
('F003', 'P003', NULL,   '{"P007","P008"}'),
('F004', 'P004', NULL,   '{"P009"}'),
('F005', 'P005', 'P015', '{"P010","P011"}'),
('F006', 'P007', NULL,   '{"P012"}')
ON CONFLICT (handle) DO NOTHING;
