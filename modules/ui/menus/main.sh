#!/usr/bin/env bash

ui_quick_guide() {
  while true; do
    ui_header
    ui_section "HƯỚNG DẪN NHANH — CHỌN ĐÚNG CHỨC NĂNG"
    cat <<'EOF'

  TÌNH HUỐNG THƯỜNG GẶP
  ---------------------
  • Tạo / xóa / bật tắt / bảo trì site
      → Sites Management / Maintenance & Safety

  • Code trên GitHub có thay đổi
      → Deploy & Runtime → Update Code from GitHub
      → sau đó Full Deploy nếu thay đổi cần build/migrate/runtime refresh

  • Chỉ sửa hoặc thêm biến .env thông thường
      → Deploy & Runtime → Backend → Optimize / Reload .env
      → sau đó Health Check
      → KHÔNG cần Full Deploy nếu không đổi image/port/service secret

  • Website lỗi 500 / 502 hoặc nghi runtime có vấn đề
      → Deploy & Runtime → Health Check
      → Doctor & Domain Diagnostics nếu cần kiểm tra sâu hơn

  • Backup trước khi thao tác nguy hiểm / phục hồi dữ liệu
      → Backup & Recovery

  • SSL / Nginx / domain proxy có vấn đề
      → Infrastructure — SSL & Nginx

  • Đổi repository nhưng giữ nguyên source
      → Repository & SSH → Update repository

  • Tạo repository mới hoặc đồng bộ hai repository
      → Repository & SSH → Bootstrap / Sync repository

  • Kiểm tra quyền GitHub / tạo SSH key riêng cho repository
      → Repository & SSH → Kiểm tra quyền repository / SSH key
      → Platform test READ + WRITE + DELETE bằng ref tạm, không chạm main
      → Nếu thiếu quyền, có thể tạo key theo owner/repo và in PUBLIC KEY

  NGUYÊN TẮC AN TOÀN
  ------------------
  1. Ưu tiên Dry-run / Health trước thao tác thay đổi lớn.
  2. Full Deploy dùng khi cần build image + migrate + optimize + runtime health.
  3. Optimize dùng cho thay đổi Laravel config/.env thông thường, nhanh hơn Full Deploy.
  4. Deploy chỉ thành công khi Laravel boot và HTTP application trả 2xx/3xx.
  5. Backup trước Archive/Purge/Restore hoặc thay đổi dữ liệu quan trọng.
  6. Không bao giờ chia sẻ private SSH key; menu chỉ hiển thị public key .pub.

  0) Quay lại

EOF
    local c
    read -r -p "Chọn: " c
    case "$c" in
      0|q|Q) return 0 ;;
      *) ;;
    esac
  done
}

# Read-only operator handoff. Never executes git, deploy or production changes.
ui_upgrade_prompt_guide() {
  ui_header
  ui_section "PROMPT NÂNG CẤP PLATFORM 2.1 — SAO CHÉP SANG CHAT MỚI"
  cat <<'EOF'

Hãy tiếp tục phát triển Laravel Deployment Platform v2.1.

Repository: tungocvan/laravel-deployment-platform-v2
Production checkout: /opt/laravel-deployment-platform-v2
CLI: platform-v2
Tài liệu ưu tiên: INFORMATION.md, README.md, docs/AI-HANDOFF.md
và docs/VPS-DEPLOYMENT-GUIDE.md.

Mục tiêu nâng cấp của tôi:
[ĐIỀN MÔ TẢ CHỨC NĂNG HOẶC LỖI CẦN SỬA]

Quy trình bắt buộc:
1. Đọc INFORMATION.md và audit read-only branch main mới nhất.
2. Đối chiếu implementation thực tế, tests, PR đang mở và lịch sử liên quan.
   Không giả định PR đã merge nếu chưa kiểm tra trên GitHub.
3. Phân tích nguyên nhân, đề xuất phạm vi và kiểm thử hồi quy.
4. Tạo feature/fix branch riêng; trực tiếp viết code trên GitHub và tạo Draft PR.
5. Không sửa production checkout, không tự merge main, không force-push.
6. Không động vào .env, APP_KEY, secrets, Docker runtime, inventory,
   database, volumes, SSH private keys hoặc site production.
7. Giữ nguyên safety gate, dry-run, confirm, backup và health check.
8. Cung cấp checkpoint git pull/test bằng worktree riêng.
9. Chỉ đề xuất merge khi Bash Syntax, targeted tests và UI PASS.
10. Sau merge, cập nhật INFORMATION.md và kiểm tra lại main.

Hãy bắt đầu bằng read-only audit, nêu chính xác trạng thái hiện tại
và thực hiện đến checkpoint pull/test, không tự merge.

EOF
  ui_pause
}

