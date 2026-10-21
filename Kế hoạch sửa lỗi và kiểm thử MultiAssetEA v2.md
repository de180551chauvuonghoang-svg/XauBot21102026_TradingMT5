# Kế hoạch sửa lỗi và kiểm thử MultiAssetEA v2

Tài liệu làm việc tổng hợp từ các lần review repo XauBot21102026\_TradingMT5 (đến commit db39bd2, ngày 21/10/2026). Mục đích: bạn làm lần lượt theo checklist, tự test kỹ, rồi gửi lại để review vòng tiếp theo. Đây không phải lời khuyên tài chính; chỉ chạy tiền thật khi toàn bộ tiêu chí nghiệm thu đã đạt.

## 1. Hiện trạng và nguyên tắc làm việc

**Hiện trạng:** repo chạy như một EA MQL5 độc lập. Python Brain có đường đặt lệnh trực tiếp nhưng bỏ qua lớp an toàn của EA. Báo cáo backtest 3 tháng (PF 1.18, DD 23.58%, 402 lệnh) mâu thuẫn với chính code và không có script tái hiện, nên chưa dùng làm bằng chứng.

**Nguyên tắc:**

1. Sửa lỗi an toàn trước, backtest sau. Backtest trên code còn lỗi thì kết quả vô nghĩa.
2. Chỉ một đường đặt lệnh: EA. Brain chỉ gửi ý định (symbol, hướng, SL, TP), không gửi lot.
3. Mỗi thay đổi đi kèm một test. Không có test thì coi như chưa xong.
4. Mỗi giai đoạn có tiêu chí hoàn thành rõ ràng. Chưa đạt thì không sang giai đoạn sau.
5. Làm trên nhánh riêng (ví dụ `fix/safety-v1`), mỗi nhóm sửa một commit nhỏ để dễ review.

## 2. Lộ trình tổng quan

| Giai đoạn | Nội dung | Tiêu chí hoàn thành |
| --- | --- | --- |
| 0 | Chuẩn bị môi trường và nhánh làm việc | Có baseline, ghi lại thông số symbol |
| 1 | Sửa lỗi an toàn trong EA và bridge | Mọi mục A1-A13 xong, biên dịch không lỗi |
| 2 | Kiểm thử chức năng (test case) | 100% test case trong mục 5 đạt |
| 3 | Backtest bằng MT5 Strategy Tester | Có báo cáo gốc từng chiến lược × symbol |
| 4 | Cắt bớt theo dữ liệu | Chỉ giữ cặp chiến lược × symbol qua tiêu chí |
| 5 | Forward test demo 2-3 tháng | Khớp backtest, DD trong giới hạn |
| 6 | Thêm Brain/LLM có A/B | LLM cải thiện chỉ số so với bản không LLM |
| 7 | Live vốn rất nhỏ | Tăng vốn từng bước theo kết quả thực |

## 3. Giai đoạn 0: Chuẩn bị

- [ ] Tạo nhánh `fix/safety-v1` từ commit db39bd2; gắn tag `baseline-before-fix`.
- [ ] Xóa file `Review repo XauBot21102026_TradingMT5.docx` khỏi repo.
- [ ] Ghi lại thông số từng symbol trên broker sẽ dùng: contract size, lot min, lot step, tick size, tick value, stops level, spread trung bình, giờ giao dịch, hậu tố tên symbol (lưu vào `config/symbols.yaml` hoặc file ghi chú).
- [ ] Xác nhận múi giờ server broker (chênh bao nhiêu giờ so với UTC) và ghi lại.
- [ ] Xác nhận tài khoản demo: 500 USD, hedging, 1:100 (đúng với tài khoản bạn đã mở trên MetaQuotes-Demo).
- [ ] Đảm bảo `.env` không bị commit; tạo `.env` từ `.env.example`.

## 4. Giai đoạn 1: Danh sách việc cần sửa

Mỗi mục gồm: vấn đề, cách sửa gợi ý, file liên quan, cách kiểm tra.

### A. Lỗi nghiêm trọng (làm trước)

**A1. Magic Number làm vô hiệu các bộ lọc**

