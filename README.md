# Gemma Chat — On-Device iOS Chat App

Google Gemma 4 E2B (2.3B effective params)를 iPhone/iPad에서 직접 구동하는 온디바이스 AI 채팅앱입니다.
llama.cpp + Metal GPU 가속으로 서버 없이 프라이빗하게 작동합니다.

## 주요 특징

- 🔒 **완전 온디바이스** — 서버 불필요, 인터넷 연결 없이 동작
- ⚡ **Metal GPU 가속** — 모든 레이어를 Apple GPU에 오프로드
- 📱 **스트리밍 응답** — AsyncStream 기반 토큰 단위 실시간 출력
- 💬 **Gemma 채팅 템플릿** — `<start_of_turn>user/model` 포맷 적용
- 📁 **파일 공유** — iTunes/Finder를 통한 모델 파일 전송 지원

## 프로젝트 구조

```
GemmaChat/
├── Package.swift                    # llama.swift SPM 의존성 (v2.8760.0)
├── GemmaChat.xcodeproj
├── models/                          # GGUF 모델 파일 (gitignored)
└── GemmaChat/
    ├── GemmaChatApp.swift          # App entry point
    ├── Info.plist                   # 파일 공유 활성화
    ├── Models/
    │   └── ChatMessage.swift       # 메시지 모델 (user/assistant/system)
    ├── Services/
    │   └── LlamaService.swift      # llama.cpp C API 래퍼 (추론 엔진)
    └── Views/
        ├── ChatView.swift          # 메인 채팅 화면 + ViewModel
        ├── MessageBubble.swift     # 말풍선 UI
        └── InputBar.swift          # 입력창
```

## 기술 스택

| 항목 | 상세 |
|------|------|
| LLM | Google Gemma 4 E2B-it (Q4_K_M, ~3.2GB) |
| 추론 엔진 | [llama.cpp](https://github.com/ggerganov/llama.cpp) via [llama.swift](https://github.com/mattt/llama.swift) v2.8760.0 |
| GPU | Metal (Apple Silicon / A-series) |
| UI | SwiftUI |
| 최소 요구사항 | iOS 17.0+, Xcode 15.0+ |
| 샘플링 | Temperature 0.7, Top-P 0.9 |
| 컨텍스트 | 4096 tokens, max generation 512 tokens |

## 셋업

### 1. 프로젝트 열기

```bash
git clone https://github.com/novaassit/GemmaChat.git
cd GemmaChat
open GemmaChat.xcodeproj
```

### 2. GGUF 모델 다운로드

[bartowski/google_gemma-4-E2B-it-GGUF](https://huggingface.co/bartowski/google_gemma-4-E2B-it-GGUF)에서 Q4_K_M 양자화 모델을 받으세요:

```bash
# Python (huggingface_hub)
uv run --with huggingface-hub python -c "
from huggingface_hub import hf_hub_download
hf_hub_download(
    'bartowski/google_gemma-4-E2B-it-GGUF',
    'google_gemma-4-E2B-it-Q4_K_M.gguf',
    local_dir='./models'
)
"
```

또는 직접 다운로드:
```bash
curl -L -o ./models/google_gemma-4-E2B-it-Q4_K_M.gguf \
  "https://huggingface.co/bartowski/google_gemma-4-E2B-it-GGUF/resolve/main/google_gemma-4-E2B-it-Q4_K_M.gguf"
```

### 3. 모델 파일을 앱에 넣기

**시뮬레이터:**
- 앱 빌드 후 `xcrun simctl get_app_container <DEVICE_ID> com.nova.gemmachat data`로 Documents 경로를 찾아 GGUF 파일 복사

**실제 기기:**
- Finder에서 iPhone → 파일 → GemmaChat 폴더에 GGUF 파일 드래그

> 앱은 Documents 폴더에서 `.gguf` 파일을 자동으로 찾아 로드합니다.

### 4. 빌드 & 실행

- Target: iPhone (시뮬레이터 또는 실기기)
- iOS 17.0+, Xcode 15.0+

## 참고

- **Q4_K_M 양자화** 권장 — 품질과 크기의 밸런스가 좋음 (~3.2GB)
- **메모리**: 약 2GB RAM 사용 → iPhone 12 이상 권장
- **Metal GPU**: 자동으로 모든 레이어를 GPU에 오프로드 (`n_gpu_layers = 99`)
- `models/*.gguf`는 `.gitignore`에 포함되어 git에 올라가지 않음

## 라이선스

Gemma 모델은 [Google Gemma Terms of Use](https://ai.google.dev/gemma/terms)를 따릅니다.