# Platform 2.1: task-oriented navigation. Descriptions are deliberately Vietnamese.
# Each operation is dispatched to its existing confirmed/safe workflow.
ui_main() {
  while true; do
    ui_header
    cat <<'EOF'


  1) Dashboard & Site Overview
     Xem danh sách, thông tin và trạng thái các website đang quản lý.

  2) Sites Management
     Tạo, nhân bản, bật/tắt, bảo trì và quản lý vòng đời website.

  3) Deploy & Runtime
     Cập nhật mã nguồn, triển khai, quản lý .env và phục hồi runtime.

  4) Backup & Recovery
     Tạo, kiểm tra và khôi phục bản sao lưu website.

  5) Monitoring & Diagnostics
     Kiểm tra sức khỏe, container, tên miền và lỗi vận hành.

  6) Infrastructure — SSL & Nginx
     Quản lý chứng chỉ HTTPS và cấu hình định tuyến Nginx.

  7) Maintenance & Safety
     Dọn dẹp, lưu trữ hoặc xóa site với bước xác nhận an toàn.

  8) Repository & SSH
     Đổi kho mã nguồn, đồng bộ Git và kiểm tra quyền truy cập SSH.

  9) Packages & Help & Upgrade Menu
     Quản lý gói, xem hướng dẫn và lấy prompt nâng cấp Platform 2.1.

  0) Thoát

EOF
    local choice
    read -r -p "Chọn chức năng: " choice || return 0
    case "$choice" in
      1) ui_site_operations_group "DASHBOARD — TỔNG QUAN WEBSITE" "$(cat <<'ITEMS'
8|Danh sách site~Xem các website đã đăng ký trên Platform.
9|Chi tiết site~Xem cấu hình và thông tin một website.
6|Runtime / Docker Status~Xem topology, container, health và cổng dịch vụ.
ITEMS
)" ;;
      2) ui_site_operations_group "SITES — QUẢN LÝ WEBSITE" "$(cat <<'ITEMS'
1|Tạo website~Khởi tạo một site mới theo quy trình có kiểm tra.
11|Nhân bản website~Tạo site mới từ site có sẵn.
12|Bật website~Kích hoạt website sau khi xác nhận.
13|Tắt website~Vô hiệu hóa website sau khi xác nhận.
14|Bật bảo trì~Đưa website vào chế độ bảo trì.
15|Tắt bảo trì~Đưa website trở lại hoạt động.
ITEMS
)" ;;
      3)
        while true; do
          ui_header
          ui_section "DEPLOY & RUNTIME — TRIỂN KHAI VÀ VẬN HÀNH"
          cat <<'EOF'
  1) Deploy chuẩn
     Git Update, Full Deploy, Backend, Frontend và Health Check.

  2) Update Site
     Git fast-forward + runtime reconcile; migration cần duyệt riêng.

  3) Manage .env
     Xem key ẩn giá trị, sửa hoặc import có preview và xác nhận.

  4) Reconcile / Resume Runtime
     Phục hồi runtime, không Git mutation, build hoặc migration.

  5) Run Artisan
     Chạy lệnh Laravel Artisan cho site đã chọn.

  0) Quay lại

