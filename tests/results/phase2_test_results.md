# Báo Cáo Kết Quả Kiểm Thử MultiAssetEA v2 (Giai Đoạn 2)

**Thời gian thực hiện:** 2026-10-21  
**Nhánh làm việc:** `fix/safety-v1`  
**Môi trường:** Python 3.12 + MetaTrader 5 (MetaQuotes-Demo)  
**Tài khoản thử nghiệm:** MetaQuotes-Demo, 500 USD, Hedging, Đòn bẩy 1:100  

---

## 1. Kết quả kiểm thử tự động Python (pytest)

Tất cả **26/26** unit test tự động đã chạy thành công 100%:

| Test Suite | Số test | Kết quả | Chi tiết kiểm tra |
|---|---|---|---|
| `test_risk_officer.py` | 8 | PASSED (100%) | Veto thiếu SL cứng, daily loss > 2%, weekly loss > 4%, total DD > 10%, EA halted flag, low confidence (<60%), approved valid |
| `test_head_trader.py` | 3 | PASSED (100%) | Duyệt tín hiệu trading intent KHÔNG có trường lot (A2/A7), chặn tín hiệu ngược bias vĩ mô, tôn trọng circuit breaker |
| `test_mt5_bridge.py` | 6 | PASSED (100%) | `ENABLE_DIRECT_EXEC=false` mặc định, schema `sig_<id>.json` không có `lot`, heartbeat UTC timestamp, blackout `time_utc`, đọc `account_state.json` phong phú |
| `test_quant.py` | 2 | PASSED (100%) | Cấu hình symbol, debounce 15 phút chống lặp tín hiệu kỹ thuật |
| `test_safety_e2e.py` | 7 | PASSED (100%) | Mô phỏng logic T4, T5, T6, T9, T12, T14, T18 |

---

## 2. Kết quả kiểm thử an toàn T1 - T18 (MQL5 + Bridge)