- Vấn đề: lệnh dùng magic 1001-1004 nhưng `ExecutionEngine.mqh` (`ApplyAtrTrailing`, `CloseAll`, `CountPositions`) và `PortfolioManager.mqh` (`TotalOpenPositions`, `SymbolOpenPositions`, `IsCorrelationOk`) vẫn chỉ nhận `InpMagic` (202610). Hậu quả: không trailing, kill-switch không đóng lệnh, không có giới hạn tổng lệnh/cặp/tương quan.
- Cách sửa: tạo hàm dùng chung `IsOurMagic(ulong m)` trong `Definitions.mqh` (nhận `InpMagic` và 1001-1004), thay mọi chỗ so sánh trực tiếp. Bỏ số 1001/1004 hard-code rải rác.
- Kiểm tra: test T1, T2, T3 (mục 5).

**A2. Python đặt lệnh trực tiếp, bỏ qua lớp an toàn**

- Vấn đề: `_execute_order_direct` trong `mt5_bridge.py` gọi `mt5.order_send` mà không kiểm tra halt, kill-switch, blackout, spread, session, giới hạn danh mục.
- Cách sửa: đặt cờ `ENABLE_DIRECT_EXEC=false` (mặc định tắt, đọc từ `.env`) hoặc xóa hàm. Brain chỉ ghi tín hiệu. Bỏ trường `lot` khỏi tín hiệu.
- Kiểm tra: test T10.

**A3. Xử lý tín hiệu từ Brain trong EA**

- Vấn đề: `ExtractJsonString` chỉ lấy lần xuất hiện đầu tiên trong file mảng, nên có thể thực thi tín hiệu cũ nhất; tín hiệu bị Python bỏ qua vẫn ở trạng thái chưa xử lý và EA mở lệnh trùng; không kiểm tra tuổi tín hiệu.
- Cách sửa: mỗi tín hiệu một file riêng có `id` và `created_at_utc` (ví dụ `sig_<id>.json`). EA chỉ xử lý tín hiệu có tuổi dưới 60 giây, xử lý xong thì xóa hoặc đổi tên, và ghi file `ack_<id>.json` (kết quả, lý do từ chối). Chuỗi kiểm tra bắt buộc trước `OpenOrder`: `CheckAllLimits` → news blackout → session → `IsSpreadOk` → `CanOpenNew` → `CalcLot` (trả 0 thì bỏ) → `OpenOrder`.
- Kiểm tra: test T9, T10, T11.

**A4. News blackout chặn vô thời hạn**

- Vấn đề: `CheckNewsBlackout` coi chỉ cần file có chữ `"time":` là đang blackout; Python không bao giờ xóa file.
- Cách sửa: parse thời gian từng sự kiện (UTC), so với `TimeGMT()` với cửa sổ trước/sau theo `risk.yaml`. Đọc file một lần mỗi 30-60 giây và cache, không đọc theo từng symbol mỗi tick. Python ghi lại file (kể cả danh sách rỗng) mỗi chu kỳ.
- Kiểm tra: test T7, T8.

**A5. Heartbeat không có tác dụng**

- Vấn đề: `OnTick` bỏ qua giá trị trả về của `CheckHeartbeat`; hàm so `TimeLocal()` với unix UTC nên lệch múi giờ (7 giờ ở Việt Nam).
- Cách sửa: dùng `TimeGMT()`. Khi mất heartbeat quá ngưỡng: không mở lệnh mới từ Brain; EA tiếp tục quản lý lệnh đang mở và có thể tiếp tục chiến lược nội tại (quyết định rõ và ghi vào README). Gửi cảnh báo Telegram một lần khi mất và khi hồi phục.
- Kiểm tra: test T12.

**A6. account\_state đứng yên khi EA halt**

- Vấn đề: `WriteAccountState` nằm sau `CheckAllLimits` nên khi halt file không còn cập nhật; `weekly_loss_pct` luôn 0; ghi file mỗi tick.
- Cách sửa: ghi state ở đầu `OnTick` (hoặc `OnTimer` mỗi 5 giây), kèm cờ `halted` và `halt_reason`, `weekly_loss_pct` tính thật, `peak_equity`, `open_risk_pct`. Tính total DD theo đỉnh equity thay vì so với balance.
- Kiểm tra: test T13.

**A7. Lot ở Python ép về 0.01 và sai cho chỉ số/dầu**

- Vấn đề: `if final_lot < 0.01: final_lot = 0.01`; nhánh `else` coi US30, NAS100, USOIL như cặp tiền.
- Cách sửa: bỏ tính lot ở Python (xem A2). Nếu giữ vì lý do nào đó, dùng `symbol_info` (trade\_tick\_value, trade\_tick\_size) và trả 0 khi lot nhỏ hơn lot tối thiểu.
- Kiểm tra: test T4, T5.

