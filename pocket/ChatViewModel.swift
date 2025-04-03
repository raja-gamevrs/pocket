//
//  ChatViewModel.swift
//  pocket
//
//  Created by Cline on 4/3/25.
//
//  Corrected download delegate, unwrapping, and history comparison.
//

import Foundation
import SwiftUI
import LLM // Import LLM library

// Use top-level types from the LLM module directly
// typealias Chat = LLM.Chat // Removed incorrect assumption
// typealias Role = LLM.Role // Removed incorrect assumption

@MainActor // Ensure UI updates happen on the main thread
class ChatViewModel: ObservableObject {

    // MARK: - Published Properties for UI Binding
    @Published var history: [Chat] = [] // Use top-level Chat type
    @Published var isProcessing: Bool = false
    @Published var outputFragment: String = "" // For streaming output display
    @Published var loadingError: String? = nil
    @Published var initializationComplete: Bool = false

    // MARK: - Private Properties
    private var llm: LLM?
    private let modelDownloadUrl = URL(string: "https://huggingface.co/ggml-org/gemma-3-4b-it-GGUF/resolve/main/gemma-3-4b-it-Q4_K_M.gguf")!
    private let localModelFileName = "gemma-3-4b-it-Q4_K_M.gguf"
    private var downloadDelegate: DownloadDelegate? // Delegate for download progress

    // MARK: - Initialization
    func initializeLLM(updateProgress: @escaping (Double) -> Void) async {
        guard !initializationComplete else { return }

        do {
            // Get local file URL
            guard let documentsUrl = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                throw NSError(domain: "ChatViewModel", code: 101, userInfo: [NSLocalizedDescriptionKey: "Could not access documents directory."])
            }
            let localModelUrl = documentsUrl.appendingPathComponent(localModelFileName)
            print("Local model path: \(localModelUrl.path)")

            // Check if model exists, download if necessary
            if !FileManager.default.fileExists(atPath: localModelUrl.path) {
                print("Model not found locally. Starting download...")
                // Use delegate pattern for download
                try await downloadFileWithDelegate(from: modelDownloadUrl, to: localModelUrl, updateProgress: updateProgress)
                print("Model download complete.")
            } else {
                print("Model found locally.")
                 updateProgress(1.0) // Report 100% if already present
            }

            // --- Initialize LLM from local file ---
            print("Initializing LLM from local file...")
            let systemPrompt = "You are a helpful assistant."
            // Initialize self.llm directly using try, adding sampling parameters.
            self.llm = try LLM(
                from: localModelUrl,
                template: .chatML(systemPrompt),
                // Adjust sampling parameters further - very restrictive sampling
                topK: 10,           // Very low topK
                topP: 0.5,          // Very low topP
                temp: 0.4,          // Keep temperature low
                historyLimit: 512,    // Keep increased history limit
                maxTokenCount: 4096  // Keep reduced max response length
            )

            // Explicitly unwrap self.llm to satisfy the compiler before accessing members
            guard let llmInstance = self.llm else {
                // This should theoretically not happen if the above line didn't throw,
                // but we add it for compiler safety and robustness.
                throw NSError(domain: "ChatViewModel", code: 106, userInfo: [NSLocalizedDescriptionKey: "LLM initialization succeeded but instance is unexpectedly nil."])
            }
            // Now use the guaranteed non-optional llmInstance

            // Assign closures AFTER successful initialization to the non-optional llmInstance
            llmInstance.update = { [weak self] partialOutput in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    if let fragment = partialOutput {
                        self.outputFragment += fragment
                        if !self.isProcessing { self.isProcessing = true }
                    } else {
                        self.outputFragment = ""
                        self.isProcessing = false
                    }
                }
            }

            llmInstance.postprocess = { [weak self] finalOutput in
                DispatchQueue.main.async {
                    print("Postprocess called. Final Output length: \(finalOutput.count)")
                    // Use optional chaining for self.llm within the closure, as self could be nil
                    self?.syncHistory()
                    self?.isProcessing = false
                }
            }

