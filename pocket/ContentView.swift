//
//  ContentView.swift
//  pocket
//
//  Created by avalon-macmini on 4/3/25.
//
//  Refactored to work with ObservableObject ViewModel holding LLM instance
//

import SwiftUI
import LLM // Import the LLM library

// Use top-level Chat and Role types directly from LLM module
// typealias Chat = LLM.Chat // Removed incorrect assumption
// typealias Role = LLM.Role // Removed incorrect assumption

struct ContentView: View {
    // Use @StateObject for the ViewModel lifecycle
    @StateObject private var viewModel = ChatViewModel()
    // State for user input
    @State private var userInput: String = ""
    // State for download progress (only relevant during init)
    @State private var downloadProgress: Double = 0.0

    var body: some View {
        NavigationView {
            Group {
                // Show loading/error view until initialization is complete
                if !viewModel.initializationComplete {
                    if let error = viewModel.loadingError {
                        initializationErrorView(errorDetails: error)
                    } else {
                        loadingView
                    }
                } else {
                    // Show chat view once initialized
                    chatView
                }
            }
            .navigationTitle("Local LLM Chat")
            .navigationBarTitleDisplayMode(.inline)
            // Use .task to handle asynchronous initialization
            .task {
                await viewModel.initializeLLM { progress in
                    // Update progress state on main thread
                    self.downloadProgress = progress
                }
            }
        }
    }

    // MARK: - Subviews

    // View shown during loading/downloading
    private var loadingView: some View {
        VStack(spacing: 15) {
            ProgressView(value: downloadProgress) {
                Text("Loading Model...")
                    .font(.headline)
            } currentValueLabel: {
                // Only show percentage if progress > 0, otherwise it's likely not downloading yet
                if downloadProgress > 0 {
                    Text(String(format: "%.1f%%", downloadProgress * 100))
                }
            }
            .progressViewStyle(.linear)

            Text("Initializing LLM engine...")
                 .font(.footnote)
                 .foregroundColor(.gray)
            if downloadProgress > 0 && downloadProgress < 1 {
                 Text("Downloading model if not cached...")
                     .font(.caption)
                     .foregroundColor(.gray)
            }
        }
        .padding()
    }

    // View shown when viewModel initialization fails
    private func initializationErrorView(errorDetails: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 50, height: 50)
                .foregroundColor(.orange)
            Text("Initialization Failed")
                .font(.headline)
            Text(errorDetails)
                .font(.footnote)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    // Main Chat View (no longer needs viewModel passed explicitly)
    private var chatView: some View {
        VStack { // Main VStack for the chat view
            // Chat message display area using viewModel.history
            ScrollViewReader { proxy in // Use ScrollViewReader to scroll to bottom
                ScrollView {
                    // Chat history view content
                    chatHistoryView
                }
                // Modifiers applied to the ScrollView
                .onChange(of: viewModel.history.count) { _ in
                    // Scroll to the last message in history
                    scrollToBottom(proxy: proxy, id: viewModel.history.count - 1)
                }
                 .onChange(of: viewModel.outputFragment) { _ in
                     // Scroll while streaming if needed (might be jumpy)
                     // Only scroll if we are processing and have a fragment
                     if viewModel.isProcessing && !viewModel.outputFragment.isEmpty {
                         scrollToBottom(proxy: proxy, id: viewModel.history.count) // Scroll to the streaming placeholder ID
                     }
                 }
            } // End ScrollViewReader

            Spacer() // Pushes the input area to the bottom

            // Input area (Now correctly inside the main VStack)
            HStack {
                TextField("Type your message...", text: $userInput)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.leading)
                    .disabled(viewModel.isProcessing) // Disable input while processing

                // Use viewModel.isProcessing to determine button state/action
                if !viewModel.isProcessing { // Show send button if not processing
                    Button {
                        send() // Call send function
                    } label: {
                        Image(systemName: "paperplane.fill")
                    }
                    .padding(.trailing)
                    .disabled(userInput.isEmpty) // Disable button if input is empty
                } else {
                    // Show stop button while processing (isProcessing is true)
                    Button {
                        viewModel.stopProcessing() // Call stopProcessing on viewModel
                    } label: {
                        Image(systemName: "stop.circle.fill")
                    }
                    .padding(.trailing)
                    .foregroundColor(.red)
                }
            }
            .padding(.bottom)

        } // End main VStack
    }

    // Helper ViewBuilder for the ScrollView content
    private var chatHistoryView: some View {
        VStack(alignment: .leading) {
            // Iterate over history
            ForEach(Array(viewModel.history.enumerated()), id: \.offset) { index, chat in
                chatBubble(chat: chat)
                    .id(index) // Assign ID for scrolling
            }
            // Display the streaming output fragment if processing
            if viewModel.isProcessing && !viewModel.outputFragment.isEmpty {
                 streamingOutputBubble(text: viewModel.outputFragment)
                     .id(viewModel.history.count) // Assign ID for scrolling to streaming bubble
            }
        }
        .padding(.horizontal)
    }

    // Helper view for a single chat bubble
    @ViewBuilder
    private func chatBubble(chat: Chat) -> some View {
        HStack {
            if chat.role == .user {
                Spacer() // Push user messages to the right
                Text(chat.content)
                    .padding(10)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    .textSelection(.enabled)
            } else {
                Text(chat.content)
                    .padding(10)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(10)
                    .textSelection(.enabled)
                Spacer() // Keep AI messages to the left
            }
        }
        .padding(.vertical, 2)
    }

     // Helper view for the streaming output bubble
     @ViewBuilder
     private func streamingOutputBubble(text: String) -> some View {
         HStack {
             Text(text)
                 .padding(10)
                 .background(Color.gray.opacity(0.2))
                 .cornerRadius(10)
                 .textSelection(.enabled)
             Spacer() // Keep AI messages to the left
         }
         .padding(.vertical, 2)
     }


    // Function to handle sending the message
    func send() {
        guard !userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        viewModel.sendMessage(userInput)
        userInput = "" // Clear input field immediately
    }

    // Helper function to scroll to the bottom
    func scrollToBottom(proxy: ScrollViewProxy, id: Int) {
         guard id >= 0 else { return }
         // Use DispatchQueue to ensure scrolling happens after the view update
         DispatchQueue.main.async {
             withAnimation {
                 proxy.scrollTo(id, anchor: .bottom)
             }
         }
     }
}

#Preview {
    ContentView()
}