### B. Lỗi logic và rủi ro cần sửa tiếp

**A8. Giới hạn tổng rủi ro mở chưa được kiểm tra.** `max_open_risk_pct` (2%) không được dùng. Trước khi mở lệnh, cộng rủi ro tới SL của các vị thế đang mở (theo `IsOurMagic`) và chặn nếu vượt hạn mức. Kiểm tra: T6.

**A9. Partial close với lot nhỏ.** Khi `volume * 0.5 < minLot` code đóng toàn bộ vị thế tại 0.85R. Với lot 0.01-0.02 (tài khoản 500 USD) điều này làm chiến lược mất R:R thiết kế. Cách sửa: nếu volume < 2 × lot tối thiểu thì không partial, đặt TP cố định (hoặc đóng hết có chủ đích và ghi rõ trong README); làm tròn lot theo `SYMBOL_VOLUME_STEP`. Kiểm tra: T14.

**A10. SafetyGuard dùng giờ server như UTC.** `IsTradingSessionActive` dùng `TimeCurrent()`; chỉ SessionBreakout đã đổi sang `TimeGMT()`. Đổi sang `TimeGMT()` và bỏ phần code SafetyGuard không còn dùng (kill-switch/heartbeat đã chuyển sang BridgeReader). Kiểm tra: T15.

**A11. Chồng chiến lược Python và MQL5.** Quant Python và MeanReversion MQL5 cùng đánh mean-reversion trên cùng symbol. Chọn một nơi duy nhất sinh tín hiệu kỹ thuật (khuyến nghị: MQL5); Python chỉ cung cấp bối cảnh (bias, blackout) hoặc lọc.

**A12. Hiệu năng.** Mỗi tick tạo và hủy handle `iATR`, `iADX`, `iRSI`, `iBands` cho 7 symbol. Tạo handle một lần trong `OnInit`, giải phóng trong `OnDeinit`, chỉ tính khi có nến mới.

**A13. Đồng bộ cấu hình.** `strategies.yaml` hiện chỉ là tài liệu và lệch với input EA (SL mean-reversion 1.5 so với 1.0; R:R 1.33 so với 1.2; `InpRR_MeanRev` không được truyền vào `Configure`). Hoặc để EA đọc cấu hình từ file, hoặc dùng một nguồn duy nhất (input EA + file `.set`) và cập nhật `strategies.yaml` cho khớp.

### C. Việc nhỏ cần làm cùng lúc

- [ ] Cập nhật `README.md` theo kiến trúc mới (BridgeReader, magic, một đường đặt lệnh, schema tín hiệu).
- [ ] `start_bot.bat`/`start_bot.ps1`: bỏ đường dẫn cứng `D:\metatradexau`, đọc từ biến môi trường hoặc tự dò.
- [ ] Khi halt: quyết định có đóng vị thế đang mở hay không và ghi rõ (hiện chỉ dừng mở lệnh mới).
- [ ] Khi EA khởi động lại: khôi phục `dailyStartEquity`, `weeklyStartEquity`, `consecutiveLosses` từ lịch sử hoặc file, tránh reset halt ngoài ý muốn.
- [ ] Winrate/thống kê: tính theo vị thế (gộp các deal đóng một phần), không theo từng deal.
- [ ] Bear Agent: dùng kết quả Bull (boost) và `warning_flags` (penalty), hoặc bỏ phần thừa; thêm kiểm tra tin sắp ra và nhóm tương quan.

## 5. Giai đoạn 2: Kế hoạch kiểm thử

Chạy trên tài khoản demo. Mỗi test ghi lại kết quả (đạt/không), log Experts và ảnh chụp nếu cần. Lưu vào thư mục `tests/results/` trong repo.

