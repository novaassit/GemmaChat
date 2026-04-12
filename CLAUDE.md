# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

On-device iOS chat app running **Google Gemma 4 E2B (Q4_K_M GGUF, ~3.2GB)** via `llama.cpp` with Metal GPU acceleration. SwiftUI front end, no server dependency. Minimum iOS 17.0, Xcode 15.0+ (project.yml pins Xcode 16.0 / Swift 5.9).

## Build & Run

The Xcode project is generated from `project.yml` via [XcodeGen](https://github.com/yonaskolb/XcodeGen). `Package.swift` mirrors the SPM dependency for command-line / SPM tooling, but the app itself is built through `GemmaChat.xcodeproj`.

```bash
# Regenerate the Xcode project after editing project.yml
xcodegen generate

# Open in Xcode
open GemmaChat.xcodeproj

# Command-line build (simulator)
xcodebuild -project GemmaChat.xcodeproj -scheme GemmaChat \
  -destination 'platform=iOS Simulator,name=iPhone 15' build
```

No test target exists yet.

### Loading the model at runtime

The `.gguf` file is **not bundled** — the app scans `Documents/` at launch and loads the first `*.gguf` it finds (`ChatViewModel.modelPath` in `GemmaChat/Views/ChatView.swift`). Place the model there before running:

- **Simulator:** `xcrun simctl get_app_container <DEVICE_ID> com.nova.gemmachat data` → copy GGUF into `Documents/`.
- **Device:** Finder → iPhone → Files → GemmaChat (file sharing is enabled via `UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace` in `Info.plist`).

The `models/` directory in the repo is `.gitignore`d and only used as a download staging area.

## Architecture

Three layers, deliberately small:

1. **`Services/LlamaService.swift`** — `@MainActor ObservableObject` that owns the raw `llama_model` / `llama_context` / `llama_vocab` pointers from the `llama` C module (via the `LlamaSwift` SPM product from `mattt/llama.swift` v2.8760.0). Heavy work (`llama_model_load_from_file`, tokenization, `llama_decode`, sampling loop) runs on detached tasks; only the published `isLoading` / `isGenerating` / `modelLoaded` / `loadError` flags are mutated on the main actor. `generate(messages:)` returns an `AsyncStream<String>` that yields one decoded piece per sampled token.

2. **`Models/ChatMessage.swift`** — plain value type with `.user | .assistant | .system` roles. Messages carry the raw text; the Gemma chat template is applied only at prompt-format time.

3. **`Views/`** — SwiftUI. `ChatView` hosts the `ChatViewModel` (`@MainActor`), which owns the `LlamaService`, the message history, and the streaming buffer (`streamingText`). During generation the in-flight tokens render as a pseudo-message with `id: "streaming"`; when the stream finishes, the accumulated text is appended to `messages` and `streamingText` is cleared. `stopGenerating()` cancels the task and commits whatever partial text was produced.

### Inference details worth knowing before editing `LlamaService`

- **Prompt format is hand-rolled** in `formatPrompt` using Gemma's `<start_of_turn>user|model|system … <end_of_turn>` template and terminated with `<start_of_turn>model\n` to kick off generation. Changing models to a non-Gemma family means rewriting this function (the `<end_of_turn>` EOT token is also how the generation loop terminates, via `llama_vocab_eot`).
- **KV cache is fully reset each turn** via `llama_memory_clear(llama_get_memory(context), true)`. The entire conversation is re-tokenized and re-decoded for every user turn — there is no incremental prefix reuse. This keeps the code simple but is the first thing to change if long-context latency becomes a problem.
- **Sampling chain** is rebuilt per call: temp 0.7 → top-p 0.9 → dist sampler with a fresh random seed. `maxTokens = 512`, `contextSize = 4096`, `n_batch = 512`, threads = `activeProcessorCount − 2`, `n_gpu_layers = 99` (offload everything to Metal).
- `llama_backend_init()` is called on first load and `llama_backend_free()` on `unload()`. `deinit` frees `context`/`model` directly because it can't hop to `@MainActor`; don't add main-actor work there.
- The generation loop manually mutates `batch.token[0]` / `batch.pos[0]` / `batch.logits[0]` instead of calling `llama_batch_clear`/`llama_batch_add` helpers — matches the low-level C API surface exposed by `llama.swift`.

## Dependencies

Single SPM package: [`mattt/llama.swift`](https://github.com/mattt/llama.swift) pinned to `from: 2.8760.0` (matches the upstream `llama.cpp` build number). It re-exports the `llama` C module and the `LlamaSwift` product. Both `Package.swift` and `project.yml` declare it — keep the versions in sync when bumping.
