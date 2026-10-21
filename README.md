# MultiAssetEA v2 - Đội Ngũ Giao Dịch Tự Động Đa Tài Sản (MT5 + Python Brain)

> **Cảnh báo rủi ro:** Không có hệ thống nào đảm bảo lợi nhuận. Giao dịch đòn bẩy (Forex, Vàng, Chỉ số, Dầu) có thể làm mất toàn bộ vốn. Tài liệu này không phải lời khuyên tài chính. Chỉ dùng số tiền bạn chấp nhận mất và luôn test trên demo trước.

## Mục lục

1. [Giới thiệu và triết lý thiết kế](#1-giới-thiệu-và-triết-lý-thiết-kế)
2. [Mục tiêu hiệu suất thực tế](#2-mục-tiêu-hiệu-suất-thực-tế)
3. [Kiến trúc Hybrid](#3-kiến-trúc-hybrid-python-brain--mt5-execution)
4. [Các thành viên trong đội ngũ](#4-các-thành-viên-trong-đội-ngũ)
5. [Chiến lược giao dịch](#5-chiến-lược-giao-dịch)
6. [Quản trị rủi ro (Risk Officer)](#6-quản-trị-rủi-ro-risk-officer)
7. [Thực thi lệnh và chốt lời](#7-thực-thi-lệnh-và-chốt-lời)
8. [Quy trình kiểm chứng bắt buộc](#8-quy-trình-kiểm-chứng-bắt-buộc)
9. [Tiêu chí nghiệm thu](#9-tiêu-chí-nghiệm-thu-trước-khi-chạy-tiền-thật)
10. [Cấu trúc thư mục](#10-cấu-trúc-thư-mục)
11. [Hướng dẫn cài đặt](#11-hướng-dẫn-cài-đặt)
12. [Cấu hình mẫu](#12-cấu-hình-mẫu)
13. [Lộ trình triển khai](#13-lộ-trình-triển-khai)
14. [Checklist an toàn trước khi chạy live](#14-checklist-an-toàn-trước-khi-chạy-live)

---

## 1. Giới thiệu và triết lý thiết kế

MultiAssetEA v2 mô phỏng một **đội ngũ trading thực thụ**: có người nghiên cứu tin tức, phân tích vĩ mô, phân tích định lượng, phản biện, ra quyết định, quản trị rủi ro, thực thi và đánh giá sau giao dịch. Hệ thống giao dịch đồng thời nhiều lớp tài sản:

- **Kim loại:** XAUUSD
- **Ngoại tệ:** EURUSD, GBPUSD, USDJPY
- **Chỉ số:** US30, NAS100
- **Hàng hóa:** USOIL

**Nguyên tắc cốt lõi:**

1. **Sống sót trước, lợi nhuận sau.** Mục tiêu là edge dương nhỏ nhưng ổn định, rủi ro kiểm soát chặt.
2. **LLM không trực tiếp bấm lệnh.** LLM chỉ đọc tin, tóm tắt, phản biện và trả về đánh giá có cấu trúc (bias, độ tin cậy, cờ cảnh báo). Quyết định cuối cùng và mọi giới hạn rủi ro do code xác định (deterministic) kiểm soát.
3. **Risk Officer có quyền phủ quyết tuyệt đối**, không phụ thuộc bất kỳ mô hình AI nào.
4. **Mọi lệnh phải có SL cứng trên server broker.** Không dùng Virtual SL làm lớp bảo vệ duy nhất.
5. **Mọi thành phần phải chứng minh giá trị bằng số liệu.** Nếu thêm LLM mà chỉ số không tốt hơn bản không LLM thì loại LLM.

## 2. Mục tiêu hiệu suất thực tế

### Vì sao không đặt mục tiêu "winrate > 80%"

Lợi nhuận phụ thuộc vào **expectancy** = (winrate × lãi TB) − (tỷ lệ thua × lỗ TB).

| Winrate | Lãi TB : Lỗ TB | Kết quả |
|---|---|---|
| 80% | 1 : 4 | Hòa vốn, trừ spread/phí là lỗ |
| 85% | 1 : 5 | Hòa vốn, thua 1 lệnh mất công 5 lệnh thắng |
| 40% | 2 : 1 | Lãi tốt |
| 60% | 1 : 1 | Lãi |

Các bot quảng cáo winrate 85-95% thường dùng martingale, grid, nhồi lệnh không SL hoặc SL cực xa. Equity đẹp nhiều tháng rồi bị quét sạch. Đây là DD cao bị che giấu, trái ngược với yêu cầu DD thấp.

### Mục tiêu đặt ra

| Chỉ số | Mục tiêu hợp lý | Ghi chú |
|---|---|---|
| Winrate | 55-70% (mean-reversion có thể 65-75%) | Trend-following thường 35-45% nhưng R:R ≥ 1:2 |
| Profit Factor | 1.4-1.8 | Trên 2.5 trong backtest thường là overfit |
| Max Drawdown | 8-15% (tốt nhất < 10%) | Giới hạn cứng 10% tổng |
| Lợi nhuận | 20-60%/năm | Muốn cao hơn phải chấp nhận DD cao hơn |
| Sharpe | 1.0-2.0 | |
| **Calmar (lợi nhuận/DD)** | **≥ 2** | **Chỉ số nên tối ưu thay cho winrate** |

### Cách nâng winrate mà không tự sát

1. **Chọn lọc A+ setup:** ít lệnh hơn, chỉ vào khi kỹ thuật, vĩ mô và phản biện đồng thuận. Đây là đòn bẩy lớn nhất.
2. **Mean-reversion trong regime sideway** (RSI/Bollinger/VWAP lệch + ADX thấp), TP gần, R:R không tệ hơn ~1:1.2.
3. **Chốt lời từng phần:** TP1 ở 0.7-1R đóng 50% rồi dời SL về hòa vốn.
4. **Lọc thời gian và tin:** chỉ giao dịch phiên thanh khoản tốt, chặn quanh NFP/CPI/FOMC.
5. **Lọc theo regime:** tắt chiến lược không hợp trạng thái thị trường.

> Dời hòa vốn làm winrate "đẹp" hơn nhưng cắt lãi trung bình. **Đánh giá bằng expectancy và Profit Factor, không bằng winrate.**

## 3. Kiến trúc Hybrid: Python Brain + MT5 Execution

MQL5 không phù hợp chạy LLM, đọc news, scraping. `WebRequest` bị giới hạn (phải whitelist URL, không chạy trong Strategy Tester). Vì vậy dùng kiến trúc lai:

```
┌─────────────────────── PYTHON BRAIN (VPS) ───────────────────────┐
│  Research Agent    → tin tức, lịch kinh tế, COT, yield, DXY, VIX │
│  Macro Analyst     → bối cảnh vĩ mô, risk-on/off, bias tài sản   │
│  Quant Analyst     → regime + tín hiệu kỹ thuật, xác suất        │
│  Bull Agent / Bear Agent → tranh luận, mỗi bên đưa luận điểm     │
│  Head Trader (Judge)  → tổng hợp, chấm điểm tin cậy              │
│  Risk Officer (VETO)  → code cứng, quyền bác bỏ tuyệt đối        │
│  Portfolio Manager    → phân bổ vốn, kiểm tra tương quan         │
│  Post-Trade Analyst   → review lệnh, journal, đề xuất tinh chỉnh │
└──────────────────────────────┬───────────────────────────────────┘
                               │ lệnh đã duyệt (JSON qua ZeroMQ / REST)
┌──────────────────────────────▼───────────────────────────────────┐
│  MT5 EA (MQL5): Execution + Safety Layer                          │
│  Đặt lệnh, SL/TP cứng trên server, trailing, kiểm spread/slippage │
│  Kill-switch cục bộ, heartbeat (mất kết nối Brain → tự bảo vệ)    │
└───────────────────────────────────────────────────────────────────┘
```

**Heartbeat:** nếu EA không nhận được tín hiệu sống từ Brain trong N giây, EA tự chuyển sang chế độ bảo vệ (không mở lệnh mới, siết SL hoặc đóng theo cấu hình).

Có thể thay EA bằng package Python `MetaTrader5` để Brain tự gửi lệnh, nhưng nên giữ một EA nhẹ làm lớp an toàn độc lập.

## 4. Các thành viên trong đội ngũ

| Vai trò | Nhiệm vụ |
|---|---|
| **Research Agent** | Thu thập tin theo lịch (economic calendar, RSS, API tin tài chính), lọc nhiễu, gắn tag tài sản bị ảnh hưởng, đánh giá mức tác động (thấp/vừa/cao) và độ mới |
| **Macro Analyst** | Tổng hợp lãi suất, lạm phát, kỳ vọng Fed, DXY, lợi suất trái phiếu, VIX, giá dầu để ra bias từng lớp tài sản (ví dụ vàng ngược chiều real yield) |
| **Quant Analyst** | Nhận diện regime (trend / range / volatile bằng ADX, độ rộng Bollinger, ATR percentile), chọn chiến lược phù hợp thay vì chạy tất cả |
| **Bull Agent / Bear Agent** | Mỗi bên đưa luận điểm kèm bằng chứng **và điều kiện làm luận điểm sai**. Bear nêu được rủi ro lớn (tin sắp ra, vùng cản mạnh, tương quan xấu) thì giảm size hoặc bỏ lệnh |
| **Head Trader** | Chỉ vào lệnh khi kỹ thuật, vĩ mô và phản biện đồng thuận, điểm tin cậy vượt ngưỡng |
| **Risk Officer** | Quyền phủ quyết, viết bằng code cứng (xem mục 6) |
| **Portfolio Manager** | Phân bổ vốn, kiểm soát tương quan và exposure theo nhóm |
| **Execution Trader** | Đặt lệnh, quản lý SL/TP, chốt lời từng phần, trailing |
| **Post-Trade Analyst** | Ghi lý do vào lệnh, kết quả, MAE/MFE, slippage. Báo cáo ngày/tuần, phát hiện chiến lược hết edge để giảm trọng số hoặc tắt |

**Quy trình ra quyết định:**

```
Research + Macro → Quant (regime + tín hiệu) → Bull vs Bear
→ Head Trader (chấm điểm) → Risk Officer (duyệt/veto/giảm size)
→ Execution → Post-Trade Analyst (journal + học)
```

## 5. Chiến lược giao dịch

Không chạy tất cả chiến lược cùng lúc. **Regime detector** chọn chiến lược phù hợp:

| Regime | Chiến lược | Đặc điểm |
|---|---|---|
| Trend | TrendFollower (EMA đa khung + SuperTrend/ATR) | Winrate thấp hơn, R:R ≥ 1:2 |
| Breakout | SessionBreakout (vùng giá phiên London/New York) | Chỉ vào khi có xác nhận khối lượng/biến động |
| Range | **MeanReversion** (Bollinger/RSI/VWAP + ADX thấp) | Winrate cao hơn, TP gần, SL cứng bắt buộc |
| Volatile bất thường | **Đứng ngoài** hoặc giảm size mạnh | Bảo toàn vốn |

**Hai hướng cấu hình** (chọn một làm mặc định):

- **Hướng A - Scalp/Mean-reversion:** nhiều lệnh, lãi nhỏ, winrate 65-75%, R:R ~1:1.2.
- **Hướng B - Swing/Trend:** ít lệnh, winrate 40-55%, R:R ≥ 1:2, Calmar thường tốt hơn.

## 6. Quản trị rủi ro (Risk Officer)

Đây là phần quan trọng nhất. Viết bằng **code cứng, không phụ thuộc LLM**.

### Giới hạn bắt buộc

| Hạng mục | Giá trị mặc định |
|---|---|
| Rủi ro mỗi lệnh | 0.25-0.5% equity |
| Tổng rủi ro mở | ≤ 2% |
| Lỗ ngày | ≤ 2% (chạm là dừng) |
| Lỗ tuần | ≤ 4% |
| Lỗ tổng (equity-based) | ≤ 10% |
| Exposure theo nhóm tương quan | Giới hạn riêng (USD, risk-on, kim loại) |
| Blackout quanh tin lớn | 15-30 phút trước và sau |
| Spread / swap / slippage | Chặn khi vượt ngưỡng bất thường |

### Các điều CẤM

- Không martingale, không grid nhồi lệnh, không gỡ lệnh bằng cách tăng lot.
- Không có lệnh nào thiếu SL cứng trên server.
- Không tăng size sau chuỗi thua.

### Cơ chế bảo vệ

- **Vol-targeting + fractional Kelly (≤ ¼ Kelly)** thay cho lot cố định; lot tính theo ATR.
- **Giảm size sau chuỗi thua**, tăng dần khi hiệu suất ổn.
- **Quản lý tương quan:** EURUSD/GBPUSD, US30/NAS100, XAUUSD/USD cùng chiều thực chất là một vị thế lớn, cần tính gộp.
- **Kill-switch nhiều tầng:** Telegram `/halt`, mất heartbeat, chạm drawdown, lỗi dữ liệu.
- **Tự dừng nếu DD live vượt 1.5 lần DD backtest**, khi đó edge nhiều khả năng đã biến mất.
- **Prop firm:** nạp thẳng quy tắc (daily/max DD, news rule) vào Risk Officer.
- Kiểm tra giờ giao dịch theo từng tài sản (tránh rollover, giờ đóng cửa chỉ số), số vị thế tối đa, tên symbol khác nhau giữa broker (hậu tố `.m`, `.pro`...).

## 7. Thực thi lệnh và chốt lời

- SL/TP cứng trên server. Virtual SL chỉ là lớp phụ, không thay thế.
- **Chốt lời từng phần:** TP1 (0.7-1R) đóng 50% và dời SL về hòa vốn; phần còn lại trailing theo ATR hoặc cấu trúc giá.
- Giới hạn deviation/slippage khi gửi lệnh; lọc spread trước khi vào.
- Retry có kiểm soát, xử lý mã lỗi trong `Definitions.mqh`.
- Ghi log chi tiết và gửi thông báo Telegram (mở lệnh, đóng lệnh, cảnh báo rủi ro, báo cáo ngày/tuần).

## 8. Quy trình kiểm chứng bắt buộc

1. **Backtest từng chiến lược riêng** với dữ liệu tick chất lượng, có spread, phí, slippage thực tế.
2. **Walk-forward + out-of-sample**, kiểm tra độ nhạy tham số để tránh overfit.
3. **Với phần LLM:** chạy *replay* trên tin quá khứ, kiểm tra rò rỉ thông tin tương lai (look-ahead leakage), so sánh "có LLM" và "không LLM". Không cải thiện thì bỏ.
4. **Forward test demo ≥ 2-3 tháng**, sau đó live với vốn rất nhỏ.
5. **Theo dõi liên tục:** Profit Factor, Sharpe/Sortino, Max DD, expectancy, winrate theo regime.

## 9. Tiêu chí nghiệm thu trước khi chạy tiền thật

Một chiến lược chỉ được lên tài khoản thật khi đạt **đủ** các điều kiện:

- [ ] Tối thiểu 300 lệnh trong backtest, dữ liệu tick, có chi phí thực tế
- [ ] Profit Factor ≥ 1.5, expectancy > 0.2R sau chi phí
- [ ] Max DD ≤ 10%, Calmar ≥ 2
- [ ] Out-of-sample/walk-forward đạt ít nhất 70% so với in-sample
- [ ] Ổn định khi đổi tham số ±20%
- [ ] Forward test demo 2-3 tháng khớp với backtest
- [ ] Nếu có LLM: chỉ số tốt hơn bản không LLM

## 10. Cấu trúc thư mục

```
XAUBOTTRADE/
├── brain/                          # Python - "bộ não"
│   ├── agents/
│   │   ├── research.py             # Research Agent
│   │   ├── macro.py                # Macro Analyst
│   │   ├── quant.py                # Quant Analyst
│   │   ├── bull.py / bear.py       # Phản biện
│   │   ├── head_trader.py          # Tổng hợp, chấm điểm
│   │   └── post_trade.py           # Review sau giao dịch
│   ├── risk/
│   │   ├── risk_officer.py         # Quyền veto, giới hạn DD
│   │   ├── correlation.py          # Exposure theo nhóm tương quan
│   │   └── news_blackout.py        # Chặn giao dịch quanh tin
│   ├── data/
│   │   ├── calendar.py             # Lịch kinh tế
│   │   ├── news_feed.py            # RSS / API tin tức
│   │   └── market_data.py
│   ├── strategies/
│   │   ├── regime.py               # Nhận diện regime
│   │   ├── trend.py
│   │   ├── breakout.py
│   │   └── mean_reversion.py
│   ├── bridge/mt5_bridge.py        # ZeroMQ / REST sang MT5
│   ├── backtest/
│   │   ├── walk_forward.py
│   │   └── llm_replay.py
│   └── journal/                    # trades.db, reports/
├── mql5/                           # MT5 - "tay chân"
│   ├── Include/
│   │   ├── Core/
│   │   │   ├── Definitions.mqh     # Struct, enum, mã lỗi, hằng số
│   │   │   ├── ExecutionEngine.mqh # Đóng/mở lệnh, trailing, break-even
│   │   │   ├── SafetyGuard.mqh     # Kill-switch, heartbeat, giới hạn cục bộ
│   │   │   ├── Bridge.mqh          # Nhận lệnh từ Brain
│   │   │   ├── RiskManager.mqh     # Lot động, circuit breaker cục bộ
│   │   │   ├── PortfolioManager.mqh
│   │   │   └── TelegramNotifier.mqh
│   │   └── Strategies/
│   │       ├── StrategyBase.mqh
│   │       ├── TrendFollowerStrategy.mqh
│   │       └── SessionBreakoutStrategy.mqh
│   └── MultiAssetEA.mq5            # EA mỏng: nhận lệnh + bảo vệ
├── config/
│   ├── symbols.yaml
│   ├── risk.yaml
│   └── sessions.yaml
└── README.md
```

## 11. Hướng dẫn cài đặt

### 11.1. Phần MT5 (EA)

1. Mở MetaTrader 5.
2. Vào **File → Open Data Folder** (hoặc `Ctrl + Shift + D`).
3. Mở thư mục `MQL5/Experts/`.
4. Copy thư mục `XAUBOTTRADE` (phần `mql5/`) vào `MQL5/Experts/`.
5. Mở MetaEditor (`F4`), mở `MultiAssetEA.mq5`, nhấn **Compile** (`F7`).
6. Vào **Tools → Options → Expert Advisors**, bật *Allow WebRequest* và thêm URL cần dùng (nếu EA gọi REST).
7. Bật nút **Algo Trading**.
8. Kéo `MultiAssetEA` vào một biểu đồ bất kỳ (ví dụ XAUUSD, M15). EA giám sát toàn bộ cặp trong danh mục cấu hình.

### 11.2. Phần Python Brain

Yêu cầu: Python 3.10+, MT5 cài trên cùng máy/VPS (Windows), tài khoản broker (demo trước).

```bash
cd XAUBOTTRADE/brain
python -m venv .venv
.venv\Scripts\activate            # Windows
pip install MetaTrader5 pandas numpy pyyaml pyzmq requests feedparser
# Thêm thư viện LLM/API tin tức bạn chọn dùng
```

Thiết lập biến môi trường (không commit lên git):

```
TELEGRAM_BOT_TOKEN=...
TELEGRAM_CHAT_ID=...
LLM_API_KEY=...
NEWS_API_KEY=...
```

Chạy: `python main.py --config ../config` (khởi động ở chế độ **demo** mặc định).

### 11.3. Triển khai VPS

- VPS Windows gần server broker để giảm độ trễ.
- Cấu hình tự khởi động lại MT5 và Brain khi reboot.
- Giám sát heartbeat và cảnh báo Telegram khi mất kết nối.

## 12. Cấu hình mẫu

`config/risk.yaml`

```yaml
risk_per_trade_pct: 0.5        # 0.25 - 0.5
max_open_risk_pct: 2.0
max_daily_loss_pct: 2.0
max_weekly_loss_pct: 4.0
max_total_drawdown_pct: 10.0
kelly_fraction_cap: 0.25
reduce_size_after_losses: 3    # giảm size sau 3 lệnh thua liên tiếp
news_blackout_minutes: {before: 30, after: 30}
max_spread_atr_ratio: 0.15
max_slippage_points: 20
require_hard_sl: true
allow_martingale: false
allow_grid: false
halt_if_live_dd_exceeds_backtest_dd_x: 1.5
heartbeat_timeout_sec: 30
correlation_groups:
  usd_long: [EURUSD, GBPUSD, XAUUSD]
  us_equities: [US30, NAS100]
```

`config/symbols.yaml`

```yaml
symbols:
  - {name: XAUUSD, suffix: "", sessions: [london, newyork]}
  - {name: EURUSD, suffix: "", sessions: [london, newyork]}
  - {name: GBPUSD, suffix: "", sessions: [london, newyork]}
  - {name: USDJPY, suffix: "", sessions: [tokyo, london, newyork]}
  - {name: US30,   suffix: "", sessions: [newyork]}
  - {name: NAS100, suffix: "", sessions: [newyork]}
  - {name: USOIL,  suffix: "", sessions: [newyork]}
```

## 13. Lộ trình triển khai

| Giai đoạn | Nội dung | Kết quả cần đạt |
|---|---|---|
| 1 | Hoàn thiện lõi MQL5: SL cứng, kill-switch, news blackout, logging | EA an toàn, chạy ổn trên demo |
| 2 | Thêm regime detection + mean-reversion; backtest và walk-forward | Từng chiến lược qua tiêu chí mục 9 |
| 3 | Dựng Python Brain: data feed, Research/Macro Agent, bridge sang MT5 | Brain gửi/nhận lệnh ổn định |
| 4 | Thêm Bull/Bear debate, Head Trader, Risk Officer veto, journal | Quy trình ra quyết định hoàn chỉnh |
| 5 | Demo forward test 2-3 tháng, đo "có LLM vs không LLM" | Số liệu chứng minh giá trị từng thành phần |
| 6 | Live vốn nhỏ, Post-Trade Analyst tự động báo cáo, tinh chỉnh dần | Tăng vốn từ từ nếu đạt chỉ số |

## 14. Checklist an toàn trước khi chạy live

- [ ] Mọi lệnh có SL cứng trên server
- [ ] Kill-switch Telegram `/halt` hoạt động
- [ ] Heartbeat mất kết nối → EA tự bảo vệ (đã test)
- [ ] Giới hạn lỗ ngày/tuần/tổng đã được test chạm ngưỡng
- [ ] Blackout tin lớn đã kiểm tra với lịch thật
- [ ] Tên symbol khớp broker (hậu tố, contract size, lot step)
- [ ] Đã forward test demo ≥ 2-3 tháng
- [ ] Bắt đầu bằng vốn rất nhỏ, tăng dần theo kết quả thực
- [ ] API key lưu trong biến môi trường, không đưa vào mã nguồn
- [ ] Có kế hoạch xử lý khi VPS/mạng/MT5 gặp sự cố

---

*Tài liệu này mang tính kỹ thuật, không phải lời khuyên đầu tư. Hiệu suất quá khứ (backtest) không đảm bảo kết quả tương lai.*