            // Access history from the non-optional llmInstance
            self.history = llmInstance.history // Initial history sync
            self.initializationComplete = true
            self.loadingError = nil
            print("LLM ViewModel initialized successfully.")

        } catch {
            print("Error during LLM initialization or download: \(error)")
            self.loadingError = error.localizedDescription
            self.initializationComplete = false
        }
    }

    // MARK: - File Download Helper (Using Delegate)
    private func downloadFileWithDelegate(from remoteUrl: URL, to localUrl: URL, updateProgress: @escaping (Double) -> Void) async throws {
        // Inform UI that download is starting (progress = 0)
        updateProgress(0)

        // Create delegate instance
        downloadDelegate = DownloadDelegate(progressHandler: updateProgress)

        // Configure URLSession with delegate
        let session = URLSession(configuration: .default, delegate: downloadDelegate, delegateQueue: nil) // Use nil queue for async/await handling

        print("Starting download task...")
        // Create download task
        let downloadTask = session.downloadTask(with: remoteUrl)

        // Use continuation to bridge delegate callbacks with async/await
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            downloadDelegate?.completionHandler = { tempURL, response, error in
                if let error = error {
                    print("Download failed with error: \(error)")
                    continuation.resume(throwing: error)
                    return
                }
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                    print("Download failed with status code: \(statusCode)")
                    let error = NSError(domain: "ChatViewModel", code: 102, userInfo: [NSLocalizedDescriptionKey: "Download failed. Status code: \(statusCode)"])
                    continuation.resume(throwing: error)
                    return
                }
                guard let tempURL = tempURL else {
                    print("Download failed: Temporary URL is nil.")
                    let error = NSError(domain: "ChatViewModel", code: 103, userInfo: [NSLocalizedDescriptionKey: "Download failed: No temporary file URL."])
                    continuation.resume(throwing: error)
                    return
                }

                // Move file and resume continuation
                do {
                    print("Moving downloaded file from \(tempURL) to \(localUrl)")
                    try FileManager.default.createDirectory(at: localUrl.deletingLastPathComponent(), withIntermediateDirectories: true)
                    if FileManager.default.fileExists(atPath: localUrl.path) {
                        try FileManager.default.removeItem(at: localUrl)
                    }
                    try FileManager.default.moveItem(at: tempURL, to: localUrl)
                    // Ensure progress reports 100% on completion via delegate
                    // self.downloadDelegate?.progressHandler(1.0) // Delegate should handle this in didFinishDownloadingFrom
                    print("File moved successfully.")
                    continuation.resume(returning: ())
                } catch {
                    print("Failed to move downloaded file: \(error)")
                    continuation.resume(throwing: error)
                }
            }
            downloadTask.resume() // Start the download
        }
        // Clean up session and delegate after completion/error
        session.finishTasksAndInvalidate()
        downloadDelegate = nil
        print("Download task finished.")
    }


    // MARK: - Public Methods
    func sendMessage(_ text: String) {
        guard let llm = llm else {
            print("Error: LLM not initialized.")
            return
        }
        guard !isProcessing else {
            print("Warning: Already processing, ignoring new message.")
            return
        }

        let userChat = Chat(role: .user, content: text)
        history.append(userChat)
        outputFragment = ""
        isProcessing = true

        Task.detached(priority: .userInitiated) { [weak self] in
            await llm.respond(to: text)
            // Explicitly sync history after respond finishes,
            // in case postprocess timing is inconsistent.
            await self?.syncHistory()
            // Ensure processing is marked false *after* sync, on main thread
            await MainActor.run {
                 self?.isProcessing = false
            }
        }
    }

    func stopProcessing() {
        llm?.stop()
    }

    // MARK: - Private Helpers
    private func syncHistory() {
         guard let llmInstance = self.llm else {
             print("Warning: Attempted to sync history but LLM instance was nil.")
             return
         }
         let llmHistory = llmInstance.history
         print("Syncing history. Current VM history count: \(history.count). LLM history count: \(llmHistory.count)")
         // Log last few messages for comparison (optional, can be verbose)
         // print("VM History Tail: \(history.suffix(4))")
         // print("LLM History Tail: \(llmHistory.suffix(4))")

         // Always update published history from the LLM instance's history
         history = llmHistory
         print("History synced. New VM history count: \(history.count)")
     }
}


// MARK: - Download Delegate Helper Class
class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    var progressHandler: (Double) -> Void
    var completionHandler: ((URL?, URLResponse?, Error?) -> Void)?

    init(progressHandler: @escaping (Double) -> Void) {
        self.progressHandler = progressHandler
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        // Update progress on the main thread
        DispatchQueue.main.async {
            // print("Download Progress: \(progress)") // Debug print
            self.progressHandler(progress)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // This provides the temporary file location. Call completion handler.
        print("Delegate: didFinishDownloadingTo \(location)")
        completionHandler?(location, downloadTask.response, nil)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        // This is called for task completion, including errors. Call completion handler.
        if let error = error {
             print("Delegate: didCompleteWithError \(error)")
        } else {
             print("Delegate: didComplete without error (but might have failed in didFinishDownloadingTo)")
        }
        // If didFinishDownloadingTo was called, completionHandler is already invoked there.
        // Only call completionHandler here if there was an error *before* finishing download.
        if error != nil {
             completionHandler?(nil, task.response, error)
        }
        // Note: If didFinishDownloadingTo succeeded, the completionHandler is called there with the temp URL.
    }
}
