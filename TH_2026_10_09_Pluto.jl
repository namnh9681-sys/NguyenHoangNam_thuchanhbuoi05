### A Pluto.jl notebook ###
# v0.20.0

# ╔═╡ 09102026-0000-4000-8000-000000000001
begin
    READ_DATA = true
    RUN_APP = true
    ROOT_DATA = joinpath(@__DIR__, "data")
end

# ╔═╡ 09102026-0000-4000-8000-000000000002
AppCore = let
    sandbox = Module(:ThucHanhNgay0910)
    Base.include(sandbox, joinpath(@__DIR__, "TH_2026_10_09_Sinh_vien.jl"))
    Base.invokelatest(getfield, sandbox, :GiaoDon)
end

# ╔═╡ 09102026-0000-4000-8000-000000000003
"""
# BÁO CÁO THỰC HÀNH: ĐIỀU PHỐI GIAO ĐƠN BẰNG JULIA (09/10/2026)

## 1. Bài toán và mô hình dữ liệu
- **Hệ thống**: Điều phối giao hàng độc lập từ kho (đỉnh 1) tới các điểm giao trên đồ thị campus rồi quay về kho.
- **Công thức chi phí**: `chi_phi = 2 * so_canh_BFS + thoi_gian_phuc_vu`.
- **Dữ liệu vào**:
  - `don_hang.csv`: gồm các đơn hàng (id, diem_giao, thoi_gian_phuc_vu, loi_ich).
  - `ban_do.csv`: 7 cạnh vô hướng kết nối 6 đỉnh trong campus.
- **Mục tiêu**: Chọn tập đơn tối ưu hóa tổng lợi ích trong phạm vi ngân sách thời gian `B = 8` (bộ MINI001).

## 2. Bốn thuật toán cốt lõi
1. **Merge Sort (`merge_sort`)**: Chia để trị, sắp xếp dãy ổn định với độ phức tạp `O(n log n)`. Dùng để sắp danh mục đơn theo ID tăng và sắp thứ tự ưu tiên (lợi ích / chi phí).
2. **Binary Search (`binary_search`)**: Tìm kiếm nhị phân trên danh mục đã sắp tăng theo ID trong `O(log n)`. Trả về `Order` hoặc `nothing`.
3. **BFS Đường đi ngắn nhất (`bfs_routes`)**: Tìm số cạnh ít nhất từ đỉnh nguồn 1 tới mọi đỉnh trong đồ thị không trọng số `O(V + E)`. Dùng `CircularQueue` (FIFO) để tính `distance`, `parent` và tái dựng `routes`.
4. **Quy hoạch động ba lô 0/1 (`knapsack`)**: Bảng `table[i+1, b+1]` lưu giá trị tối ưu với `i` đơn và ngân sách `b` trong `O(n * B)`. Truy vết tìm tập ID được chọn.
"""

# ╔═╡ 09102026-0000-4000-8000-000000000004
ho_so = AppCore.mini_profile()

# ╔═╡ 09102026-0000-4000-8000-000000000005
du_lieu = READ_DATA ? AppCore.read_data(joinpath(ROOT_DATA,"MINI001")) : nothing

# ╔═╡ 09102026-0000-4000-8000-000000000006
bao_cao = !RUN_APP || du_lieu === nothing ? nothing : let
    s = AppCore.build_session(du_lieu.orders,du_lieu.edges,ho_so)
    r = AppCore.plan!(s)
    trace = NamedTuple[]
    save(label) = push!(trace,(buoc=label,queue=AppCore.queue_values(s.pending),
                              stack=copy(s.completed),spent=s.spent,earned=s.earned))
    save("Sau lập kế hoạch")
    AppCore.deliver!(s); save("Sau giao một đơn")
    AppCore.undo!(s); save("Sau hoàn tác")
    while s.pending.count > 0
        AppCore.deliver!(s)
    end
    save("Sau giao hết")
    (chi_phi=copy(s.costs),tuyen=deepcopy(s.routes),chon=copy(s.selected_ids),
     loi_ich_toi_uu=r.optimal.value,truy_vet=trace,bat_bien=AppCore.check_invariants(s))
