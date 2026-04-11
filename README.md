# Gemma Chat — On-Device iOS Chat App

Gemma 4 E2B (2.3B params)를 iPhone에서 직접 돌리는 채팅앱입니다.

## 구조

```
GemmaChat/
├── Package.swift                    # llama.cpp SPM 의존성
├── GemmaChat/
│   ├── GemmaChatApp.swift          # App entry point
│   ├── Info.plist                   # 파일 공유 활성화
│   ├── Models/
│   │   └── ChatMessage.swift       # 메시지 모델
│   ├── Services/
│   │   └── LlamaService.swift      # llama.cpp 래퍼 (추론 엔진)
│   └── Views/
│       ├── ChatView.swift          # 메인 채팅 화면 + ViewModel
│       ├── MessageBubble.swift     # 말풍선 UI
│       └── InputBar.swift          # 입력창
```

## 셋업

### 1. Xcode에서 열기

```bash
open GemmaChat.xcodeproj  # 또는 Xcode에서 Package.swift 열기
```

### 2. GGUF 모델 다운로드

Hugging Face에서 Gemma 4 E2B GGUF 파일을 받으세요:

```bash
# 예시 (Q4_K_M 양자화 — 약 1.5GB, 아이폰에 적합)
huggingface-cli download google/gemma-4-e2b-it-gguf \
    gemma-4-e2b-it-Q4_K_M.gguf \
    --local-dir ./models
```

또는 직접 다운로드:
- https://huggingface.co/google/gemma-4-e2b-it-gguf

### 3. 모델 파일을 앱에 넣기

**방법 A: 번들에 포함** (개발용)
- GGUF 파일을 Xcode 프로젝트에 드래그
- 파일명을 `gemma-4-e2b.gguf`로 변경

**방법 B: iTunes/Finder 파일 공유** (배포용)
- 빌드 후 iPhone에 설치
- Finder에서 iPhone → 파일 → GemmaChat 폴더에 GGUF 파일 복사

### 4. 빌드 & 실행

- Target: 실제 iPhone (시뮬레이터는 Metal 미지원)
- iOS 17.0+
- Xcode 15.0+

## 참고

- **Metal GPU 가속**: 자동으로 모든 레이어를 GPU에 올립니다
- **Q4_K_M 양자화** 권장: 품질과 크기의 밸런스가 좋음
- **메모리**: E2B Q4는 약 2GB RAM 사용 → iPhone 12 이상 권장
- Gemma 4 chat template (`<start_of_turn>user/model`) 적용됨
