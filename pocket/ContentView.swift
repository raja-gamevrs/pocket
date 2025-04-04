import SwiftUI
import LLM

class Bot: LLM {
    convenience init?(_ update: @escaping (Double) -> Void) async {
        let systemPrompt = "You are a helpful assistant that responds directly to instructions and questions without asking clarifying questions. Always provide a direct answer or follow instructions exactly as given. Never ask the user for more information. If a task is unclear, make reasonable assumptions and proceed with a response. Keep your answers concise and to the point."
        
        // Create the model with the chatML template
        let model = HuggingFaceModel("unsloth/gemma-3-4b-it-GGUF", .Q5_K_M, template: .chatML(systemPrompt))
        
        // Initialize the bot with the model
        try? await self.init(from: model) { progress in update(progress) }
        
        // Set inference parameters to reduce hallucinations (order matters)
        self.topK = 64               // More restrictive top-K
        self.topP = 0.95            // Slightly more restrictive top-P
        self.temp = 1              // Even lower temperature for more deterministic outputs
        // Set history limit to keep context manageable 
        self.historyLimit = 8        // Keep up to 4 back-and-forth exchanges
        // Override the template to explicitly set the format
        self.template = Template(
            system: ("<|im_start|>system\n", "<|im_end|>\n"),
            user: ("<|im_start|>user\n", "<|im_end|>\n"),
            bot: ("<|im_start|>assistant\n", "<|im_end|>\n"),
            stopSequence: "<|im_end|>",
            systemPrompt: systemPrompt
        )
    }
}

struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let isUser: Bool
    let text: String
    
    static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        lhs.id == rhs.id && lhs.isUser == rhs.isUser && lhs.text == rhs.text
    }
}

struct ContentView: View {
    @State var bot: Bot? = nil
    @State var progress: CGFloat = 0
    @State var messages: [ChatMessage] = []
    @State var inputText: String = ""
    @State var isTyping: Bool = false
    @State var currentResponse: String = ""
    
    func updateProgress(_ progress: Double) {
        self.progress = CGFloat(progress)
    }
    
    var body: some View {
        VStack {
            if let bot {
                chatView(bot)
            } else {
                loadingView
            }
        }
        .padding()
    }
    
    var loadingView: some View {
        VStack {
            Text("Loading Local AI Model...")
                .font(.headline)
                .padding()
            
            ProgressView(value: progress) {
                Text("Downloading model...")
            } currentValueLabel: {
                Text(String(format: "%.2f%%", progress * 100))
            }
            .padding()
            .onAppear() {
                Task {
                    let bot = await Bot(updateProgress)
                    await MainActor.run { self.bot = bot }
                }
            }
        }
    }
    
    func chatView(_ bot: Bot) -> some View {
        VStack {
            Text("Local AI Chat")
                .font(.headline)
                .padding()
            
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(messages) { message in
                            chatBubble(message)
                        }
                        
                        if isTyping {
                            HStack {
                                Text(currentResponse)
                                    .padding(12)
                                    .background(Color(.systemGray5))
                                    .foregroundColor(.primary)
                                    .cornerRadius(18)
                                
                                Spacer()
                            }
                            .id("typing")
                        }
                    }
                    .padding(.horizontal)
                    .onChange(of: messages) { _ in
                        if let lastMessage = messages.last {
                            withAnimation {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: isTyping) { _ in
                        if isTyping {
                            withAnimation {
                                proxy.scrollTo("typing", anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: currentResponse) { _ in
                        if isTyping {
                            withAnimation {
                                proxy.scrollTo("typing", anchor: .bottom)
                            }
                        }
                    }
                }
            }
            
            HStack {
                TextField("Ask something...", text: $inputText)
                    .padding(10)
                    .background(Color(.systemGray6))
                    .cornerRadius(20)
                    .disabled(isTyping)
                
                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .resizable()
                        .frame(width: 30, height: 30)
                        .foregroundColor(.blue)
                }
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isTyping)
            }
            .padding()
        }
    }
    
    func chatBubble(_ message: ChatMessage) -> some View {
        HStack {
            if message.isUser {
                Spacer()
                
                Text(message.text)
                    .padding(12)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(18)
            } else {
                Text(message.text)
                    .padding(12)
                    .background(Color(.systemGray5))
                    .foregroundColor(.primary)
                    .cornerRadius(18)
                
                Spacer()
            }
        }
        .id(message.id)
    }
    
    // Simple utility to clean template tokens
    private func removeTemplateTokens(_ text: String) -> String {
        var cleaned = text
            .replacingOccurrences(of: "<|im_end|>", with: "")
            .replacingOccurrences(of: "<|im_start|>", with: "")
        
        // Check for partial template tokens at the end of the text
        let partialEndTokens = ["<|im", "<|", "im_start", "im_"]
        for token in partialEndTokens {
            if cleaned.hasSuffix(token) {
                cleaned = String(cleaned.dropLast(token.count))
            }
        }
        
        return cleaned
    }
    
    func sendMessage() {
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let bot = bot else { return }
        
        let userMessage = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        messages.append(ChatMessage(isUser: true, text: userMessage))
        inputText = ""
        isTyping = true
        currentResponse = ""
        
        // Track text length to detect runaway generation
        var textLength = 0
        let maxAllowedLength = 2000 // Maximum characters to allow
        var shouldContinueProcessing = true
        
        Task {
            // Use the more advanced respond method for full control over the process
            await bot.respond(to: userMessage, with: { responseStream in
                // Handle the streaming response manually
                for await delta in responseStream {
                    // Skip processing if we've exceeded our limit
                    if !shouldContinueProcessing {
                        continue
                    }
                    
                    // Clean any template tokens from deltas
                    let cleanDelta = removeTemplateTokens(delta)
                    if !cleanDelta.isEmpty {
                        await MainActor.run {
                            currentResponse += cleanDelta
                            textLength += cleanDelta.count
                            
                            // If text gets too long, set flag to stop processing more content
                            if textLength > maxAllowedLength {
                                shouldContinueProcessing = false
                                
                                // Add ellipsis to indicate truncation
                                currentResponse += "..."
                            }
                        }
                    }
                }
                
                // When stream completes, create clean final response
                var finalCleanResponse = removeTemplateTokens(currentResponse)
                
                // Safety check: look for incomplete template markers at the end
                if let range = finalCleanResponse.range(of: "<|", options: .backwards) {
                    let distance = finalCleanResponse.distance(from: range.lowerBound, to: finalCleanResponse.endIndex)
                    if distance < 15 { // If the marker is near the end
                        finalCleanResponse = String(finalCleanResponse[..<range.lowerBound])
                    }
                }
                
                // Update on main thread
                await MainActor.run {
                    if !finalCleanResponse.isEmpty {
                        messages.append(ChatMessage(isUser: false, text: finalCleanResponse))
                    }
                    isTyping = false
                }
                
                return finalCleanResponse
            })
        }
    }
}

#Preview {
    ContentView()
} 