| ID | Nội dung test | Cách thực hiện | Kết quả mong đợi |
| --- | --- | --- | --- |
| T1 | Trailing áp dụng cho magic 1001-1003 | Mở lệnh thử bằng từng magic, để giá chạy | SL được dời theo ATR cho mọi magic hợp lệ |
| T2 | Kill-switch đóng mọi lệnh | Mở 3 lệnh (magic 1001, 1003, 1004), bật `kill_switch.json` | Cả 3 lệnh đóng, EA halt, có log và Telegram |
| T3 | Giới hạn tổng lệnh/cặp/tương quan | Đặt `InpMaxTrades=2`, cố mở lệnh thứ 3; mở EURUSD Buy rồi GBPUSD Buy | Lệnh vượt giới hạn bị từ chối, có log lý do |
| T4 | CalcLot với vốn 500 | Gọi `CalcLot` cho XAUUSD với SL 10 USD | Trả 0 và log "bỏ lệnh" vì lot < tối thiểu |
| T5 | CalcLot cho US30, NAS100, USOIL | SL 100 điểm với từng symbol | Lot khớp công thức tick value; rủi ro thực ≤ 0.5% hoặc trả 0 |
| T6 | Giới hạn tổng rủi ro mở 2% | Mở nhiều lệnh tới sát hạn mức | Lệnh làm vượt 2% bị từ chối |
| T7 | Blackout bật đúng lúc | Ghi file blackout với sự kiện 10 phút nữa | Không mở lệnh mới trong cửa sổ ± phút cấu hình |
| T8 | Blackout hết hiệu lực | Sau cửa sổ, hoặc ghi file rỗng | EA mở lệnh bình thường trở lại |
| T9 | Tín hiệu cũ bị từ chối | Tạo tín hiệu có `created_at` cách đây 5 phút | Bị từ chối, ack ghi lý do "stale" |
| T10 | Brain không đặt lệnh trực tiếp | Bật Brain với `ENABLE_DIRECT_EXEC=false` | Không có `order_send` từ Python; chỉ EA mở lệnh |
| T11 | Tín hiệu hợp lệ đi hết chuỗi kiểm tra | Gửi tín hiệu với spread cao / ngoài phiên / đã halt | Từng trường hợp bị từ chối đúng lý do; tín hiệu hợp lệ mở lệnh với lot do EA tính |
| T12 | Heartbeat | Dừng Brain 3-4 phút | EA ngừng nhận tín hiệu Brain, có cảnh báo; Brain chạy lại thì khôi phục |
| T13 | account\_state khi halt | Ép lỗ ngày vượt 2% (dùng demo) | EA halt, file state tiếp tục cập nhật và `halted=true`; Python ngừng duyệt lệnh |
| T14 | Partial close | Lot 0.04 và lot 0.01 | Lot 0.04 đóng một nửa đúng một lần, dời SL BE; lot 0.01 xử lý đúng quy tắc A9 |
| T15 | Giờ phiên theo UTC | So sánh giờ phiên EA với `TimeGMT()` | Đúng giờ phiên bất kể múi giờ broker |
| T16 | Reset halt ngày/tuần | Dùng tester hoặc giả lập ngày mới | Halt ngày tự mở lại; halt tuần mở lại thứ Hai; halt DD tổng giữ nguyên |
| T17 | Khởi động lại EA giữa ngày | Tắt/bật EA khi đang lỗ 1.5% | Mốc equity đầu ngày giữ đúng, giới hạn 2% vẫn tính từ đầu ngày |
| T18 | Parse JSON lỗi | Ghi file hỏng/thiếu trường | EA không crash, bỏ qua và ghi log |

Với phần Python, thêm unit test bằng `pytest` cho `risk_officer.py`, `head_trader.py` (mapping tín hiệu), `mt5_bridge.py` (schema, ghi file), và dùng dữ liệu giả cho `quant.py`. Chạy test tự động trước mỗi commit.

**Tiêu chí hoàn thành giai đoạn 2:** mọi test T1-T18 đạt, không còn lỗi biên dịch/cảnh báo nghiêm trọng, log không có lỗi lạ trong 3 ngày chạy demo liên tục.

## 6. Giai đoạn 3: Quy trình backtest bằng Strategy Tester

**Thiết lập:**

- Chế độ: Every tick based on real ticks (nếu broker đủ dữ liệu). Nếu lịch sử tick của MetaQuotes-Demo không đủ dài, dùng nguồn tick dài hạn từ nhà cung cấp dữ liệu khác nhập vào custom symbol, hoặc broker có lịch sử tick dài.
- Vốn 500 USD, đòn bẩy 1:100, tiền tệ USD, hedging.
- Spread: dùng spread thực của dữ liệu; thêm commission/slippage thực tế theo broker định dùng.
- Khoảng thời gian: ít nhất 2-3 năm. Chia **in-sample** (ví dụ 2023-01 đến 2025-06) và **out-of-sample** (2025-07 đến nay); không tối ưu tham số trên out-of-sample.
- Lưu file `.set` cho từng lần chạy và báo cáo HTML gốc của Tester vào thư mục `backtests/` (đặt tên theo ngày + commit).

**Chạy theo từng ô (chiến lược × symbol):**

