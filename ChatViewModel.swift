import SwiftUI
import FoundationModels
import Combine
import Vision
import PhotosUI
import UniformTypeIdentifiers
import ImagePlayground

struct ChatThread: Identifiable, Hashable {
    let id: UUID
    var title: String
    let date: Date
    var messages: [ChatMessage]

    init(id: UUID = UUID(), title: String, date: Date = Date(), messages: [ChatMessage]) {
        self.id = id
        self.title = title
        self.date = date
        self.messages = messages
    }
}

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var input: String = ""
    @Published var isResponding: Bool = false
    @Published var availabilityMessage: String? = nil
    @Published var selectedPhoto: PhotosPickerItem? = nil
    @Published var pendingImageData: Data? = nil
    @Published var history: [ChatThread] = []
    @Published var allowWebAccess: Bool = true
    @Published var showImagePlayground: Bool = false
    @Published var imagePlaygroundPrompt: String = ""

    private var session: LanguageModelSession?
    private var tools: [any Tool] = []
    private let systemInstructions: String
    private var cancellables = Set<AnyCancellable>()

    init() {
        systemInstructions = """
        You are an expert conversational assistant, helpful and well-informed. You can help with any question: recipes, advice, explanations, creativity, programming, and much more.
        
        🌍 LANGUAGE:
        ALWAYS respond in the same language the user writes in. If they write in Italian, respond in Italian. If they write in English, respond in English. If they write in any other language, respond in that language.
        
        📚 YOUR CAPABILITIES:
        - You can answer ANY general question: recipes, advice, tutorials, explanations, stories, code, etc.
        - You have access to your vast base knowledge (updated until October 2023)
        - You can be creative, give advice, explain complex concepts
        - You are NOT limited to only news or recent information!
        
        🌐 INTELLIGENT WEB SEARCH:
        The app automatically decides HOW MANY sources are needed based on the type of request:
        
        1 SOURCE - For requests requiring A SINGLE complete answer:
           • Recipes, tutorials, how-to guides
           • Use the ENTIRE source to give detailed and complete instructions
           • Example: "How to make apple pie" → 1 complete recipe with ingredients and procedure
        
        2 SOURCES - For requests requiring COMPARISON or DEEP DIVE:
           • Reviews, comparisons, different opinions
           • Synthesize information from both sources
           • Example: "iPhone vs Samsung" → balanced comparison from 2 perspectives
        
        3 SOURCES - For requests about NEWS or CURRENT EVENTS:
           • Today's news, recent events, updates
           • Create a unified summary from all sources
           • Example: "Today's news" → general summary from 3 different outlets
        
        HOW TO RECOGNIZE WEB DATA:
        - Look for sections like "🌐 WEB INFORMATION FOUND" or "=== SOURCE" in the prompt
        - These contain REAL and UPDATED articles from the internet
        
        HOW TO USE WEB DATA (ADAPT BASED ON NUMBER OF SOURCES):
        - With 1 source: Present the recipe/guide in a complete and structured way
        - With 2 sources: Compare and integrate information to give a complete view
        - With 3 sources: Synthesize key points from all sources in a fluid summary
        - DO NOT include links or URLs
        
        WHEN THERE'S NO WEB DATA:
        - Respond NORMALLY using your base knowledge
        - For general questions (recipes, advice, explanations): always respond!
        - For news/recent events without web data: explain that your knowledge is limited to October 2023
        
        STYLE:
        - Be helpful, friendly and available
        - Develop complete and detailed responses
        - Use a natural and conversational tone
        - Never refuse legitimate requests
        """
        
        // Setup notification observer for Image Playground
        setupImagePlaygroundObserver()
    }
    
    private func setupImagePlaygroundObserver() {
        // Observer for when image is generated
        NotificationCenter.default.publisher(for: NSNotification.Name("ImagePlaygroundGenerated"))
            .sink { [weak self] notification in
                guard let self = self,
                      let imageData = notification.userInfo?["imageData"] as? Data else { return }
                
                Task { @MainActor in
                    // Add generated image to chat
                    self.messages.append(.assistantImage(imageData, caption: "✅ Immagine creata con Image Playground!"))
                }
            }
            .store(in: &cancellables)
    }

    func checkAvailability() {
        let availability = SystemLanguageModel.default.availability
        switch availability {
        case .available:
            availabilityMessage = nil
            tools = []
            session = LanguageModelSession(tools: tools, instructions: systemInstructions)
        case .unavailable:
            availabilityMessage = availabilityText(for: availability)
            session = nil
        @unknown default:
            availabilityMessage = "The model is not available for an unknown reason."
            session = nil
        }
    }
    
    // Rileva se l'utente chiede di creare/generare un'immagine
    private func shouldGenerateImage(text: String) -> Bool {
        let lower = text.lowercased()
        let imageKeywords = [
            // Varianti "crea"
            "crea un'immagine", "crea una foto", "crea immagine", "crea foto", "crea una immagine",
            "creami un'immagine", "creami una foto", "creami immagine", "creami foto",
            // Varianti "genera"
            "genera un'immagine", "genera una foto", "genera immagine", "genera foto", "genera una immagine",
            "generami un'immagine", "generami una foto", "generami immagine", "generami foto",
            // Varianti "fai/fare"
            "fai un'immagine", "fai una foto", "fai immagine", "fai foto", "fai una immagine",
            "fammi un'immagine", "fammi una foto", "fammi immagine", "fammi foto",
            "fare un'immagine", "fare una foto",
            // Varianti "disegna"
            "disegna", "disegnami", "fai un disegno", "fammi un disegno",
            // Varianti "voglio/mostra"
            "voglio un'immagine", "voglio una foto", "mostrami un'immagine", "mostrami una foto",
            // Inglese
            "create an image", "create a picture", "create image", "generate an image", 
            "generate a picture", "draw", "make a picture", "make an image",
            "make me an image", "make me a picture", "draw me"
        ]
        return imageKeywords.contains { lower.contains($0) }
    }
    
    // Estrae il prompt per Image Playground dalla richiesta
    private func extractImagePrompt(from text: String) -> String {
        let lower = text.lowercased()
        
        // Pattern comuni: "crea un'immagine di...", "genera una foto di..."
        let patterns = [
            "crea un'immagine di ", "crea una foto di ", "crea immagine di ", "crea foto di ",
            "genera un'immagine di ", "genera una foto di ", "genera immagine di ", "genera foto di ",
            "disegna ", "fai un disegno di ", "fai una foto di ", "fai un'immagine di ",
            "create an image of ", "create a picture of ", "generate an image of ", "generate a picture of ",
            "draw ", "make a picture of ", "make an image of ",
            "voglio un'immagine di ", "voglio una foto di ", "mostrami un'immagine di "
        ]
        
        for pattern in patterns {
            if let range = lower.range(of: pattern) {
                let startIndex = text.index(text.startIndex, offsetBy: lower.distance(from: lower.startIndex, to: range.upperBound))
                return String(text[startIndex...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        // Fallback: usa tutto il testo
        return text
    }

    func send() {
        let userText = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userText.isEmpty || pendingImageData != nil else { return }
        guard !isResponding else { return }
        
        // 🎨 Rileva richieste di generazione immagini
        print("🔍 DEBUG: Controllo se '\(userText)' è una richiesta di immagine...")
        if pendingImageData == nil && shouldGenerateImage(text: userText) {
            print("✅ DEBUG: Rilevata richiesta di immagine!")
            let imagePrompt = extractImagePrompt(from: userText)
            print("📝 DEBUG: Prompt estratto: '\(imagePrompt)'")
            messages.append(.user(userText))
            input = ""
            
            // Show message and open Image Playground
            messages.append(.assistant("🎨 Opening Image Playground to create the image...\n\nYou'll be able to customize the style and details directly in the Image Playground interface!"))
            imagePlaygroundPrompt = imagePrompt
            showImagePlayground = true
            print("🎨 DEBUG: showImagePlayground = true, should open sheet")
            return
        }
        print("❌ DEBUG: Not an image request, proceeding normally")
        
        guard let session = session, !session.isResponding else { return }
        let attachedData = pendingImageData

        if let data = pendingImageData {
            messages.append(.userImage(data, caption: userText))
        } else {
            messages.append(.user(userText))
        }
        input = ""
        selectedPhoto = nil
        pendingImageData = nil
        isResponding = true

        Task {
            do {
                var prompt: String
                var analysisText: String? = nil
                var webContext: String? = nil
                if let _ = attachedData {
                    if userText.isEmpty {
                        prompt = "There's an attached photo. You don't have direct access to the image; if you don't find a local analysis, ask for a brief description (1-2 sentences) and suggest 2-3 ways you can help, without repeating that you can't see the image."
                    } else {
                        prompt = userText
                        if let url = firstURL(in: userText) {
                            if let preview = await fetchURLPreview(url) {
                                webContext = "Contenuto web da \(url.absoluteString):\n\n" + preview
                            }
                        } else if allowWebAccess {
                            // When web search is active, always search on web
                            messages.append(.assistant("🔍 Searching for information on the web..."))
                            if let searchContext = await performWebSearchContext(query: userText) {
                                // Remove the searching message
                                if messages.last?.text == "🔍 Searching for information on the web..." {
                                    messages.removeLast()
                                }
                                
                                // Check if it's an error message
                                if searchContext.starts(with: "❌") || searchContext.starts(with: "⚠️") {
                                    // Show error to user
                                    messages.append(.assistant(searchContext))
                                } else {
                                    // Success
                                    webContext = searchContext
                                    let newsCount = searchContext.components(separatedBy: "=== NEWS").count - 1
                                    if newsCount > 0 {
                                        messages.append(.assistant("✅ Found \(newsCount) \(newsCount == 1 ? "source" : "sources") on the web."))
                                    }
                                }
                            } else {
                                // Remove message and inform user
                                if messages.last?.text == "🔍 Searching for information on the web..." {
                                    messages.removeLast()
                                }
                                messages.append(.assistant("⚠️ Web search found no results."))
                            }
                        }
                    }
                    // Local analysis (OCR + details)
                    let analysisTool = ImageAnalysisTool(imageProvider: { attachedData })
                    if let analysis = try? await analysisTool.call(arguments: .init(mode: nil)), !analysis.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        analysisText = analysis
                        if userText.isEmpty {
                            prompt = "Below you'll find a local analysis of the image. Use this information to respond helpfully, without repeating that you can't see the image.\n\n" + analysis
                        } else {
                            prompt = "Below you'll find a local analysis of the image. Use this information to respond helpfully, without repeating that you can't see the image.\n\n" + analysis + "\n\nUser: " + userText
                        }
                    }
                } else {
                    // Text content without image
                    prompt = userText
                    if let url = firstURL(in: userText) {
                        if let preview = await fetchURLPreview(url) {
                            webContext = "Contenuto web da \(url.absoluteString):\n\n" + preview
                        }
                    } else if allowWebAccess {
                        // When web search is active, always search on web
                        messages.append(.assistant("🔍 Searching for information on the web..."))
                        if let searchContext = await performWebSearchContext(query: userText) {
                            // Remove the searching message
                            if messages.last?.text == "🔍 Searching for information on the web..." {
                                messages.removeLast()
                            }
                            
                            // Check if it's an error message
                            if searchContext.starts(with: "❌") || searchContext.starts(with: "⚠️") {
                                // Show error to user
                                messages.append(.assistant(searchContext))
                            } else {
                                // Count how many news items were found
                                webContext = searchContext
                                let newsCount = searchContext.components(separatedBy: "=== NEWS").count - 1
                                if newsCount > 0 {
                                    messages.append(.assistant("✅ Found \(newsCount) \(newsCount == 1 ? "source" : "sources") on the web. Analyzing content..."))
                                }
                            }
                        } else {
                            // Remove message and inform user
                            if messages.last?.text == "🔍 Searching for information on the web..." {
                                messages.removeLast()
                            }
                            messages.append(.assistant("⚠️ Web search found no usable results. I'll try to respond with my base knowledge."))
                        }
                    }
                }

                // Display local analysis (if available) to give visibility to user
                if let analysisText {
                    messages.append(.assistant(analysisText))
                }
                if let webContext {
                    // Add web context to prompt
                    prompt = "\(webContext)\n\n━━━\nUSER: \(prompt)"
                    
                    // Log length for debug
                    print("📏 DEBUG: Total prompt length: \(prompt.count) characters")
                    print("📏 DEBUG: webContext length: \(webContext.count) characters")
                }
                // Reduced context when there's web search to avoid token limit
                let contextLimit = webContext != nil ? 2 : 6
                let context = chatContextString(limit: contextLimit)
                let finalPrompt = context + "\n\n" + prompt
                
                print("📏 DEBUG: finalPrompt length: \(finalPrompt.count) characters")
                print("🤖 DEBUG: Sending request to AI model...")
                
                let response = try await session.respond(to: finalPrompt, options: GenerationOptions(temperature: 0.7))
                
                print("✅ DEBUG: Response received from model")
                messages.append(.assistant(response.content))
            } catch {
                print("❌ DEBUG: Error from AI model: \(error)")
                print("❌ DEBUG: Error type: \(type(of: error))")
                messages.append(.assistant("An error occurred while responding. Please try again later.\n\nTechnical details: \(error.localizedDescription)"))
            }
            isResponding = false
        }
    }
    
    func sendImage(data: Data, caption: String = "") {
        guard !isResponding else { return }
        guard let session = session, !session.isResponding else { return }
        
        messages.append(.userImage(data, caption: caption))
        isResponding = true
        
        Task {
            do {
                var prompt: String
                var analysisText: String? = nil
                var webContext: String? = nil
                // Local analysis
                let analysisTool = ImageAnalysisTool(imageProvider: { data })
                if let analysis = try? await analysisTool.call(arguments: .init(mode: nil)), !analysis.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    analysisText = analysis
                    if caption.isEmpty {
                        prompt = "Below you'll find a local analysis of the image. Use this information to respond helpfully.\n\n" + analysis
                    } else {
                        prompt = "Below you'll find a local analysis of the image. Use this information to respond helpfully.\n\n" + analysis + "\n\nUser: " + caption
                    }
                } else {
                    if caption.isEmpty {
                        prompt = "There's an attached photo. You don't have direct access to the image; ask for a brief description (1-2 sentences) and suggest 2-3 ways you can help, without repeating that you can't see the image."
                    } else {
                        prompt = "There's an attached photo. Use the provided description: \(caption). Respond based on context, without repeating that you can't see the image."
                        if let url = firstURL(in: caption) {
                            if let preview = await fetchURLPreview(url) {
                                webContext = "Contenuto web da \(url.absoluteString):\n\n" + preview
                            }
                        } else if allowWebAccess {
                            // When web search is active, always search on web
                            messages.append(.assistant("🔍 Searching for information on the web..."))
                            if let searchContext = await performWebSearchContext(query: caption) {
                                // Remove the searching message
                                if messages.last?.text == "🔍 Searching for information on the web..." {
                                    messages.removeLast()
                                }
                                
                                // Check if it's an error message
                                if searchContext.starts(with: "❌") || searchContext.starts(with: "⚠️") {
                                    // Show error to user
                                    messages.append(.assistant(searchContext))
                                } else {
                                    // Success
                                    webContext = searchContext
                                    let newsCount = searchContext.components(separatedBy: "=== NEWS").count - 1
                                    if newsCount > 0 {
                                        messages.append(.assistant("✅ Found \(newsCount) \(newsCount == 1 ? "source" : "sources") on the web."))
                                    }
                                }
                            } else {
                                // Remove message and inform user
                                if messages.last?.text == "🔍 Searching for information on the web..." {
                                    messages.removeLast()
                                }
                                messages.append(.assistant("⚠️ Web search found no results."))
                            }
                        }
                    }
                }

                // Display local analysis (if available)
                if let analysisText {
                    messages.append(.assistant(analysisText))
                }
                if let webContext {
                    // Add web context to prompt
                    prompt = "\(webContext)\n\n━━━\nUSER: \(prompt)"
                }
                // Reduced context when there's web search
                let contextLimit = webContext != nil ? 2 : 6
                let context = chatContextString(limit: contextLimit)
                let finalPrompt = context + "\n\n" + prompt
                let response = try await session.respond(to: finalPrompt, options: GenerationOptions(temperature: 0.7))
                messages.append(.assistant(response.content))
            } catch {
                messages.append(.assistant("An error occurred while processing the image."))
            }
            isResponding = false
        }
    }

    func newChat() {
        Task { await archiveCurrentChatAndReset() }
    }

    func loadChat(_ thread: ChatThread) {
        // Carica una chat dalla history come chat corrente (non rimuove dalla history)
        messages = thread.messages
    }

    func deleteChats(at offsets: IndexSet) {
        history.remove(atOffsets: offsets)
    }

    private func archiveCurrentChatAndReset() async {
        // If there are no messages, just clear current state
        guard !messages.isEmpty else {
            messages.removeAll()
            input = ""
            pendingImageData = nil
            selectedPhoto = nil
            // Reset AI session even for empty chat
            reset()
            return
        }

        let title = await generateTitle(for: messages)
        let thread = ChatThread(title: title, messages: messages)
        history.insert(thread, at: 0)

        // Clears current chat AND resets AI session
        messages.removeAll()
        input = ""
        pendingImageData = nil
        selectedPhoto = nil
        reset() // Important: resets session to free context
    }

    func reset() {
        messages.removeAll()
        if SystemLanguageModel.default.availability == .available {
            tools = []
            session = LanguageModelSession(tools: tools, instructions: systemInstructions)
        } else {
            session = nil
            availabilityMessage = "The model is not available to reset the conversation."
        }
    }

    private func generateTitle(for msgs: [ChatMessage]) async -> String {
        // Fallback heuristic
        func fallbackTitle() -> String {
            if let first = msgs.first(where: { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })?.text {
                let trimmed = first.trimmingCharacters(in: .whitespacesAndNewlines)
                return String(trimmed.prefix(60))
            }
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            return "New chat (" + formatter.string(from: Date()) + ")"
        }

        // If model is not available or busy, use fallback
        guard SystemLanguageModel.default.availability == .available, let session = session, !session.isResponding else {
            return fallbackTitle()
        }

        // Build brief context from recent messages
        let recent = msgs.suffix(10)
        let contextLines: [String] = recent.map { m in
            let role = m.isUser ? "User" : "Assistant"
            if m.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "[\(role)] (message without text)"
            } else {
                return "[\(role)] \(m.text)"
            }
        }
        let context = contextLines.joined(separator: "\n")
        let titlePrompt = """
        Generate a concise title in English (max 6 words) for this conversation. Avoid quotes, final periods and special characters. Only the title, nothing else.

        Conversation:
        \(context)
        """

        do {
            let response = try await session.respond(to: titlePrompt, options: GenerationOptions(temperature: 0.3))
            var candidate = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            // Normalize title to single line and limit length
            if let newline = candidate.firstIndex(of: "\n") {
                candidate = String(candidate[..<newline])
            }
            if candidate.isEmpty { return fallbackTitle() }
            return String(candidate.prefix(60))
        } catch {
            return fallbackTitle()
        }
    }

    private func availabilityText(for availability: SystemLanguageModel.Availability) -> String {
        switch availability {
        case .available:
            return ""
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return "Your device is not eligible to use this model."
            case .appleIntelligenceNotEnabled:
                return "AI hardware is not enabled on the device."
            case .modelNotReady:
                return "The model is not ready for use."
            @unknown default:
                return "The model is not available."
            }
        @unknown default:
            return "The model is not available."
        }
    }
    
    private func chatContextString(limit: Int = 12) -> String {
        // Takes the last N messages to provide context to the model
        // Reduced default limit to avoid exceeding context window
        let effectiveLimit = min(limit, 6) // Maximum 6 recent messages
        let recent = messages.suffix(effectiveLimit)
        let lines: [String] = recent.map { msg in
            let role = msg.isUser ? "User" : "Assistant"
            if msg.imageData != nil {
                // Don't include image bytes, just a placeholder and optional caption
                if msg.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return "[\(role)] [Attached image]"
                } else {
                    return "[\(role)] [Attached image] \nCaption: \(msg.text)"
                }
            } else {
                // Limit length of each message to save tokens
                let truncated = String(msg.text.prefix(300))
                return "[\(role)] \(truncated)"
            }
        }
        return "Conversation context (last \(recent.count) messages):\n" + lines.joined(separator: "\n\n")
    }

    // MARK: - Web fetch helpers
    private func firstURL(in text: String) -> URL? {
        let types: NSTextCheckingResult.CheckingType = .link
        guard let detector = try? NSDataDetector(types: types.rawValue) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let match = detector.firstMatch(in: text, options: [], range: range)
        if let m = match, let r = Range(m.range, in: text) {
            return URL(string: String(text[r]))
        }
        return nil
    }

    private func fetchURLPreview(_ url: URL) async -> String? {
        do {
            var request = URLRequest(url: url)
            request.setValue("Mozilla/5.0 (iOS) ChatClient", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 10
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
            // Try to decode as UTF-8 text and strip HTML
            if let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) {
                let text = stripHTML(html)
                let trimmed = text.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
                // Limit to 3000 chars per article to avoid huge prompts
                return String(trimmed.prefix(3000))
            }
            return nil
        } catch {
            return nil
        }
    }

    private func stripHTML(_ html: String) -> String {
        var s = html
        // Remove scripts and styles
        s = s.replacingOccurrences(of: "<script[\\s\\S]*?</script>", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "<style[\\s\\S]*?</style>", with: "", options: .regularExpression)
        // Replace <br> and <p> with newlines
        s = s.replacingOccurrences(of: "<br[ /]*>", with: "\n", options: .regularExpression)
        s = s.replacingOccurrences(of: "</p>", with: "\n\n", options: .regularExpression)
        // Strip other tags
        s = s.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        // Decode common HTML entities (basic subset)
        let entities: [String: String] = [
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&#39;": "'"
        ]
        for (k, v) in entities { s = s.replacingOccurrences(of: k, with: v) }
        // Normalize whitespace
        s = s.replacingOccurrences(of: "\u{00A0}", with: " ") // non-breaking space
        s = s.replacingOccurrences(of: "[ \t]{2,}", with: " ", options: .regularExpression)
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return s
    }
    
    // MARK: - Web search helpers
    private func shouldWebSearch(for text: String) -> Bool {
        let lowered = text.lowercased()
        
        // Non cercare se c'è già un URL esplicito
        if lowered.contains("http://") || lowered.contains("https://") { return false }
        
        // Non cercare per domande molto generiche, conversazionali o richieste comuni che non necessitano web
        let excludePatterns = [
            "come stai", "ciao", "buongiorno", "buonasera", "grazie", "prego",
            "chi sei", "cosa puoi fare", "aiutami", "spiegami come",
            "ricetta", "ricette", "come si fa", "come fare", "come si prepara",
            "consiglio", "consigli", "suggerimento", "suggerimenti",
            "racconta", "scrivi", "crea", "inventa", "spiega"
        ]
        if excludePatterns.contains(where: { lowered.contains($0) }) { return false }
        
        // Cerca per indicatori temporali recenti
        let temporalIndicators = [
            "oggi", "ieri", "domani", "questa settimana", "questo mese", "quest'anno",
            "recente", "recenti", "attuale", "attuali", "ora", "adesso",
            "2024", "2025", "ultime", "ultimo", "ultima"
        ]
        
        // Cerca per richieste di informazioni specifiche che richiedono dati aggiornati
        let informationRequests = [
            "notizie", "notizia", "news", "novità",
            "prezzo", "costo", "quanto costa",
            "uscito", "uscita", "pubblicato", "annunciato",
            "evento", "eventi", "accaduto", "successo",
            "meteo", "tempo", "temperatura"
        ]
        
        // SOLO se contiene indicatori temporali O richieste specifiche di info aggiornate
        let hasTemporalIndicator = temporalIndicators.contains(where: { lowered.contains($0) })
        let hasInfoRequest = informationRequests.contains(where: { lowered.contains($0) })
        
        // Rimosso il controllo generico per "?" perché troppo ampio
        return hasTemporalIndicator || hasInfoRequest
    }

    private func performWebSearchContext(query: String) async -> String? {
        print("🔍 DEBUG: Inizio ricerca web per: \(query)")
        
        // Decidi quante fonti servono in base alla query (logica semplice e diretta)
        let lower = query.lowercased()
        let (numSources, optimizedQuery): (Int, String)
        
        if lower.contains("ricetta") || lower.contains("recipe") || lower.contains("come fare") || lower.contains("how to") || lower.contains("tutorial") || lower.contains("come si fa") {
            numSources = 1
            optimizedQuery = query
            print("🎯 DEBUG: Rilevata richiesta tutorial/ricetta - userò 1 fonte")
        } else if lower.contains("notizie") || lower.contains("news") || lower.contains("oggi") || lower.contains("attualità") || lower.contains("ultime") {
            numSources = 3
            optimizedQuery = query
            print("🎯 DEBUG: Rilevata richiesta notizie - userò 3 fonti")
        } else {
            numSources = 2
            optimizedQuery = query
            print("🎯 DEBUG: Richiesta generica - userò 2 fonti")
        }
        
        print("🎯 DEBUG: Userò \(numSources) fonte/i con query: \(optimizedQuery)")
        
        // Test connessione internet prima
        let testURL = URL(string: "https://www.google.com")!
        do {
            print("🌐 DEBUG: Test connessione internet...")
            let (_, testResponse) = try await URLSession.shared.data(from: testURL)
            if let http = testResponse as? HTTPURLResponse {
                print("✅ DEBUG: Connessione OK (status: \(http.statusCode))")
            }
        } catch {
            print("❌ DEBUG: Nessuna connessione internet: \(error)")
            return "❌ ERRORE: Impossibile connettersi a internet. Verifica la connessione."
        }
        
        // Usa la query ottimizzata dall'AI
        guard let q = optimizedQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://duckduckgo.com/html/?q=\(q)") else {
            print("❌ DEBUG: Impossibile codificare la query")
            return nil
        }
        
        do {
            print("🌐 DEBUG: Scaricamento risultati da DuckDuckGo...")
            var request = URLRequest(url: url)
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 15
            
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                print("❌ DEBUG: Risposta non HTTP")
                return nil
            }
            
            print("📡 DEBUG: Status code: \(http.statusCode)")
            
            guard (200..<300).contains(http.statusCode) else {
                print("❌ DEBUG: Risposta HTTP non valida: \(http.statusCode)")
                return "⚠️ Il motore di ricerca ha rifiutato la richiesta (status: \(http.statusCode))"
            }
            
            guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
                print("❌ DEBUG: Impossibile decodificare HTML")
                return nil
            }
            
            print("📄 DEBUG: HTML scaricato: \(html.count) caratteri")
            
            let results = parseDuckDuckGoResults(html: html)
            print("📋 DEBUG: Trovati \(results.count) risultati")
            
            guard !results.isEmpty else {
                print("❌ DEBUG: Nessun risultato trovato nel parsing")
                return "⚠️ La ricerca non ha trovato risultati validi"
            }
            
            // Usa il numero di fonti deciso dall'AI
            var contentPieces: [String] = []
            var totalChars = 0
            let maxCharsPerSource = numSources == 1 ? 8000 : (numSources == 2 ? 3000 : 2000)
            let maxTotalChars = 10000 // Aumentato perché ora ottimizziamo per fonte
            
            for (index, item) in results.prefix(numSources).enumerated() {
                print("📰 DEBUG: Scaricamento contenuto da: \(item.title)")
                print("🔗 DEBUG: URL: \(item.url.absoluteString)")
                if let preview = await fetchURLPreview(item.url) {
                    print("✅ DEBUG: Contenuto scaricato (\(preview.count) caratteri)")
                    
                    let limitedPreview = String(preview.prefix(maxCharsPerSource))
                    if totalChars + limitedPreview.count < maxTotalChars {
                        contentPieces.append("=== FONTE \(index + 1): \(item.title) ===\n\n\(limitedPreview)")
                        totalChars += limitedPreview.count
                        print("📊 DEBUG: Aggiunta fonte. Totale caratteri: \(totalChars)")
                    } else {
                        print("⚠️ DEBUG: Limite raggiunto, salto questa fonte")
                        break
                    }
                } else {
                    print("❌ DEBUG: Impossibile scaricare contenuto da \(item.url.absoluteString)")
                }
            }
            
            print("📊 DEBUG: Totale notizie scaricate: \(contentPieces.count), totale caratteri: \(totalChars)")
            guard !contentPieces.isEmpty else {
                return "⚠️ Ho trovato \(results.count) risultati ma non sono riuscito a scaricare i contenuti"
            }
            
            // Build rich context with all retrieved content
            var lines: [String] = ["🌐 WEB INFORMATION FOUND FOR: \(query)"]
            lines.append("")
            lines.append("You have the following detailed news available. Analyze them all and create a complete summary:")
            lines.append("")
            lines.append(contentPieces.joined(separator: "\n\n"))
            
            print("✅ DEBUG: Search completed successfully!")
            return lines.joined(separator: "\n")
        } catch {
            print("❌ DEBUG: Error during search: \(error)")
            return "❌ ERROR during search: \(error.localizedDescription)"
        }
    }

    private func parseDuckDuckGoResults(html: String) -> [(title: String, url: URL)] {
        var items: [(String, URL)] = []
        // Match result links
        let pattern = #"<a[^>]*class=\"result__a\"[^>]*href=\"([^"]+)\"[^>]*>(.*?)</a>"#
        let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators])
        let ns = html as NSString
        let matches = regex?.matches(in: html, options: [], range: NSRange(location: 0, length: ns.length)) ?? []
        
        for m in matches {
            guard m.numberOfRanges >= 3 else { continue }
            var href = ns.substring(with: m.range(at: 1))
            let titleHTML = ns.substring(with: m.range(at: 2))
            let title = stripHTML(titleHTML)
            
            // Decodifica HTML entities nell'URL
            href = href.replacingOccurrences(of: "&amp;", with: "&")
            
            // Se l'URL inizia con //, aggiungi https:
            if href.hasPrefix("//") {
                href = "https:" + href
            }
            
            // Se è un redirect di DuckDuckGo, estrai l'URL reale dal parametro uddg
            if href.contains("duckduckgo.com/l/") {
                // Estrai il parametro uddg=...
                if let uddgRange = href.range(of: "uddg="),
                   let endRange = href[uddgRange.upperBound...].range(of: "&") {
                    let realURL = String(href[uddgRange.upperBound..<endRange.lowerBound])
                    if let decoded = realURL.removingPercentEncoding, let url = URL(string: decoded) {
                        print("🔗 DEBUG: URL estratto: \(url.absoluteString)")
                        items.append((title, url))
                        continue
                    }
                } else if let uddgRange = href.range(of: "uddg=") {
                    // Nessun & alla fine, prendi fino alla fine della stringa
                    let realURL = String(href[uddgRange.upperBound...])
                    if let decoded = realURL.removingPercentEncoding, let url = URL(string: decoded) {
                        print("🔗 DEBUG: URL estratto: \(url.absoluteString)")
                        items.append((title, url))
                        continue
                    }
                }
            }
            
            // Prova come URL diretto
            if let url = URL(string: href), ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                print("🔗 DEBUG: URL diretto: \(url.absoluteString)")
                items.append((title, url))
            }
        }
        
        print("📋 DEBUG: Parsing completato, \(items.count) URL validi estratti")
        return items
    }
}

