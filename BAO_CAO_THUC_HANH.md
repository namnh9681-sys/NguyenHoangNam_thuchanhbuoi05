# BÁO CÁO THỰC HÀNH CẤU TRÚC DỮ LIỆU VÀ GIẢI THUẬT
## ĐIỀU PHỐI GIAO ĐƠN TRONG KHUÔN VIÊN TRƯỜNG BẰNG JULIA

- **Mã số sinh viên (MSSV):** `N24DCDT051`
- **Ngày thực hành:** 09/10/2026
- **Ngôn ngữ & Môi trường:** Julia 1.12.7 (Base, không dùng thư viện ngoài)
- **Tập dữ liệu chuẩn:** `MINI001` (Ngân sách thời gian $B = 8$)
- **Tập dữ liệu cá nhân hóa:** `N24DCDT051` (10 đơn hàng, Ngân sách $B = 26$)
- **Phiên bản mã nguồn:** Hoàn thiện toàn bộ 4 hàm cốt lõi trong [TH_2026_10_09_Sinh_vien.jl](file:///d:/DOWNLOAD/Bo_Thuc_hanh_Julia_2026_10_09_Sinh_vien/TH_2026_10_09_Sinh_vien.jl)

---

## 1. Bài toán và Dữ liệu

### 1.1. Mô tả bài toán
Bài toán đặt ra yêu cầu xây dựng hệ thống điều phối giao hàng độc lập trong khuôn viên trường đại học:
- Xuất phát từ kho trung tâm (đỉnh 1), người giao hàng vận chuyển đơn tới điểm giao, phục vụ khách hàng, rồi lập tức quay về kho 1 trước khi bắt đầu chuyến tiếp theo.
- Bản đồ trường học được mô hình hóa thành đồ thị vô hướng không trọng số $G = (V, E)$ gồm 6 đỉnh và 7 cạnh. Mỗi cạnh tốn 1 đơn vị thời gian di chuyển.
- Tổng thời gian thực hiện đơn hàng $i$ ($\tau_i$) được xác định bởi công thức:
  $$\tau_i = 2 \times h_i + s_i$$
  Trong đó:
  - $h_i$: số cạnh của đường đi ngắn nhất từ kho 1 tới điểm giao $d_i$ (do BFS tìm kiếm).
  - $2 \times h_i$: thời gian cả lượt đi và lượt về.
  - $s_i$: thời gian phục vụ tại điểm giao.
- Mục tiêu: Chọn ra một tập các đơn hàng sao cho **tổng lợi ích thu được là lớn nhất** mà **tổng chi phí thời gian không vượt quá ngân sách $B = 8$**. Đây là bài toán Ba lô 0/1 (0/1 Knapsack Problem).

### 1.2. Dữ liệu đầu vào (Bộ mẫu `MINI001`)
- Tệp `don_hang.csv`:
  ```csv
  id,diem_giao,thoi_gian_phuc_vu,loi_ich
  1,2,1,6
  2,4,1,8
  3,6,1,10
  ```
- Tệp `ban_do.csv`: 7 cạnh vô hướng:
  `(1, 2), (1, 3), (2, 4), (3, 4), (3, 5), (4, 6), (5, 6)`

---

## 2. Sơ đồ xử lý và Mô hình dữ liệu

### 2.1. Sơ đồ luồng xử lý dữ liệu
```
[ don_hang.csv ] ──┐
                   ├─► read_data() ──► Danh mục đơn & Bản đồ
[ ban_do.csv   ] ──┘                          │
                                              ▼
                                     merge_sort(ID tăng) ──► Cây BST cân bằng & binary_search
                                              │
                                              ▼
                                      bfs_routes(G, 1) ──► distance, parent, routes
                                              │
                                              ▼
                                     Tính costs = Dict(id => 2*h + s)
                                              │
                                              ▼
                                   knapsack(orders, costs, B) ──► Kế hoạch tối ưu (DP)
                                              │
                                              ▼
                                   priority_orders (tỷ số giảm) ──► Danh sách liên kết kế hoạch
                                              │
                                              ▼
                             Hàng đợi vòng FIFO (pending) ◄───► Ngăn xếp LIFO (completed)
                             [Thao tác deliver!]                [Thao tác undo!]
                                              │
                                              ▼
                                     export_result() ──► [ ket_qua.csv ]
```

### 2.2. Vai trò các cấu trúc dữ liệu và Bất biến
- `Order`: Bản ghi bất biến biểu diễn đơn hàng (`id`, `destination`, `service`, `benefit`).
- `CircularQueue` (FIFO): Quản lý danh sách các đơn hàng đã được chọn và đang chờ được giao.
- `Vector{Int}` (Stack LIFO): Quản lý lịch sử các đơn hàng đã giao thành công, phục vụ thao tác hoàn tác (`undo!`).
- `balanced_bst`: Cây tìm kiếm nhị phân hỗ trợ tra cứu thông tin đơn hàng theo ID với độ phức tạp tốt nhất.
- **Bất biến hệ thống (`check_invariants`)**:
  1. Không mất đơn, không lặp đơn: $\text{Set}(\text{pending}) \cap \text{Set}(\text{completed}) = \emptyset$ và $\text{Set}(\text{pending}) \cup \text{Set}(\text{completed}) = \text{Set}(\text{selected\_ids})$.
  2. Bảo toàn ngân sách: $0 \le \text{spent} \le \text{cost}(\text{selected}) \le B$.
  3. Bảo toàn lợi ích: $\text{earned} = \sum_{id \in \text{completed}} \text{benefit}(id)$ (được kiểm chứng qua đệ quy `recursive_benefit`).

---

## 3. Ý tưởng thuật toán và Truy vết chi tiết

### 3.1. Nhiệm vụ 1: Sắp xếp trộn (`merge_sort`)
- **Đầu vào:** `a::AbstractVector`, `before::Function`.
- **Đầu ra:** Mảng mới chứa các phần tử của `a` đã được sắp xếp theo quan hệ thứ tự `before`, không thay đổi mảng gốc `a`.
- **Ý tưởng & Điều kiện dừng:**
  - Áp dụng phương pháp chia để trị (Divide and Conquer).
  - Điều kiện dừng: nếu `length(a) <= 1`, trả về bản sao `collect(a)`.
  - Chia đôi dãy tại `mid = div(length(a), 2)`, đệ quy sắp xếp hai nửa `left` và `right`.
  - Trộn hai dãy đã sắp: so sánh `right[j]` và `left[i]`. Nếu `before(right[j], left[i])` là `true` thì lấy phần tử bên phải; ngược lại lấy phần tử bên trái. Quy tắc này đảm bảo tính ổn định (stable) khi hai phần tử có khóa bằng nhau.

### 3.2. Nhiệm vụ 2: Tìm kiếm nhị phân (`binary_search`)
- **Đầu vào:** `a::Vector{Order}` (đã sắp xếp tăng dần theo `id`), `id::Int`.
- **Đầu ra:** Đối tượng `Order` nếu tìm thấy, hoặc `nothing` nếu không có trong mảng.
- **Ý tưởng:**
  - Khởi tạo khoảng tìm kiếm `[lo, hi] = [1, length(a)]`.
  - Trong khi `lo <= hi`: lấy chỉ số giữa `mid = lo + div(hi - lo, 2)`.
  - Nếu `a[mid].id == id`: trả về `a[mid]`.
  - Nếu `a[mid].id < id`: thu hẹp sang nửa phải `lo = mid + 1`.
  - Nếu `a[mid].id > id`: thu hẹp sang nửa trái `hi = mid - 1`.
  - Khi `lo > hi`, khoảng rỗng, trả về `nothing`.

### 3.3. Nhiệm vụ 3: BFS tìm đường ngắn nhất (`bfs_routes`)
- **Đầu vào:** `graph` (danh sách kề đồ thị), đỉnh nguồn `source = 1`.
- **Đầu ra:** NamedTuple `(distance, parent, routes)`.
- **Ý tưởng:**
  - Sử dụng hàng đợi vòng `CircularQueue(V)` hoạt động theo cơ chế FIFO.
  - Khởi tạo mảng `distance` toàn $-1$, `parent` toàn $0$.
  - Đánh dấu đỉnh nguồn: `distance[source] = 0`, `parent[source] = 0`, đưa vào hàng đợi `enqueue!(q, source)`.
  - Lặp rút đỉnh $u$ khỏi hàng đợi. Với mỗi đỉnh kề $v \in graph[u]$, nếu $v$ chưa thăm (`distance[v] == -1`), cập nhật ngay `distance[v] = distance[u] + 1`, `parent[v] = u` và `enqueue!(q, v)`. Việc đánh dấu ngay khi đưa vào hàng đợi đảm bảo mỗi đỉnh chỉ được thăm đúng 1 lần.
  - Dựng đường đi `routes[v]`: lần ngược từ $v$ theo mảng `parent` về đỉnh nguồn, sau đó đảo ngược dãy.

#### Bảng truy vết đường đi và chi phí thời gian từ Kho 1:
| Đơn ID | Điểm giao | Tuyến đường lượt đi ($1 \to d$) | Số cạnh $h$ | Thời gian phục vụ $s$ | Chi phí $\tau = 2h + s$ | Lợi ích | Tỷ số ưu tiên $\frac{b}{\tau}$ |
| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **1** | 2 | $1 \to 2$ | 1 | 1 | $2(1) + 1 = 3$ | 6 | $6 / 3 = 2.00$ |
| **2** | 4 | $1 \to 2 \to 4$ | 2 | 1 | $2(2) + 1 = 5$ | 8 | $8 / 5 = 1.60$ |
| **3** | 6 | $1 \to 2 \to 4 \to 6$ | 3 | 1 | $2(3) + 1 = 7$ | 10 | $10 / 7 \approx 1.43$ |

### 3.4. Nhiệm vụ 4: Quy hoạch động chọn đơn (`knapsack`)
- **Đầu vào:** `orders::Vector{Order}`, `costs::Dict{Int, Int}`, ngân sách `budget::Int`.
- **Đầu ra:** NamedTuple `(ids, value, cost, table)`.
- **Công thức quy hoạch động:**
  - Gọi $F(i, b)$ là giá trị lợi ích lớn nhất thu được khi xét tập con của $i$ đơn hàng đầu tiên với ngân sách thời gian tối đa $b$.
  - Trong Julia (chỉ số 1-based), $F(i, b)$ được lưu tại ô `table[i+1, b+1]`. Kích thước bảng là $(n+1) \times (B+1)$.
  - Trường hợp cơ sở: Hàng đầu tiên $i=0$ (`table[1, :] = 0`) và cột đầu tiên $b=0$ (`table[:, 1] = 0`).
  - Công thức chuyển trạng thái với đơn hàng thứ $i$ có chi phí $c_i = \text{costs}[o_i.id]$ và lợi ích $v_i = o_i.benefit$:
    - Nếu $c_i > b$: không thể chọn đơn $i \Rightarrow F(i, b) = F(i-1, b)$.
    - Nếu $c_i \le b$:
      $$F(i, b) = \max\Big(F(i-1, b),\, v_i + F(i-1, b - c_i)\Big)$$
    - **Quy tắc hòa:** Khi hai phương án bằng lợi ích, giữ phương án không chọn đơn $i$.
- **Truy vết (Backtracking):**
  - Khởi tạo $curr\_b = B$. Duyệt $i$ từ $n$ giảm về 1:
  - Nếu `table[i+1, curr_b+1] > table[i, curr_b+1]`: chứng tỏ đơn hàng $i$ đã được chọn. Thêm $o_i.id$ vào danh sách `ids` và giảm ngân sách: $curr\_b \leftarrow curr\_b - c_i$.
  - Đảo ngược danh sách `ids` để có thứ tự tự nhiên.

#### Bảng Quy hoạch động $F(i, b)$ chi tiết ($n=3, B=8$):
| $i \backslash b$ | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 |
| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **$i=0$ (gốc)** | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| **$i=1$ ($c_1=3, v_1=6$)** | 0 | 0 | 0 | 6 | 6 | 6 | 6 | 6 | 6 |
| **$i=2$ ($c_2=5, v_2=8$)** | 0 | 0 | 0 | 6 | 6 | 8 | 8 | 8 | **14** |
| **$i=3$ ($c_3=7, v_3=10$)** | 0 | 0 | 0 | 6 | 6 | 8 | 8 | 10 | **14** |

- **Giải thích ô $F(2, 8)$ tại `table[3, 9]`:**
  - Không lấy đơn 2: lấy từ hàng trước $F(1, 8) = 6$ (`table[2, 9]`).
  - Lấy đơn 2: lợi ích $v_2 + F(1, 8 - 5) = 8 + F(1, 3) = 8 + 6 = 14$ (lấy từ `table[2, 4]`).
  - So sánh: $14 > 6 \Rightarrow F(2, 8) = 14$.
- **Giải thích ô $F(3, 8)$ tại `table[4, 9]`:**
  - Không lấy đơn 3: $F(2, 8) = 14$.
  - Lấy đơn 3: $v_3 + F(2, 8 - 7) = 10 + F(2, 1) = 10 + 0 = 10$.
  - So sánh: $14 > 10 \Rightarrow F(3, 8) = 14$. Không lấy đơn 3.

---

## 4. Quyết định chọn đơn & Đối chiếu Vét cạn

### 4.1. Kết quả chọn đơn
- **Ngân sách:** $B = 8$.
- **Tập đơn được chọn:** `{1, 2}`.
- **Tổng thời gian tiêu tốn:** $3 + 5 = 8$ (vừa khít ngân sách 8).
- **Tổng lợi ích đạt được:** $6 + 8 = 14$.

### 4.2. Đối chiếu với Vét cạn (Brute Force - Liệt kê $2^3 = 8$ tập con)
| Tập con đơn hàng | Tổng chi phí thời gian | Hợp lệ ($\le 8$)? | Tổng lợi ích | Đánh giá |
| :---: | :---: | :---: | :---: | :---: |
| $\emptyset$ | 0 | Có | 0 | |
| $\{1\}$ | 3 | Có | 6 | |
| $\{2\}$ | 5 | Có | 8 | |
| $\{3\}$ | 7 | Có | 10 | |
| **$\{1, 2\}$** | **8** | **Có** | **14** | **NGHIỆM TỐI ƯU DUY NHẤT** |
| $\{1, 3\}$ | $3 + 7 = 10$ | Không (vượt ngân sách) | - | Bị loại |
| $\{2, 3\}$ | $5 + 7 = 12$ | Không (vượt ngân sách) | - | Bị loại |
| $\{1, 2, 3\}$ | $3 + 5 + 7 = 15$ | Không (vượt ngân sách) | - | Bị loại |

$\Rightarrow$ Kết quả thuật toán Quy hoạch động $14$ hoàn toàn trùng khớp với kết quả Vét cạn.

---

## 5. Vòng đời Giao hàng và Hoàn tác

Bảng trạng thái thực nghiệm của ứng dụng qua các bước thao tác trên bộ `MINI001`:

| Thời điểm / Bước | Hàng đợi chờ (`pending`) | Ngăn xếp đã giao (`completed`) | Đã dùng (`spent`) | Đã nhận (`earned`) | Ghi chú hành động |
| :--- | :---: | :---: | :---: | :---: | :--- |
| **1. Sau lập kế hoạch** | `[1, 2]` | `[]` | 0 | 0 | Đơn được nạp vào FIFO theo tỷ số ưu tiên giảm dần |
| **2. Sau giao một đơn** | `[2]` | `[1]` | 3 | 6 | Lấy đơn 1 khỏi đầu FIFO, đẩy vào ngăn xếp hoàn tất |
| **3. Sau hoàn tác** | `[1, 2]` | `[]` | 0 | 0 | Rút đơn 1 từ đỉnh ngăn xếp, trả về đầu FIFO qua `enqueue_front!` |
| **4. Sau giao hết** | `[]` | `[1, 2]` | 8 | 14 | Giao lần lượt đơn 1 rồi đơn 2; hàng đợi rỗng, hoàn tất toàn bộ |

---

## 6. Kết quả Kiểm thử thực tế

Kết quả thực thi toàn bộ kiểm thử tự động với lệnh `julia TH_2026_10_09_Kiem_thu.jl --phase=all`:

| Pha kiểm thử | Lệnh thực thi | Số ca kiểm tra | Kết quả thực tế | Trạng thái |
| :--- | :--- | :---: | :--- | :---: |
| `phase=data` | `julia TH_2026_10_09_Kiem_thu.jl --phase=data` | 12 | 12/12 ca kiểm tra đạt | **ĐẠT** |
| `phase=sort` | `julia TH_2026_10_09_Kiem_thu.jl --phase=sort` | 8 | 8/8 ca kiểm tra đạt | **ĐẠT** |
| `phase=search`| `julia TH_2026_10_09_Kiem_thu.jl --phase=search` | 5 | 5/5 ca kiểm tra đạt | **ĐẠT** |
| `phase=bfs` | `julia TH_2026_10_09_Kiem_thu.jl --phase=bfs` | 7 | 7/7 ca kiểm tra đạt | **ĐẠT** |
| `phase=dp` | `julia TH_2026_10_09_Kiem_thu.jl --phase=dp` | 12 | 12/12 ca kiểm tra đạt | **ĐẠT** |
| `phase=app` | `julia TH_2026_10_09_Kiem_thu.jl --phase=app` | 16 | 16/16 ca kiểm tra đạt | **ĐẠT** |
| **Tổng thể (`all`)** | **`julia TH_2026_10_09_Kiem_thu.jl --phase=all`** | **60** | **60/60 ca kiểm tra đạt** | **100% ĐẠT** |

- Tệp kết quả xuất tự động: `data/MINI001/ket_qua.csv`
  ```csv
  id,diem_giao,so_canh,chi_phi,loi_ich,tuyen_di,duoc_chon,da_giao,trang_thai
  1,2,1,3,6,1-2,1,1,da_giao
  2,4,2,5,8,1-2-4,1,1,da_giao
  3,6,3,7,10,1-2-4-6,0,0,khong_chon
  ```

---

## 7. Phân tích Độ phức tạp và Giới hạn

| Thuật toán | Độ phức tạp thời gian | Độ phức tạp bộ nhớ | Điều kiện áp dụng & Giới hạn |
| :--- | :---: | :---: | :--- |
| `merge_sort` | $O(n \log n)$ | $O(n)$ | Thuật toán sắp xếp ổn định, hoạt động tốt trên mọi loại dữ liệu hỗ trợ quan hệ so sánh. |
| `binary_search`| $O(\log n)$ | $O(1)$ | **Bắt buộc mảng phải có thứ tự tăng dần theo khóa tìm kiếm** (ở đây là ID đơn hàng). |
| `bfs_routes` | $O(V + E)$ | $O(V)$ (bộ nhớ tuyến: $O(V^2)$) | **Chỉ áp dụng trên đồ thị không trọng số** (mỗi cạnh 1 đơn vị thời gian). Nếu có trọng số khác nhau, phải dùng Dijkstra. |
| `knapsack` | $O(n \cdot B)$ | $O(n \cdot B)$ | Bảng quy hoạch động là thuật toán đa thức giả (pseudo-polynomial), phụ thuộc vào độ lớn của số nguyên $B$. Nếu $B$ quá lớn, chi phí bộ nhớ/thời gian tăng cao. |
| `brute_force` | $O(n \cdot 2^n)$ | $O(n)$ | Độ phức tạp hàm mũ; chỉ dùng để kiểm chứng tính đúng đắn trên tập dữ liệu nhỏ ($n \le 20$). |
| `balanced_bst` | $O(h)$ | $O(n)$ | Chi phí tra cứu phụ thuộc chiều cao $h$. Với cây cân bằng $h = O(\log n)$; nếu cây lệch xấu nhất $h = O(n)$. |

---

## 8. Trả lời 5 Câu hỏi cuối buổi

### Q1. Vì sao không được dùng dãy đã sắp giảm theo lợi ích/τ để tìm kiếm nhị phân theo ID? Nêu tiền điều kiện của hàm tìm kiếm.
- **Trả lời:**
  - **Tiền điều kiện của tìm kiếm nhị phân:** Dãy đầu vào bắt buộc phải được sắp xếp theo đúng khóa tìm kiếm (trong bài toán này là `Order.id` tăng dần).
  - **Lý do không dùng dãy theo tỷ số lợi ích/$\tau$:** Khi sắp xếp giảm dần theo tỷ số lợi ích/chi phí ($\frac{b}{\tau}$), thứ tự của các mã định danh `id` bị xáo trộn ngẫu nhiên (không còn tăng dần). Nếu so sánh `a[mid].id` với `id` cần tìm, ta không thể biết phần tử cần tìm nằm ở nửa trái hay nửa phải, dẫn đến loại trừ sai phạm vi tìm kiếm và cho kết quả không chính xác.

### Q2. Với đơn ID 2 tới điểm 4, phục vụ 1 và bản đồ mẫu, giải thích từng thành phần của thời gian thực hiện τ. BFS có tiếp tục cho thời gian ngắn nhất nếu các cạnh mang thời gian khác nhau không?
- **Trả lời:**
  - **Giải thích từng thành phần:**
    - Tuyến đường ngắn nhất từ kho 1 tới điểm 4 là $1 \to 2 \to 4$, gồm $h = 2$ cạnh.
    - Thời gian di chuyển 2 chiều (đi và về): $2 \times h = 2 \times 2 = 4$ đơn vị thời gian.
    - Thời gian phục vụ tại điểm giao: $s = 1$ đơn vị thời gian.
    - Tổng thời gian: $\tau = 2h + s = 4 + 1 = 5$.
  - **Khi các cạnh mang thời gian khác nhau:** Thuật toán BFS **không còn** đảm bảo tìm được đường đi ngắn nhất. BFS chỉ tìm đường đi có **ít số cạnh nhất**. Khi đồ thị có trọng số thời gian trên cạnh khác nhau, đường đi ít cạnh hơn có thể có tổng trọng số lớn hơn đường đi nhiều cạnh hơn. Khi đó, bắt buộc phải sử dụng thuật toán Dijkstra.

### Q3. Giải thích hai phương án tạo ô F(2,8) và vị trí của ô đó trong table Julia. Vì sao nhánh lấy đơn phải dùng hàng trước?
- **Trả lời:**
  - **Vị trí ô trong Julia:** Ô $F(2, 8)$ biểu diễn $i=2$ đơn đầu và ngân sách $b=8$. Do mảng Julia đánh chỉ số từ 1, ô này nằm tại tọa độ `table[2+1, 8+1]` = **`table[3, 9]`**.
  - **Hai phương án tạo ô:**
    - *Phương án 1 (Không lấy đơn 2):* Giá trị tối ưu lấy nguyên từ bài toán con với 1 đơn đầu cùng ngân sách 8: $F(1, 8) = \text{table}[2, 9] = 6$.
    - *Phương án 2 (Lấy đơn 2):* Đơn 2 có chi phí $c_2 = 5$ và lợi ích $v_2 = 8$. Lợi ích nhận được là $v_2$ cộng với giá trị tối ưu của phần ngân sách còn lại $8 - 5 = 3$ từ 1 đơn đầu: $v_2 + F(1, 3) = 8 + \text{table}[2, 4] = 8 + 6 = 14$.
    - Lấy giá trị lớn nhất: $\max(6, 14) = 14$.
  - **Vì sao nhánh lấy đơn phải dùng hàng trước ($i-1$)?** Để đảm bảo tính chất của bài toán ba lô 0/1: **mỗi đơn hàng chỉ được chọn tối đa một lần**. Nếu lấy từ hàng hiện tại $i$, đơn hàng thứ $i$ có thể được cộng lặp lại nhiều lần vào cùng một phương án (trở thành bài toán ba lô không giới hạn).

### Q4. Sau khi giao ID 1 rồi hoàn tác ngay, FIFO, ngăn xếp, tổng thời gian và tổng lợi ích phải thay đổi thế nào? Nêu một bất biến kiểm tra việc không mất hoặc lặp đơn.
- **Trả lời:**
  - **Diễn biến trạng thái:**
    - *Khi giao ID 1:* Đơn 1 rời khỏi đầu FIFO `pending`, đẩy vào đỉnh ngăn xếp `completed`; tổng thời gian $\text{spent}$ tăng từ $0 \to 3$; tổng lợi ích $\text{earned}$ tăng từ $0 \to 6$.
    - *Khi hoàn tác ngay (`undo!`):* Đơn 1 được lấy khỏi đỉnh ngăn xếp `completed`, chèn ngược lại vào **đầu** FIFO `pending` bằng `enqueue_front!`; tổng thời gian $\text{spent}$ giảm từ $3 \to 0$; tổng lợi ích $\text{earned}$ giảm từ $6 \to 0$. Trạng thái được khôi phục nguyên vẹn như trước khi giao: FIFO có `[1, 2]`, ngăn xếp rỗng `[]`.
  - **Bất biến kiểm tra:**
    - Tập hợp bảo toàn: $\text{Set}(\text{pending}) \cup \text{Set}(\text{completed}) = \text{Set}(\text{selected\_ids})$.
    - Không giao nhau: $\text{Set}(\text{pending}) \cap \text{Set}(\text{completed}) = \emptyset$.
    - Kích thước bảo toàn: $\text{length}(\text{pending}) + \text{length}(\text{completed}) = \text{length}(\text{selected\_ids})$.

### Q5. Cho biết độ phức tạp theo n, V, E, B của sắp xếp trộn, tìm kiếm nhị phân, BFS cốt lõi và DP bảng đầy đủ. Vì sao không thể khẳng định mọi BST đều tra cứu trong O(log n)?
- **Trả lời:**
  - **Độ phức tạp:**
    1. Sắp xếp trộn (`merge_sort`): Thời gian $O(n \log n)$, Không gian $O(n)$.
    2. Tìm kiếm nhị phân (`binary_search`): Thời gian $O(\log n)$, Không gian $O(1)$.
    3. BFS cốt lõi (`bfs_routes`): Thời gian $O(V + E)$, Không gian $O(V)$ (ngoài bộ nhớ lưu trữ các tuyến đường).
    4. Quy hoạch động bảng đầy đủ (`knapsack`): Thời gian $O(n \cdot B)$, Không gian $O(n \cdot B)$.
  - **Vì sao không thể khẳng định mọi BST đều tra cứu trong $O(\log n)$?**
    - Chi phí tìm kiếm trên cây tìm kiếm nhị phân (BST) phụ thuộc trực tiếp vào **chiều cao của cây $h$**, tức là $O(h)$.
    - Chiều cao $h = O(\log n)$ chỉ đạt được khi cây ở trạng thái cân bằng. Với một BST thông thường (không có cơ chế tự cân bằng), nếu các khóa được chèn vào theo thứ tự đã sắp xếp tăng dần hoặc giảm dần, cây sẽ bị suy biến hoàn toàn thành một danh sách liên kết tuyến tính. Khi đó, chiều cao cây là $h = n$, và thời gian tra cứu trong trường hợp xấu nhất sẽ là $O(n)$.

---

## 9. Mở rộng Cá nhân hóa theo MSSV (`N24DCDT051`)

### 9.1. Thông số Hồ sơ cá nhân
- **MSSV:** `N24DCDT051`
- **Số đơn hàng ($n$):** 10 đơn hàng
- **Ngân sách thời gian ($B$):** 26 đơn vị
- **Tập tin dữ liệu sinh ra:**
  - `data/N24DCDT051/don_hang.csv`
  - `data/N24DCDT051/ban_do.csv`

### 9.2. Bảng dữ liệu 10 đơn hàng và Chi phí tính từ BFS
| ID | Điểm giao | Thời gian phục vụ $s$ | Chi phí BFS $\tau$ | Lợi ích | Tuyến đường BFS | Trạng thái chọn |
| :---: | :---: | :---: | :---: | :---: | :--- | :---: |
| **1** | 6 | 2 | 8 | 14 | $1 \to 3 \to 5 \to 6$ | **ĐƯỢC CHỌN** (Đã giao) |
| **2** | 2 | 1 | 3 | 13 | $1 \to 2$ | **ĐƯỢC CHỌN** (Đã giao) |
| **3** | 2 | 1 | 3 | 5 | $1 \to 2$ | Không chọn |
| **4** | 4 | 2 | 6 | 3 | $1 \to 3 \to 4$ | Không chọn |
| **5** | 6 | 2 | 8 | 8 | $1 \to 3 \to 5 \to 6$ | Không chọn |
| **6** | 6 | 1 | 7 | 13 | $1 \to 3 \to 5 \to 6$ | **ĐƯỢC CHỌN** (Đã giao) |
| **7** | 6 | 2 | 8 | 2 | $1 \to 3 \to 5 \to 6$ | Không chọn |
| **8** | 5 | 3 | 7 | 11 | $1 \to 3 \to 5$ | **ĐƯỢC CHỌN** (Đã giao) |
| **9** | 4 | 2 | 6 | 6 | $1 \to 3 \to 4$ | Không chọn |
| **10** | 4 | 2 | 6 | 8 | $1 \to 3 \to 4$ | Không chọn |

### 9.3. So sánh hiệu quả thuật toán trên tập dữ liệu `N24DCDT051`
- **Quy hoạch động (DP):** Lợi ích tối ưu = **51**
- **Vét cạn (Brute Force):** Lợi ích tối ưu = **51** (Trùng khớp 100% với DP)
- **Tham lam (Greedy theo tỷ số):** Lợi ích = **45**

> **Nhận xét quan trọng:**
> Kết quả thực nghiệm trên MSSV `N24DCDT051` cho thấy rõ ràng:
> - Thuật toán **Quy hoạch động** tìm được nghiệm tối ưu toàn cục (Lợi ích 51, tiêu tốn 25/26 ngân sách thời gian với 4 đơn `{2, 6, 1, 8}`), hoàn toàn trùng khớp với thuật toán vét cạn $2^{10} = 1024$ tập con.
> - Thuật toán **Tham lam** (Greedy) chỉ đạt lợi ích 45 (bị mất 6 điểm lợi ích). Đây là minh chứng thực tế trên chính dữ liệu sinh viên cho thấy phương pháp tham lam cục bộ không đảm bảo tối ưu toàn cục cho bài toán Ba lô 0/1.

### 9.4. Tệp kết quả xuất ra
- Đường dẫn: `data/N24DCDT051/ket_qua.csv`
- Đầy đủ 9 cột theo quy chuẩn, phản ánh chính xác trạng thái giao và tuyến đường của cả 10 đơn hàng.