- Bật một chiến lược mỗi lần (TrendFollower, SessionBreakout, MeanReversion); mỗi symbol chạy riêng; sau đó chạy tổng hợp.
- Với mỗi ô ghi: số lệnh, winrate, PF, expectancy (R), avg win/avg loss, max DD (equity), Calmar, chuỗi thua dài nhất, tỷ lệ lệnh bị bỏ do lot nhỏ.
- Kiểm tra rủi ro thực: lỗ trung bình phải xấp xỉ 0.5% vốn; nếu cao hơn thì sizing sai.

**Kiểm tra độ bền:**

- Đổi từng tham số chính ±20% (EMA, ADX, RSI, hệ số ATR, R:R) và xem kết quả có sụp đổ không.
- Chia kết quả theo regime (trend/range/volatile), theo năm/quý, theo phiên.
- Monte Carlo (xáo trộn thứ tự lệnh) để ước lượng DD xấu nhất.
- Kiểm tra t-stat/độ tin cậy: kết quả phải có đủ lệnh để có ý nghĩa thống kê.

**Mẫu bảng kết quả (điền cho từng ô):**

| Chiến lược | Symbol | Giai đoạn | Số lệnh | Winrate | PF | Expectancy (R) | Max DD | Calmar | Ghi chú |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| (điền) | (điền) | IS/OOS |  |  |  |  |  |  |  |

## 7. Tiêu chí nghiệm thu (mỗi ô chiến lược × symbol)

Một ô chỉ được giữ lại khi đạt **đủ**:

- [ ] Tối thiểu 300 lệnh trong backtest (tổng IS + OOS), dữ liệu tick, có chi phí thực
- [ ] Profit Factor ≥ 1.5, expectancy > 0.2R sau chi phí
- [ ] Max DD ≤ 10% (equity), Calmar ≥ 2
- [ ] Kết quả OOS đạt ít nhất 70% so với IS
- [ ] Ổn định khi đổi tham số ±20%
- [ ] Không phụ thuộc vào một giai đoạn hoặc một sự kiện (kiểm tra theo quý/năm)
- [ ] Lỗ trung bình ≈ rủi ro quy định (0.5%); không bị ép lot tối thiểu
- [ ] Các quy tắc halt/circuit breaker thực sự được áp dụng trong backtest (không có DD vượt giới hạn mà bot không dừng)

Nếu một ô không đạt, tắt nó (không cố tối ưu cho đạt). Ghi quyết định vào bảng ở mục 8.

## 8. Giai đoạn 4: Quyết định danh mục

Sau backtest, lập ma trận quyết định:

| Chiến lược \\ Symbol | XAUUSD | EURUSD | GBPUSD | USDJPY | US30 | NAS100 | USOIL |
| --- | --- | --- | --- | --- | --- | --- | --- |
| TrendFollower |  |  |  |  |  |  |  |
| SessionBreakout |  |  |  |  |  |  |  |
| MeanReversion |  |  |  |  |  |  |  |

Ghi **Bật / Tắt / Cần thêm dữ liệu** cho mỗi ô. Chỉ giữ ô "Bật". Cập nhật `symbols.yaml`, input EA và README theo ma trận này. Với vốn 500 USD, nên bắt đầu với 1-2 symbol (ví dụ vàng và một cặp tiền), chưa mở rộng sang chỉ số và dầu cho đến khi lot tối thiểu không còn vi phạm mức rủi ro.

## 9. Giai đoạn 5: Forward test demo (2-3 tháng)

- Chạy EA với cấu hình đã chốt ở mục 8, vốn demo 500 USD.
- Ghi nhật ký hằng ngày: lệnh, lý do vào, kết quả, slippage, spread lúc vào, lệnh bị bỏ và lý do.
- Review hằng tuần: so sánh với backtest (winrate, PF, DD, số lệnh/tuần).
- **Điều kiện dừng:** DD vượt 1.5 lần DD backtest; lỗi an toàn (lệnh không SL, vượt giới hạn rủi ro, lệnh trùng); PF dưới 1.0 sau 100 lệnh.
- **Điều kiện qua:** ít nhất 2-3 tháng, ≥ 100 lệnh, kết quả khớp backtest trong sai số hợp lý, không vi phạm an toàn.

## 10. Giai đoạn 6: Thêm Brain/LLM bằng A/B

