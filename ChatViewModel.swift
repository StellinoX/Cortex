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
        Sei un assistente conversazionale esperto, disponibile e ben informato. Puoi aiutare con qualsiasi domanda: ricette, consigli, spiegazioni, creatività, programmazione, e molto altro.
        
        🌍 LINGUA:
        Rispondi SEMPRE nella stessa lingua in cui l'utente scrive. Se scrive in italiano, rispondi in italiano. Se scrive in inglese, rispondi in inglese. Se scrive in qualsiasi altra lingua, rispondi in quella lingua.
        
        📚 TUE CAPACITÀ:
        - Puoi rispondere a QUALSIASI domanda generale: ricette, consigli, tutorial, spiegazioni, storie, codice, ecc.
        - Hai accesso alla tua vasta conoscenza di base (aggiornata fino a ottobre 2023)
        - Puoi essere creativo, dare consigli, spiegare concetti complessi
        - NON devi limitarti solo a notizie o informazioni recenti!
        
        🌐 RICERCA WEB INTELLIGENTE:
        L'app decide automaticamente QUANTE fonti servono in base al tipo di richiesta:
        
        1 FONTE - Per richieste che richiedono UN'UNICA risposta completa:
           • Ricette, tutorial, guide how-to
           • Usa TUTTA la fonte per dare istruzioni dettagliate e complete
           • Esempio: "Come fare la torta di mele" → 1 ricetta completa con ingredienti e procedimento
        
        2 FONTI - Per richieste che richiedono CONFRONTO o APPROFONDIMENTO:
           • Recensioni, confronti, opinioni diverse
           • Sintetizza le informazioni da entrambe le fonti
           • Esempio: "iPhone vs Samsung" → confronto bilanciato da 2 prospettive
        
        3 FONTI - Per richieste su NOTIZIE o ATTUALITÀ:
           • Notizie del giorno, eventi recenti, aggiornamenti
           • Crea un riassunto unificato da tutte le fonti
           • Esempio: "Notizie di oggi" → riassunto generale da 3 testate diverse
        
        COME RICONOSCERE I DATI WEB:
        - Cerca sezioni come "🌐 INFORMAZIONI TROVATE SUL WEB" o "=== FONTE" nel prompt
        - Questi contengono articoli REALI e AGGIORNATI da internet
        
        COME USARE I DATI WEB (ADATTA IN BASE AL NUMERO DI FONTI):
        - Con 1 fonte: Presenta la ricetta/guida in modo completo e strutturato
        - Con 2 fonti: Confronta e integra le informazioni per dare una visione completa
        - Con 3 fonti: Sintetizza i punti chiave da tutte le fonti in un riassunto fluido
        - NON includere link o URL
        
        QUANDO NON CI SONO DATI WEB:
        - Rispondi NORMALMENTE usando la tua conoscenza di base
        - Per domande generali (ricette, consigli, spiegazioni): rispondi sempre!
        - Per notizie/eventi recenti senza dati web: spiega che la tua conoscenza è limitata a ottobre 2023
        
        STILE:
        - Sii utile, amichevole e disponibile
        - Sviluppa risposte complete e dettagliate
        - Usa un tono naturale e conversazionale
        - Non rifiutare mai richieste legittime
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
            availabilityMessage = "Il modello non è disponibile per un motivo sconosciuto."
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
            
            // Mostra messaggio e apri Image Playground
            messages.append(.assistant("🎨 Sto aprendo Image Playground per creare l'immagine...\n\nPotrai personalizzare lo stile e i dettagli direttamente nell'interfaccia di Image Playground!"))
            imagePlaygroundPrompt = imagePrompt
            showImagePlayground = true
            print("🎨 DEBUG: showImagePlayground = true, dovrebbe aprire il sheet")
            return
        }
        print("❌ DEBUG: Non è una richiesta di immagine, procedo normalmente")
        
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
                        prompt = "C'è una foto allegata. Non hai accesso diretto all'immagine; se non trovi un'analisi locale, chiedi una breve descrizione (1-2 frasi) e proponi 2-3 modi in cui puoi aiutare, senza ripetere che non puoi vedere l'immagine."
                    } else {
                        prompt = userText
                        if let url = firstURL(in: userText) {
                            if let preview = await fetchURLPreview(url) {
                                webContext = "Contenuto web da \(url.absoluteString):\n\n" + preview
                            }
                        } else if allowWebAccess {
                            // Quando la ricerca web è attiva, cerca sempre sul web
                            messages.append(.assistant("🔍 Sto cercando informazioni sul web..."))
                            if let searchContext = await performWebSearchContext(query: userText) {
                                // Rimuovi il messaggio di ricerca in corso
                                if messages.last?.text == "🔍 Sto cercando informazioni sul web..." {
                                    messages.removeLast()
                                }
                                
                                // Verifica se è un messaggio di errore
                                if searchContext.starts(with: "❌") || searchContext.starts(with: "⚠️") {
                                    // Mostra l'errore all'utente
                                    messages.append(.assistant(searchContext))
                                } else {
                                    // Successo
                                    webContext = searchContext
                                    let newsCount = searchContext.components(separatedBy: "=== NOTIZIA").count - 1
                                    if newsCount > 0 {
                                        messages.append(.assistant("✅ Ho trovato \(newsCount) \(newsCount == 1 ? "fonte" : "fonti") sul web."))
                                    }
                                }
                            } else {
                                // Rimuovi il messaggio e informa l'utente
                                if messages.last?.text == "🔍 Sto cercando informazioni sul web..." {
                                    messages.removeLast()
                                }
                                messages.append(.assistant("⚠️ La ricerca web non ha trovato risultati."))
                            }
                        }
                    }
                    // Analisi locale (OCR + dettagli)
                    let analysisTool = ImageAnalysisTool(imageProvider: { attachedData })
                    if let analysis = try? await analysisTool.call(arguments: .init(mode: nil)), !analysis.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        analysisText = analysis
                        if userText.isEmpty {
                            prompt = "Di seguito trovi un'analisi locale dell'immagine. Usa queste informazioni per rispondere in modo utile, senza ripetere che non puoi vedere l'immagine.\n\n" + analysis
                        } else {
                            prompt = "Di seguito trovi un'analisi locale dell'immagine. Usa queste informazioni per rispondere in modo utile, senza ripetere che non puoi vedere l'immagine.\n\n" + analysis + "\n\nUtente: " + userText
                        }
                    }
                } else {
                    // Contenuto testuale senza immagine
                    prompt = userText
                    if let url = firstURL(in: userText) {
                        if let preview = await fetchURLPreview(url) {
                            webContext = "Contenuto web da \(url.absoluteString):\n\n" + preview
                        }
                    } else if allowWebAccess {
                        // Quando la ricerca web è attiva, cerca sempre sul web
                        messages.append(.assistant("🔍 Sto cercando informazioni sul web..."))
                        if let searchContext = await performWebSearchContext(query: userText) {
                            // Rimuovi il messaggio di ricerca in corso
                            if messages.last?.text == "🔍 Sto cercando informazioni sul web..." {
                                messages.removeLast()
                            }
                            
                            // Verifica se è un messaggio di errore
                            if searchContext.starts(with: "❌") || searchContext.starts(with: "⚠️") {
                                // Mostra l'errore all'utente
                                messages.append(.assistant(searchContext))
                            } else {
                                // Conta quante notizie sono state trovate
                                webContext = searchContext
                                let newsCount = searchContext.components(separatedBy: "=== NOTIZIA").count - 1
                                if newsCount > 0 {
                                    messages.append(.assistant("✅ Ho trovato \(newsCount) \(newsCount == 1 ? "fonte" : "fonti") sul web. Analizzo i contenuti..."))
                                }
                            }
                        } else {
                            // Rimuovi il messaggio e informa l'utente
                            if messages.last?.text == "🔍 Sto cercando informazioni sul web..." {
                                messages.removeLast()
                            }
                            messages.append(.assistant("⚠️ La ricerca web non ha trovato risultati utilizzabili. Provo a rispondere con la mia conoscenza di base."))
                        }
                    }
                }

                // Mostra a schermo l'analisi locale (se disponibile) per dare visibilità all'utente
                if let analysisText {
                    messages.append(.assistant(analysisText))
                }
                if let webContext {
                    // Aggiungi il contesto web al prompt
                    prompt = "\(webContext)\n\n━━━\nUSER: \(prompt)"
                    
                    // Log della lunghezza per debug
                    print("📏 DEBUG: Lunghezza prompt totale: \(prompt.count) caratteri")
                    print("📏 DEBUG: Lunghezza webContext: \(webContext.count) caratteri")
                }
                // Ridotto context quando c'è web search per evitare token limit
                let contextLimit = webContext != nil ? 2 : 6
                let context = chatContextString(limit: contextLimit)
                let finalPrompt = context + "\n\n" + prompt
                
                print("📏 DEBUG: Lunghezza finalPrompt: \(finalPrompt.count) caratteri")
                print("🤖 DEBUG: Invio richiesta al modello AI...")
                
                let response = try await session.respond(to: finalPrompt, options: GenerationOptions(temperature: 0.7))
                
                print("✅ DEBUG: Risposta ricevuta dal modello")
                messages.append(.assistant(response.content))
            } catch {
                print("❌ DEBUG: Errore dal modello AI: \(error)")
                print("❌ DEBUG: Tipo errore: \(type(of: error))")
                messages.append(.assistant("Si è verificato un errore durante la risposta. Riprova più tardi.\n\nDettagli tecnici: \(error.localizedDescription)"))
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
                // Analisi locale
                let analysisTool = ImageAnalysisTool(imageProvider: { data })
                if let analysis = try? await analysisTool.call(arguments: .init(mode: nil)), !analysis.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    analysisText = analysis
                    if caption.isEmpty {
                        prompt = "Di seguito trovi un'analisi locale dell'immagine. Usa queste informazioni per rispondere in modo utile.\n\n" + analysis
                    } else {
                        prompt = "Di seguito trovi un'analisi locale dell'immagine. Usa queste informazioni per rispondere in modo utile.\n\n" + analysis + "\n\nUtente: " + caption
                    }
                } else {
                    if caption.isEmpty {
                        prompt = "C'è una foto allegata. Non hai accesso diretto all'immagine; chiedi una breve descrizione (1-2 frasi) e proponi 2-3 modi in cui puoi aiutare, senza ripetere che non puoi vedere l'immagine."
                    } else {
                        prompt = "C'è una foto allegata. Usa la descrizione fornita: \(caption). Rispondi in base al contesto, senza ripetere che non puoi vedere l'immagine."
                        if let url = firstURL(in: caption) {
                            if let preview = await fetchURLPreview(url) {
                                webContext = "Contenuto web da \(url.absoluteString):\n\n" + preview
                            }
                        } else if allowWebAccess {
                            // Quando la ricerca web è attiva, cerca sempre sul web
                            messages.append(.assistant("🔍 Sto cercando informazioni sul web..."))
                            if let searchContext = await performWebSearchContext(query: caption) {
                                // Rimuovi il messaggio di ricerca in corso
                                if messages.last?.text == "🔍 Sto cercando informazioni sul web..." {
                                    messages.removeLast()
                                }
                                
                                // Verifica se è un messaggio di errore
                                if searchContext.starts(with: "❌") || searchContext.starts(with: "⚠️") {
                                    // Mostra l'errore all'utente
                                    messages.append(.assistant(searchContext))
                                } else {
                                    // Successo
                                    webContext = searchContext
                                    let newsCount = searchContext.components(separatedBy: "=== NOTIZIA").count - 1
                                    if newsCount > 0 {
                                        messages.append(.assistant("✅ Ho trovato \(newsCount) \(newsCount == 1 ? "fonte" : "fonti") sul web."))
                                    }
                                }
                            } else {
                                // Rimuovi il messaggio e informa l'utente
                                if messages.last?.text == "🔍 Sto cercando informazioni sul web..." {
                                    messages.removeLast()
                                }
                                messages.append(.assistant("⚠️ La ricerca web non ha trovato risultati."))
                            }
                        }
                    }
                }

                // Mostra a schermo l'analisi locale (se disponibile)
                if let analysisText {
                    messages.append(.assistant(analysisText))
                }
                if let webContext {
                    // Aggiungi il contesto web al prompt
                    prompt = "\(webContext)\n\n━━━\nUSER: \(prompt)"
                }
                // Ridotto context quando c'è web search
                let contextLimit = webContext != nil ? 2 : 6
                let context = chatContextString(limit: contextLimit)
                let finalPrompt = context + "\n\n" + prompt
                let response = try await session.respond(to: finalPrompt, options: GenerationOptions(temperature: 0.7))
                messages.append(.assistant(response.content))
            } catch {
                messages.append(.assistant("Si è verificato un errore nell'elaborazione dell'immagine."))
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
        // Se non ci sono messaggi, basta pulire lo stato corrente
        guard !messages.isEmpty else {
            messages.removeAll()
            input = ""
            pendingImageData = nil
            selectedPhoto = nil
            // Reset della sessione AI anche per chat vuota
            reset()
            return
        }

        let title = await generateTitle(for: messages)
        let thread = ChatThread(title: title, messages: messages)
        history.insert(thread, at: 0)

        // Pulisce la chat corrente E resetta la sessione AI
        messages.removeAll()
        input = ""
        pendingImageData = nil
        selectedPhoto = nil
        reset() // Importante: resetta la sessione per liberare il context
    }

    func reset() {
        messages.removeAll()
        if SystemLanguageModel.default.availability == .available {
            tools = []
            session = LanguageModelSession(tools: tools, instructions: systemInstructions)
        } else {
            session = nil
            availabilityMessage = "Il modello non è disponibile per resettare la conversazione."
        }
    }

    private func generateTitle(for msgs: [ChatMessage]) async -> String {
        // Heuristica di fallback
        func fallbackTitle() -> String {
            if let first = msgs.first(where: { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })?.text {
                let trimmed = first.trimmingCharacters(in: .whitespacesAndNewlines)
                return String(trimmed.prefix(60))
            }
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            return "Nuova chat (" + formatter.string(from: Date()) + ")"
        }

        // Se il modello non è disponibile o è occupato, usa fallback
        guard SystemLanguageModel.default.availability == .available, let session = session, !session.isResponding else {
            return fallbackTitle()
        }

        // Costruisci un breve contesto dai messaggi recenti
        let recent = msgs.suffix(10)
        let contextLines: [String] = recent.map { m in
            let role = m.isUser ? "Utente" : "Assistente"
            if m.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "[\(role)] (messaggio senza testo)"
            } else {
                return "[\(role)] \(m.text)"
            }
        }
        let context = contextLines.joined(separator: "\n")
        let titlePrompt = """
        Genera un titolo conciso in italiano (max 6 parole) per questa conversazione. Evita virgolette, punti finali e caratteri speciali. Solo il titolo, niente altro.

        Conversazione:
        \(context)
        """

        do {
            let response = try await session.respond(to: titlePrompt, options: GenerationOptions(temperature: 0.3))
            var candidate = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            // Normalizza il titolo su una sola riga e limita la lunghezza
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
                return "Il tuo dispositivo non è idoneo per utilizzare questo modello."
            case .appleIntelligenceNotEnabled:
                return "L'hardware AI non è abilitato sul dispositivo."
            case .modelNotReady:
                return "Il modello non è pronto per l'uso."
            @unknown default:
                return "Il modello non è disponibile."
            }
        @unknown default:
            return "Il modello non è disponibile."
        }
    }
    
    private func chatContextString(limit: Int = 12) -> String {
        // Prende gli ultimi N messaggi per fornire contesto al modello
        // Ridotto il limite default per evitare di superare il context window
        let effectiveLimit = min(limit, 6) // Massimo 6 messaggi recenti
        let recent = messages.suffix(effectiveLimit)
        let lines: [String] = recent.map { msg in
            let role = msg.isUser ? "Utente" : "Assistente"
            if msg.imageData != nil {
                // Non includiamo i bytes dell'immagine, solo un segnaposto e l'eventuale didascalia
                if msg.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return "[\(role)] [Immagine allegata]"
                } else {
                    return "[\(role)] [Immagine allegata] \nDidascalia: \(msg.text)"
                }
            } else {
                // Limita la lunghezza di ogni messaggio per risparmiare token
                let truncated = String(msg.text.prefix(300))
                return "[\(role)] \(truncated)"
            }
        }
        return "Contesto conversazione (ultimi \(recent.count) messaggi):\n" + lines.joined(separator: "\n\n")
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
            var lines: [String] = ["🌐 INFORMAZIONI TROVATE SUL WEB PER: \(query)"]
            lines.append("")
            lines.append("Hai a disposizione le seguenti notizie dettagliate. Analizzale tutte e crea un riassunto completo:")
            lines.append("")
            lines.append(contentPieces.joined(separator: "\n\n"))
            
            print("✅ DEBUG: Ricerca completata con successo!")
            return lines.joined(separator: "\n")
        } catch {
            print("❌ DEBUG: Errore durante la ricerca: \(error)")
            return "❌ ERRORE durante la ricerca: \(error.localizedDescription)"
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