EOF
          read -r -p "Chọn chức năng: " choice || break
          case "$choice" in
            1) ui_menu_deploy ;;
            2) ui_site_operation_dispatch 2 ;;
            3) ui_site_operation_dispatch 3 ;;
            4) ui_site_operation_dispatch 25 ;;
            5) ui_site_operation_dispatch 5 ;;
            0|q|Q) break ;;
            *) echo "[ERROR] Lựa chọn không hợp lệ."; ui_pause ;;
          esac
        done
        ;;
      4) ui_menu_backup ;;
      5)
        while true; do
          ui_header
          ui_section "MONITORING — GIÁM SÁT VÀ CHẨN ĐOÁN"
          cat <<'EOF'
  1) Doctor & Domain Diagnostics
     Kiểm tra domain, định danh và tình trạng website.

  2) Production Diagnostics
     Thu thập bằng chứng chẩn đoán chỉ đọc.

  3) Site Doctor
     Kiểm tra một site cụ thể.

  4) Runtime / Docker Status
     Xem dịch vụ, container, cổng và trạng thái sức khỏe.

  0) Quay lại

EOF
          read -r -p "Chọn chức năng: " choice || break
          case "$choice" in
            1) ui_menu_doctor ;;
            2) ui_site_operation_dispatch 4 ;;
            3) ui_site_operation_dispatch 10 ;;
            4) ui_site_operation_dispatch 6 ;;
            0|q|Q) break ;;
            *) echo "[ERROR] Lựa chọn không hợp lệ."; ui_pause ;;
          esac
        done
        ;;
      6) ui_menu_infrastructure ;;
      7) ui_site_operations_group "MAINTENANCE — BẢO TRÌ VÀ AN TOÀN" "$(cat <<'ITEMS'
7|Production Cleanup~Mặc định chỉ báo cáo; áp dụng cần xác nhận, Docker cleanup ảnh hưởng toàn host.
16|Archive site~Lưu trữ website theo quy trình an toàn.
17|Restore archived site~Khôi phục website đã lưu trữ.
18|Danh sách archive~Xem các website đang lưu trữ.
19|Purge site~Xóa website theo quy trình có xác nhận.
20|Purge Force~Xóa site đang hoạt động; thao tác nguy hiểm, cần xác nhận.
ITEMS
)" ;;
      8) ui_site_operations_group "REPOSITORY & SSH — KHO MÃ NGUỒN" "$(cat <<'ITEMS'
21|Update repository~Đổi kho mã nguồn của website có kiểm tra tương thích.
22|Bootstrap repository~Tạo kho Git mới từ mã nguồn hiện có.
23|Sync repositories~Đồng bộ hai kho theo quy trình có kiểm tra an toàn.
24|Repository access / SSH~Kiểm tra quyền Git và khóa SSH, không hiển thị private key.
ITEMS
)" ;;
      9)
        while true; do
          ui_header
          ui_section "PACKAGES & HELP & UPGRADE — GÓI, HƯỚNG DẪN VÀ NÂNG CẤP"
          cat <<'EOF'
  1) Packages
     Liệt kê, kiểm tra và xem lịch sử các gói chức năng.

  2) Hướng dẫn sử dụng / Chọn đúng chức năng
     Hướng dẫn xử lý .env, deploy, lỗi 500/502, backup, Git và SSL.

  3) Prompt nâng cấp Platform 2.1 (chỉ đọc)
     Hiển thị mẫu yêu cầu AI audit source và tạo PR an toàn.

  0) Quay lại

EOF
          read -r -p "Chọn chức năng: " choice || break
          case "$choice" in
            1) ui_menu_packages ;;
            2) ui_quick_guide ;;
            3) ui_upgrade_prompt_guide ;;
            0|q|Q) break ;;
            *) echo "[ERROR] Lựa chọn không hợp lệ."; ui_pause ;;
          esac
        done
        ;;
      0|q|Q) return 0 ;;
      *) echo "[ERROR] Lựa chọn không hợp lệ."; ui_pause ;;
    esac
  done
}