end

# ╔═╡ 09102026-0000-4000-8000-000000000007
"""
## 3. Giải thích bảng Quy hoạch động và Truy vết
- **Ý nghĩa ô bảng DP**:
  - `table[i+1, b+1]` đại diện cho `F(i, b)` — lợi ích lớn nhất khi xét tập con của `i` đơn đầu tiên với ngân sách thời gian tối đa `b`.
  - Hàng 1 (`i=0`) và cột 1 (`b=0`) là các trường hợp cơ sở có giá trị bằng 0.
- **Công thức chuyển trạng thái**:
  - `not_take = table[i, b+1]` (không chọn đơn thứ `i`).
  - Nếu `c_i <= b`: `take = val_i + table[i, b - c_i + 1]` (chọn đơn `i`).
  - `table[i+1, b+1] = take > not_take ? take : not_take`.
- **Vì sao nhánh chọn phải lấy từ hàng i - 1 (`table[i, ...]`)?**
  - Để đảm bảo bài toán ba lô 0/1: mỗi đơn hàng chỉ được chọn **tối đa một lần**. Nếu lấy từ hàng `i`, đơn `i` có thể bị dùng lặp lại nhiều lần (ba lô không giới hạn).
- **Ví dụ ô `F(2, 8)` tương ứng `table[3, 9]`**:
  - Đơn 2 có chi phí `c_2 = 5`, lợi ích `val_2 = 8`.
  - `not_take = table[2, 9] = F(1, 8) = 6`.
  - `take = 8 + table[2, 8 - 5 + 1] = 8 + table[2, 4] = 8 + F(1, 3) = 8 + 6 = 14`.
  - `F(2, 8) = max(6, 14) = 14` -> Giá trị lưu tại `table[3, 9] = 14`.
- **Đối chiếu với Vét cạn (Brute Force)**:
  - Trên bộ mini (3 đơn, ngân sách 8): cả thuật toán DP và thuật toán vét cạn đều cho giá trị tối ưu = 14 với tập đơn được chọn là `{1, 2}` và tổng chi phí là 8.
"""

# ╔═╡ 09102026-0000-4000-8000-000000000008
"""
## 4. Minh chứng kiểm thử và Kết quả luồng thực thi
- **Kiểm thử tự động**:
  - Đạt toàn bộ 60/60 phép kiểm tra (`--phase=all`):
    - `phase=data`: 12/12
    - `phase=sort`: 8/8
    - `phase=search`: 5/5
    - `phase=bfs`: 7/7
    - `phase=dp`: 12/12
    - `phase=app`: 16/16
- **Bất biến hệ thống**: Đảm bảo toàn vẹn `check_invariants(s) == true`.
  - Đơn chờ và đơn đã giao không trùng lặp, hợp lại đúng bằng tập chọn `[1, 2]`.
  - Thời gian đã dùng `s.spent == 8 <= budget = 8`.
  - Lợi ích đã nhận `s.earned == 14`.
  - Thao tác `undo!` khôi phục hoàn hảo trạng thái trước khi giao.
"""

# ╔═╡ 09102026-0000-4000-8000-000000000009
if RUN_APP && bao_cao !== nothing
    println("Kết quả từ cùng lõi ứng dụng Julia:")
    show(stdout, "text/plain", bao_cao)
    println()
end

# ╔═╡ Cell order:
# ╠═09102026-0000-4000-8000-000000000001
# ╠═09102026-0000-4000-8000-000000000002
# ╠═09102026-0000-4000-8000-000000000003
# ╠═09102026-0000-4000-8000-000000000004
# ╠═09102026-0000-4000-8000-000000000005
# ╠═09102026-0000-4000-8000-000000000006
# ╠═09102026-0000-4000-8000-000000000007
# ╠═09102026-0000-4000-8000-000000000008
# ╠═09102026-0000-4000-8000-000000000009
