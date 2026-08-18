# pocket

An LLM in your pocket. A SwiftUI chat app that runs **Gemma 3 4B** entirely on device — no server, no API key, no network once the model is cached.

Built on [LLM.swift](https://github.com/eastriverlee/LLM.swift) (llama.cpp under the hood).

## What it does

- **Chat with a local model.** Tokens stream into the view as they're generated, history scrolls itself, and nothing leaves the device.
- **Fetches its own weights.** First launch pulls `gemma-3-4b-it-Q4_K_M.gguf` from Hugging Face into the app's Documents directory behind a real progress bar — a `URLSessionDownloadDelegate`, not a spinner that lies. Subsequent launches load from disk.
- **Handles the states that actually happen.** Downloading, initializing, initialization *failed* — each is a distinct UI state rather than a hang.

## Prompt template

Gemma's turn markers are configured explicitly, including the stop sequence — the detail that separates a working local chat loop from one that runs on past the end of its turn:

```swift
let gemmaTemplate = Template(
    user: ("<|im_start|>user>\n", ""),
    bot:  ("<|im_start|>assistant>\n", ""),
    stopSequence: "<|im_end|>assistant>",
    systemPrompt: "You are a helpful assistant."
)
```

## Structure

| File | Role |
|---|---|
| `ChatViewModel.swift` | `@MainActor ObservableObject`. Owns model lifecycle, download, template, and generation. Publishes `history`, `isProcessing`, `outputFragment`, `loadingError`, `initializationComplete`. |
| `ContentView.swift` | Pure SwiftUI. Chat transcript, input field, progress and error states. |
| `pocketApp.swift` | App entry point. |

## Running it

1. Open `pocket.xcodeproj` in Xcode.
2. Build to a device or simulator with room for a quantized 4B model — it's a real download and a real memory footprint.
3. Wait out the first-launch download. After that it's offline.

## Related

[`tethr-llmswift`](https://github.com/raja-gamevrs/tethr-llmswift) — my fork of LLM.swift, the library this app sits on, extended with embed-only models for RAG, structured output, and separated chain-of-thought.

## License

MIT