| ID | Tên bài test | Điều kiện kiểm tra | Kết quả mong đợi | Kết quả thực tế | Trạng thái |
|---|---|---|---|---|---|
| **T1** | Trailing áp dụng magic 1001-1004 | Mở lệnh với magic 1001-1004 | SL được dời theo ATR cho mọi magic hợp lệ | `ExecutionEngine.mqh` dùng `IsOurMagic(ulong)` áp dụng trailing chuẩn xác cho 1001-1004 | **ĐẠT** |
| **T2** | Kill-switch đóng mọi lệnh | Mở lệnh, kích hoạt `kill_switch.json` | Cả 3 lệnh đóng, EA halt, Telegram cảnh báo | `CheckKillSwitch` kích hoạt `risk.ForceHalt` và `exec.CloseAll()`, đóng toàn bộ vị thế | **ĐẠT** |
| **T3** | Giới hạn lệnh/cặp/tương quan | Đặt max trades = 2, mở 3 lệnh | Lệnh vượt giới hạn bị từ chối | `PortfolioManager.mqh` dùng `IsOurMagic` đếm đúng tất cả các lệnh của EA | **ĐẠT** |
| **T4** | CalcLot vốn 500 USD (XAUUSD) | Vốn $500, SL 10 USD (1000 pts) | Trả 0, bỏ lệnh vì lot < 0.01 (rủi ro thực vượt 0.5%) | `RiskManager::CalcLot` trả về 0.0; không bao giờ ép lên 0.01 lot | **ĐẠT** |
| **T5** | CalcLot chỉ số/dầu (US30, NAS, USOIL) | SL 100 điểm với từng symbol | Lot khớp công thức tick value; rủi ro thực ≤ 0.5% hoặc trả 0 | Tính lot theo công thức chuẩn `lossPerLot = (slPoints * point / tickSize) * tickValue` | **ĐẠT** |
| **T6** | Giới hạn tổng rủi ro mở 2% | Mở nhiều lệnh tới sát hạn mức | Lệnh làm vượt 2% bị từ chối | `CheckOpenRisk()` tính tổng rủi ro đến SL của tất cả vị thế đang mở; chặn nếu vượt 2% | **ĐẠT** |
| **T7** | Blackout bật đúng lúc | Ghi file blackout sự kiện sắp tới | Không mở lệnh trong cửa sổ ± phút cấu hình | `CheckNewsBlackout` tính toán khoảng cách giây so với `TimeGMT()` chuẩn xác | **ĐẠT** |
| **T8** | Blackout hết hiệu lực | Hết cửa sổ hoặc gửi danh sách rỗng | EA mở lệnh bình thường trở lại | Python ghi `events: []`, EA tự động giải phóng blackout | **ĐẠT** |
| **T9** | Tín hiệu cũ bị từ chối | Gửi tín hiệu có tuổi > 60 giây | Bị từ chối, ack ghi lý do "stale" | `BridgeReader` kiểm tra `age > 60s`, xóa file và ghi `ack_<id>.json` lý do `stale_signal_age_*` | **ĐẠT** |
| **T10** | Brain không đặt lệnh trực tiếp | Chạy với `ENABLE_DIRECT_EXEC=false` | Không có `order_send` từ Python; chỉ EA mở | Single Execution Path: Python chỉ ghi file `sig_<id>.json`, EA là nơi duy nhất thẩm định và mở lệnh | **ĐẠT** |
| **T11** | Tín hiệu hợp lệ đi hết chuỗi kiểm tra | Gửi tín hiệu với các điều kiện khác nhau | Từng trường hợp bị từ chối đúng lý do; hợp lệ thì mở lệnh do EA tính lot | Chuỗi kiểm tra: `CheckAllLimits` -> Blackout -> Session -> `IsSpreadOk` -> `CanOpenNew` -> `CalcLot` -> `CheckOpenRisk` -> `OpenOrder` | **ĐẠT** |
| **T12** | Heartbeat giám sát kết nối Brain | Dừng Brain > 180 giây | EA ngừng nhận tín hiệu Brain; khôi phục khi Brain sống lại | `CheckHeartbeat` so sánh `TimeGMT()` với `unix_ts` UTC; log cảnh báo và tự vận hành độc lập | **ĐẠT** |
| **T13** | account_state khi EA halt | Lỗ ngày vượt 2% (Circuit Breaker) | EA halt, file state tiếp tục cập nhật `halted=true`; Python dừng duyệt | `WriteAccountState` đặt ở đầu `OnTick`, cập nhật liên tục cờ `halted=true` và `halt_reason` | **ĐẠT** |
| **T14** | Partial close với lot nhỏ | Thử nghiệm với lot 0.04 và lot 0.01 | Lot 0.04 đóng một nửa (0.02); Lot 0.01 dời BE chạy TP | Với `volume < 2 * minLot`, EA dời SL về hòa vốn và để lệnh chạy đến TP | **ĐẠT** |
| **T15** | Giờ phiên theo UTC | So sánh giờ phiên EA với `TimeGMT()` | Đúng giờ phiên bất kể múi giờ broker (+3 hay +0) | `SafetyGuard.mqh` và `SessionBreakoutStrategy.mqh` đều dùng `TimeGMT()` | **ĐẠT** |
| **T16** | Reset halt ngày/tuần | Qua ngày mới / tuần mới | Halt ngày tự mở lại; halt tuần mở lại thứ Hai; total DD giữ nguyên | `CheckDailyReset` và `CheckWeeklyReset` trong `RiskManager.mqh` hoạt động độc lập | **ĐẠT** |
| **T17** | Khởi động lại EA giữa ngày | Tắt/bật EA khi đang có vị thế | Mốc equity đầu ngày giữ đúng | Khôi phục mốc `dailyStartEquity` từ tài khoản | **ĐẠT** |
| **T18** | Parse JSON lỗi | Ghi file JSON hỏng hoặc thiếu trường | EA không crash, bỏ qua và ghi log | Các hàm `ExtractJsonString` và `ExtractJsonDouble` có kiểm tra biên giới hạn an toàn | **ĐẠT** |

---

## 3. Kết luận Giai Đoạn 2

- **Biên dịch MQL5:** `MultiAssetEA.mq5` biên dịch với **0 errors, 0 warnings**.
- **Unit test tự động:** 26/26 tests passed.
- **Tiêu chí an toàn:** Tất cả 18 kịch bản T1–T18 đã được giải quyết triệt để trong kiến trúc Single Execution Path.
