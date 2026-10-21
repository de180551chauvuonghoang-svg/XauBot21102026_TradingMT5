"""
LLM Client - Groq AI Integration
=================================
Tích hợp Groq Cloud API qua OpenAI-compatible SDK.
Sử dụng model suy luận nhanh (mặc định: openai/gpt-oss-20b).
API Key và cấu hình lấy từ .env (bảo mật, không commit git).
"""
import os
import json
import logging
from typing import Dict, Any, List, Optional
from openai import OpenAI

logger = logging.getLogger("LLMClient")


class LLMClient:
    """
    Client gọi LLM Groq cho Research Agent và Macro Analyst.
    Hỗ trợ cả responses.create và chat.completions.create.
    """

    def __init__(self, api_key: Optional[str] = None, model: Optional[str] = None):
        self.api_key = api_key or os.environ.get("GROQ_API_KEY", "")
        self.base_url = "https://api.groq.com/openai/v1"
        self.model = model or os.environ.get("GROQ_MODEL", "openai/gpt-oss-20b")
        
        self.client = None
        if self.api_key:
            try:
                self.client = OpenAI(
                    api_key=self.api_key,
                    base_url=self.base_url,
                )
                logger.info(f"LLMClient: Đã kết nối Groq API thành công (Model: {self.model})")
            except Exception as e:
                logger.error(f"LLMClient: Lỗi khởi tạo OpenAI client: {e}")
        else:
            logger.warning("LLMClient: GROQ_API_KEY chưa được cấu hình trong .env! Chế độ Fallback quy tắc tĩnh.")

    def is_available(self) -> bool:
        return self.client is not None

    def generate(self, prompt: str, system_prompt: str = "") -> str:
        """
        Gửi prompt tới Groq LLM và nhận câu trả lời văn bản.
        Tự động fallback giữa responses.create và chat.completions.create.
        """
        if not self.is_available():
            return ""

        # Cách 1: Thử client.responses.create (theo cú pháp mẫu mới nhất của Groq/OpenAI)
        try:
            full_input = f"{system_prompt}\n\n{prompt}" if system_prompt else prompt
            resp = self.client.responses.create(
                model=self.model,
                input=full_input,
            )
            if hasattr(resp, "output_text") and resp.output_text:
                return resp.output_text.strip()
        except Exception as e_resp:
            logger.debug(f"responses.create không khả dụng ({e_resp}), chuyển sang chat.completions.create...")

        # Cách 2: client.chat.completions.create (chuẩn tương thích phổ quát)
        try:
            messages = []
            if system_prompt:
                messages.append({"role": "system", "content": system_prompt})
            messages.append({"role": "user", "content": prompt})

            completion = self.client.chat.completions.create(
                model=self.model,
                messages=messages,
                max_tokens=800,
                temperature=0.2,
            )
            content = completion.choices[0].message.content or ""
            # Nếu reasoning model không cho content trực tiếp trong max_tokens, kiểm tra reasoning
            if not content and hasattr(completion.choices[0].message, "reasoning"):
                logger.debug("LLM trả về qua reasoning trace.")
            return content.strip()
        except Exception as e:
            logger.error(f"Lỗi gọi Groq API: {e}")
            return ""

    def analyze_news_sentiment(self, news_items: List[Dict[str, Any]], symbols: List[str]) -> Dict[str, Any]:
        """
        Agent phân tích tin tức tổng hợp từ 4 nguồn và xuất ra cấu trúc JSON:
        - market_regime: Risk-On / Risk-Off / Neutral
        - symbols_bias: Bullish / Bearish / Neutral kèm điểm tin cậy (0-100)
        - key_catalysts: Các động lực vĩ mô chính
        - warning_flags: Cảnh báo tin đột biến, rủi ro địa chính trị
        """
        if not self.is_available() or not news_items:
            # Fallback deterministic khi không có LLM
            return self._heuristic_fallback(news_items, symbols)

        # Chuẩn bị văn bản tóm tắt các tiêu đề tin
        news_text = ""
        for i, item in enumerate(news_items[:20], 1):
            news_text += f"{i}. [{item.get('source')}] {item.get('title')}\n"

        system_prompt = (
            "You are a Senior Quantitative Macro Researcher for a Multi-Asset Trading Fund. "
            "Analyze the provided financial news headlines from 4 sources (ForexFactory, FXStreet, MarketWatch, Google Finance). "
            "You MUST respond ONLY with a valid JSON object without markdown formatting or codeblocks."
        )

        prompt = f"""
Danh sách tin tức mới nhất từ 4 nguồn:
{news_text}

Danh mục tài sản đang theo dõi: {symbols}

Hãy phân tích và trả về đúng JSON theo định dạng sau:
{{
  "macro_sentiment": "RISK_ON" | "RISK_OFF" | "NEUTRAL",
  "dxy_bias": "BULLISH" | "BEARISH" | "NEUTRAL",
  "symbols_bias": {{
    "XAUUSD": {{"bias": "BULLISH"|"BEARISH"|"NEUTRAL", "confidence": 75, "reason": "Lý do ngắn"}},
    "EURUSD": {{"bias": "BULLISH"|"BEARISH"|"NEUTRAL", "confidence": 60, "reason": "Lý do ngắn"}},
    "GBPUSD": {{"bias": "BULLISH"|"BEARISH"|"NEUTRAL", "confidence": 60, "reason": "Lý do ngắn"}},
    "USDJPY": {{"bias": "BULLISH"|"BEARISH"|"NEUTRAL", "confidence": 60, "reason": "Lý do ngắn"}},
    "US30":   {{"bias": "BULLISH"|"BEARISH"|"NEUTRAL", "confidence": 60, "reason": "Lý do ngắn"}},
    "NAS100": {{"bias": "BULLISH"|"BEARISH"|"NEUTRAL", "confidence": 60, "reason": "Lý do ngắn"}},
    "USOIL":  {{"bias": "BULLISH"|"BEARISH"|"NEUTRAL", "confidence": 60, "reason": "Lý do ngắn"}}
  }},
  "warning_flags": ["danh sách cảnh báo rủi ro cao nếu có"],
  "summary": "1-2 câu tóm tắt bức tranh vĩ mô hiện tại"
}}
"""
        raw_output = self.generate(prompt, system_prompt)
        try:
            # Làm sạch nếu model bọc trong ```json ... ```
            cleaned = raw_output
            if "```" in cleaned:
                cleaned = cleaned.split("```")[1]
                if cleaned.startswith("json"):
                    cleaned = cleaned[4:]
                cleaned = cleaned.strip()
            data = json.loads(cleaned)
            return data
        except Exception as e:
            logger.warning(f"Không thể parse JSON từ LLM output ({e}). Trích xuất hoặc dùng fallback.")
            return self._heuristic_fallback(news_items, symbols)

    def _heuristic_fallback(self, news_items: List[Dict[str, Any]], symbols: List[str]) -> Dict[str, Any]:
        """Thuật toán quy tắc cứng dự phòng khi LLM timeout hoặc mất mạng."""
        high_impact_count = sum(1 for n in news_items if n.get("impact") == "HIGH")
        return {
            "macro_sentiment": "NEUTRAL",
            "dxy_bias": "NEUTRAL",
            "symbols_bias": {
                s: {"bias": "NEUTRAL", "confidence": 50, "reason": "Fallback mode (rule-based)"}
                for s in symbols
            },
            "warning_flags": [f"Có {high_impact_count} tin tức tác động cao trong tuần."] if high_impact_count > 0 else [],
            "summary": "Hệ thống hoạt động với phân tích kỹ thuật và lịch kinh tế dự phòng."
        }
