# GemmaChat 개발 계획

## 로컬 모델 안정성 — 크래시/리부팅 방어

### 1. 사전 방어 (모델 로드 전)
- `os_proc_available_memory()`로 사용 가능 메모리 확인
- 모델 크기 대비 여유 메모리 부족 시 로드 거부 + "메모리 부족" 안내
- 최소 요구 메모리 기준: 모델 크기 + ~1GB (KV 캐시 + Metal 버퍼)

### 2. 실시간 모니터링 (추론 중)
- `UIApplication.didReceiveMemoryWarningNotification` 감지 → KV 캐시 클리어 + 생성 즉시 중단
- `ProcessInfo.processInfo.thermalState` 감지 → `.serious`/`.critical` 시 추론 일시 중지 + "기기 과열" 안내
- 생성 시간 타임아웃 → 일정 시간 초과 시 자동 중단 + 부분 응답 표시

### 3. 복구 (크래시 후)
- 대화 내역 자동 저장 (UserDefaults 또는 Documents 파일)
- 앱 재시작 시 이전 대화 복원
- 마지막 크래시 감지 → "이전 세션이 비정상 종료됨" 안내 + 컨텍스트 축소 제안