- Chỉ làm sau khi EA thuần qua forward test.
- Brain chỉ đóng vai trò lọc/giảm size/chặn lệnh (bias vĩ mô, tin tức, phản biện), không tạo lệnh ngoài chiến lược đã kiểm chứng.
- Chạy replay trên tin quá khứ (cẩn thận rò rỉ thông tin tương lai) và so sánh "có Brain" với "không Brain" trên cùng dữ liệu.
- Giữ Brain nếu cải thiện được PF/DD có ý nghĩa thống kê; nếu không thì bỏ.
- Forward test lại 4-8 tuần với Brain bật trước khi dùng tiền thật.

## 11. Giai đoạn 7: Live vốn rất nhỏ

- Chỉ bắt đầu khi giai đoạn 2-5 đạt và checklist an toàn (README mục 14) đã tích đủ.
- Bắt đầu với số tiền bạn chấp nhận mất; giữ rủi ro 0.25-0.5% mỗi lệnh.
- Tăng vốn từng bước theo kết quả thực, không tăng sau vài ngày thắng.

## 12. Lưu ý riêng cho tài khoản 500 USD

- 0.5% rủi ro là 2.5 USD. Lot tối thiểu 0.01 của XAUUSD với SL 10 USD đã là 10 USD (2%). Bot phải bỏ lệnh khi lot tính ra nhỏ hơn lot tối thiểu, không ép lên.
- Với lot 0.01-0.02, partial close 50% không thực hiện được; cân nhắc TP cố định.
- Giới hạn tổng rủi ro mở 2% tương đương khoảng 10 USD, tức chỉ chạy được vài lệnh cùng lúc.
- Ưu tiên ít symbol, SL hợp lý (không quá rộng), tránh giờ tin lớn.

## 13. Gói hồ sơ gửi review vòng sau

Trước khi nhờ review, chuẩn bị đủ:

- [ ] Link repo và hash commit cuối cùng trên nhánh làm việc
- [ ] Danh sách thay đổi (mỗi mục A1-A13: đã sửa/không sửa, vì sao)
- [ ] Kết quả test T1-T18 (bảng đạt/không + log Experts liên quan)
- [ ] Kết quả `pytest` của phần Python
- [ ] Báo cáo HTML gốc của Strategy Tester, file `.set`, và bảng tổng hợp mục 6 đã điền
- [ ] Ma trận quyết định mục 8
- [ ] Nhật ký forward test (nếu đã bắt đầu)
- [ ] README đã cập nhật theo kiến trúc mới
- [ ] Danh sách câu hỏi hoặc điểm bạn muốn mình soi kỹ

## 14. Phụ lục: Trạng thái các lỗi đã phát hiện

| Lỗi | Trạng thái (theo commit db39bd2) |
| --- | --- |
| OnTradeTransaction không xử lý deal đóng lệnh | Đã sửa (commit 3462b03) |
| CalcLot ép lot tối thiểu (MQL5) | Đã sửa |
| Partial close lặp lại | Đã sửa (còn vấn đề lot nhỏ, xem A9) |
| Halt không tự reset ngày/tuần | Đã sửa |
| RSI đảo thứ tự, tín hiệu trên nến đang chạy | Đã sửa |
| IsSpreadOk fail-open | Đã sửa |
| Python R:R mean-reversion kém, lặp tín hiệu | Đã sửa (debounce, SL 1.5σ) |
| `.env.example`, Bull/Bear, post\_trade, strategies.yaml | Đã thêm (cần dùng thật, xem mục C và A13) |
| Magic Number làm hỏng bộ lọc | **Chưa sửa (A1)** |
| Python đặt lệnh trực tiếp bỏ qua EA | **Chưa sửa (A2)** |
| Xử lý tín hiệu Brain (cũ/trùng/không kiểm tra) | **Chưa sửa (A3)** |
| News blackout chặn vô thời hạn | **Chưa sửa (A4)** |
| Heartbeat không tác dụng, lệch múi giờ | **Chưa sửa (A5)** |
| account\_state đứng yên khi halt | **Chưa sửa (A6)** |
| Lot Python ép 0.01, sai cho chỉ số/dầu | **Chưa sửa (A7)** |
| Tổng rủi ro mở chưa được kiểm tra | **Chưa sửa (A8)** |
| Session dùng giờ server như UTC | **Chưa sửa (A10)** |
| Báo cáo backtest mâu thuẫn và không tái hiện | **Cần chạy lại (giai đoạn 3)** |

*Tài liệu này không phải lời khuyên tài chính. Giao dịch đòn bẩy có thể mất toàn bộ vốn; hiệu suất quá khứ không đảm bảo kết quả tương lai.*
