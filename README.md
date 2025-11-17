# 🧠 Cortex - AI Chat Assistant

An advanced iOS app that combines artificial intelligence, web search, image analysis, and visual content generation through Image Playground.

## 📋 Table of Contents

- [Key Features](#-key-features)
- [System Requirements](#-system-requirements)
- [Architecture](#-architecture)
- [Detailed Features](#-detailed-features)
- [Technical Components](#-technical-components)
- [Usage](#-usage)
- [Debug and Troubleshooting](#-debug-and-troubleshooting)

---

## 🌟 Key Features

### 1. **Conversational AI Chat**
- Based on **Apple Intelligence** (iOS 18.1+)
- Automatic multilingual support (responds in user's language)
- Conversational context management
- Native Markdown rendering for formatted responses

### 2. **Intelligent Web Search**
- Integrated web search system with **DuckDuckGo**
- **Automatic source count adaptation**:
  - **1 source**: Recipes, tutorials, how-to guides
  - **2 sources**: Comparisons, reviews, deep dives
  - **3 sources**: News, current events, recent updates
- Automatic web content extraction and parsing
- Intelligent search query optimization

### 3. **Image Analysis**
- **OCR (Optical Character Recognition)**: Text extraction from images
- **Object Recognition**: Visual element identification
- **Detailed Analysis**: Complete content description
- Support for PhotosPicker and drag & drop

### 4. **Image Generation with Image Playground**
- Native integration with **Image Playground** (iOS 18.2+)
- Automatic detection of generation requests
- **30+ recognized keywords** in Italian and English:
  - `"create an image of..."`
  - `"generate a picture of..."`
  - `"draw..."`
  - `"crea un'immagine di..."`
  - And many other variants
- Intelligent prompt extraction from user input
- Visual feedback during generation

### 5. **Conversation Management**
- **Chat History**: All conversations are saved
- **Automatic Titles**: AI generates descriptive titles for each chat
- **Multi-thread**: Support for multiple conversations
- **Chat Deletion**: Individual conversation management

---

## 📱 System Requirements

### Minimum Requirements
- **iOS 18.1** or later
- **Apple Intelligence** compatible device:
  - iPhone 15 Pro / Pro Max
  - iPhone 16 / Plus / Pro / Pro Max
  - iPad with M1 chip or later
  - Mac with Apple Silicon

### Requirements for Image Playground
- **iOS 18.2** or later
- Device with **Apple Intelligence enabled**
- Active internet connection

### Required Permissions
- Photo library access (for image analysis)
- Internet connection (for web search and AI)

---

## 🏗️ Architecture

### Project Structure

```
Cortex/
├── CortexApp.swift              # App entry point
├── ContentView.swift            # Main UI and interface management
├── ChatViewModel.swift          # Business logic and coordination
├── ChatMessage.swift            # Data model for messages
├── ImageAnalysisTool.swift      # OCR and object recognition analysis
└── Assets.xcassets/             # Graphic resources
```

### Architectural Pattern
- **MVVM (Model-View-ViewModel)**
  - `ChatMessage`: Model for messages
  - `ContentView`: View layer with SwiftUI
  - `ChatViewModel`: ViewModel with business logic

### Frameworks Used
```swift
import SwiftUI                    // UI Framework
import FoundationModels           // Apple Intelligence
import Combine                    // Reactive programming
import Vision                     // OCR and image analysis
import PhotosUI                   // Photo selection
import UniformTypeIdentifiers     // File type management
import ImagePlayground            // AI image generation
```

---

## 🔧 Detailed Features

### 1. AI Chat System

#### System Prompt
The AI is configured with detailed instructions including:
- **Language Adaptation**: Responds in user's language
- **General Capabilities**: Not limited to news, can answer any question
- **Web Source Management**: Logic for integrating 1, 2, or 3 sources
- **Conversational Style**: Friendly and helpful tone

#### Context Management
```swift
private func chatContextString(limit: Int = 12) -> String
```
- Limits context to **6 recent messages** to avoid overflow
- Includes role (User/Assistant) and content
- Handles placeholders for images (doesn't include bytes)
- Automatic optimization with web search (2 messages instead of 6)

#### Temperature and Parameters
```swift
GenerationOptions(temperature: 0.7)
```
- Balanced temperature for creativity and coherence
- Persistent session with configurable tools

---

### 2. Advanced Web Search

#### Query Detection Algorithm
```swift
private func shouldWebSearch(for text: String) -> Bool
```

**Detected Temporal Indicators:**
- `"today"`, `"yesterday"`, `"tomorrow"`
- `"this week"`, `"this month"`, `"this year"`
- `"recent"`, `"current"`, `"latest"`
- Specific years: `"2024"`, `"2025"`

**Information Requests:**
- `"news"`, `"updates"`, `"breaking"`
- `"price"`, `"cost"`, `"how much"`
- `"weather"`, `"temperature"`, `"forecast"`
- `"event"`, `"events"`, `"happened"`

**Automatic Exclusions:**
- Conversational questions: `"how are you"`, `"hello"`
- Creative requests: `"recipe"`, `"how to"`, `"advice"`
- URLs already present in text

#### 3-Level Source System

##### 🎯 1 Source - Tutorials/Recipes
**When:**
- Query contains: `"recipe"`, `"how to"`, `"tutorial"`, `"guide"`

**Behavior:**
- Downloads **8000 characters** from 1 source
- AI presents content in complete and structured way
- Ideal for step-by-step guides

**Example:**
```
User: "How to make pizza margherita"
System: Searches 1 complete recipe → 8000 characters → Detailed guide
```

##### 🎯 2 Sources - Comparisons/Deep Dives
**When:**
- Generic query without specific indicators
- Comparison or review requests

**Behavior:**
- Downloads **3000 characters** from 2 sources
- AI compares and integrates information
- Balanced view from different perspectives

**Example:**
```
User: "iPhone vs Samsung"
System: Searches 2 reviews → 6000 characters total → Balanced comparison
```

##### 🎯 3 Sources - News/Current Events
**When:**
- Query contains: `"news"`, `"today"`, `"current"`, `"latest"`, `"breaking"`

**Behavior:**
- Downloads **2000 characters** from 3 sources
- AI creates unified summary
- Complete overview from different outlets

**Example:**
```
User: "Today's tech news"
System: Searches 3 outlets → 6000 characters total → General synthesis
```

#### Web Search Pipeline

1. **Connection Test**
   ```swift
   let testURL = URL(string: "https://www.google.com")!
   ```
   - Verifies connectivity before proceeding
   - Error message if offline

2. **DuckDuckGo Query**
   ```swift
   https://duckduckgo.com/html/?q={query}
   ```
   - Custom User-Agent
   - 15-second timeout
   - HTML parsing with regex

3. **URL Extraction**
   - Pattern matching for links with class `result__a`
   - Decode `uddg=` parameter (DuckDuckGo redirect)
   - URL validation (HTTP/HTTPS only)

4. **Content Download**
   ```swift
   private func fetchURLPreview(_ url: URL) async -> String?
   ```
   - 10-second timeout per site
   - Strip HTML tags with regex
   - Decode HTML entities
   - Normalize whitespace
   - 3000 character limit per article

5. **Aggregation**
   - Total limit: **10000 characters**
   - Format: `=== SOURCE N: {title} ===\n\n{content}`
   - User feedback: "✅ Found N sources on the web"

#### Error Handling
```
❌ No connection → "Check your internet connection"
⚠️ HTTP error → "Status code: {code}"
⚠️ No results → "No valid results found"
```

---

### 3. Image Analysis (ImageAnalysisTool)

#### Analysis Modes

```swift
enum AnalysisMode: String, Codable {
    case ocr = "ocr"           // Text only
    case objects = "objects"    // Objects only
    case full = "full"         // Complete
}
```

#### OCR (Optical Character Recognition)

**Framework:** Apple's `Vision`

**Process:**
1. Create `VNRecognizeTextRequest`
2. Configure recognition level: `.accurate`
3. Automatic multi-language support
4. Extract confidence scores

**Output:**
```
📄 DETECTED TEXT:
[Text extracted from image]
```

#### Object Recognition

**Framework:** `Vision` + `VNClassifyImageRequest`

**Process:**
1. Automatic classification with Core ML
2. Confidence threshold: 10%
3. Sort by relevance
4. Format: `{object_name} ({confidence}%)`

**Output:**
```
🔍 DETECTED OBJECTS:
• Cat (95%)
• Pillow (78%)
• Plant (45%)
```

#### Complete Analysis (Default)

Combines OCR + Objects + Image details:

```
📷 IMAGE ANALYSIS

🔍 DETECTED OBJECTS:
• [objects with confidence]

📄 DETECTED TEXT:
[text if present]

📊 DETAILS:
• Dimensions: {width}x{height} px
• Format: {format}
```

#### Error Handling
- Invalid image → `"Unable to analyze image"`
- No text found → Text section omitted
- No objects detected → Objects section omitted

---

### 4. Image Generation (Image Playground)

#### Detection System

**30+ Recognized Keywords:**

**Italian - "Create" Variants:**
- `"crea un'immagine"`, `"crea una foto"`, `"crea immagine"`, `"crea foto"`
- `"creami un'immagine"`, `"creami una foto"`, `"creami immagine"`

**Italian - "Generate" Variants:**
- `"genera un'immagine"`, `"genera una foto"`, `"genera immagine"`
- `"generami un'immagine"`, `"generami una foto"`, `"generami immagine"`

**Italian - "Make/Do" Variants:**
- `"fai un'immagine"`, `"fai una foto"`, `"fammi un'immagine"`, `"fammi una foto"`
- `"fare un'immagine"`, `"fare una foto"`

**Italian - Other:**
- `"disegna"`, `"disegnami"`, `"fai un disegno"`, `"fammi un disegno"`
- `"voglio un'immagine"`, `"voglio una foto"`
- `"mostrami un'immagine"`, `"mostrami una foto"`

**English:**
- `"create an image"`, `"create a picture"`, `"generate an image"`
- `"make an image"`, `"make a picture"`, `"make me an image"`
- `"draw"`, `"draw me"`

#### Prompt Extraction

```swift
private func extractImagePrompt(from text: String) -> String
```

**Examples:**
- Input: `"create an image of a black cat"`
  - Output: `"a black cat"`

- Input: `"generate a picture of sunset on the beach"`
  - Output: `"sunset on the beach"`

- Input: `"draw a mountain"`
  - Output: `"a mountain"`

#### Generation Flow

1. **Detection** (in `send()`)
   ```swift
   if pendingImageData == nil && shouldGenerateImage(text: userText)
   ```

2. **Prompt Extraction**
   ```swift
   let imagePrompt = extractImagePrompt(from: userText)
   ```

3. **User Feedback**
   ```swift
   messages.append(.assistant("🎨 Opening Image Playground..."))
   ```

4. **Sheet Presentation**
   ```swift
   imagePlaygroundPrompt = imagePrompt
   showImagePlayground = true
   ```

5. **Image Playground API**
   ```swift
   .imagePlaygroundSheet(
       isPresented: $isPresented,
       concept: prompt
   ) { url in
       // Success callback
   } onCancellation: {
       // Cancellation callback
   }
   ```

6. **Image Reception**
   - Notification via `NotificationCenter`
   - Name: `"ImagePlaygroundGenerated"`
   - Payload: `["imageData": Data]`

7. **Add to Chat**
   ```swift
   messages.append(.assistantImage(imageData, caption: "✅ Image created!"))
   ```

#### Availability Management

**Environment Check:**
```swift
@Environment(\.supportsImagePlayground) private var supportsImagePlayground
```

**Fallback UI:**
If unavailable, shows:
```
⚠️ Image Playground not available

Requirements:
• iOS 18.2 or later
• Apple Intelligence compatible device
```

**Supported Devices:**
- iPhone 15 Pro / Pro Max
- iPhone 16 / Plus / Pro / Pro Max
- iPad with M1+
- Mac with Apple Silicon

---

### 5. Message and History Management

#### ChatMessage Model

```swift
enum ChatMessage: Identifiable, Hashable {
    case user(String)
    case assistant(String)
    case userImage(Data, caption: String)
    case assistantImage(Data, caption: String)
}
```

**Properties:**
- `id`: Unique UUID
- `text`: Textual content
- `imageData`: Optional image data
- `isUser`: Bool to distinguish sender

#### Markdown Rendering

**Framework:** Native SwiftUI (iOS 15+)

```swift
Text(.init(message.text))
    .textSelection(.enabled)
```

**Support:**
- **Bold**: `**text**`
- **Italic**: `*text*`
- **Inline code**: `` `code` ``
- **Code block**: ``` ```code``` ```
- **Lists**: `- item` or `* item`
- **Headers**: `# H1`, `## H2`, etc.
- **Links**: `[text](url)`

#### Threads and History

**ChatThread Model:**
```swift
struct ChatThread: Identifiable, Hashable {
    let id: UUID
    var title: String
    let date: Date
    var messages: [ChatMessage]
}
```

**Automatic Title Generation:**
```swift
private func generateTitle(for msgs: [ChatMessage]) async -> String
```

**Process:**
1. Takes last 10 messages as context
2. Asks AI for concise title (max 6 words)
3. Temperature: 0.3 (more deterministic)
4. Fallback: First 60 characters of first message or "New chat (date)"

**Management:**
- `history: [ChatThread]` - Array of conversations
- `newChat()` - Archives current and creates new
- `loadChat(_ thread)` - Loads from history
- `deleteChats(at: IndexSet)` - Deletes selected

---

## 🎨 UI Components

### ContentView

**Main Structure:**
```swift
NavigationStack {
    Group {
        if availabilityMessage != nil {
            // Availability error screen
        } else {
            ChatView(vm: vm)
        }
    }
    .toolbar {
        // Buttons: History, Web, New Chat
    }
}
```

### ChatView

**Components:**
- `ScrollView` with `ScrollViewReader`
- Lazy message rendering
- Auto-scroll to latest messages
- Input bar with PhotosPicker
- Web Search toggle
- Keyboard dismissal gesture

**Optimizations:**
```swift
.id(message.id)
.scrollContentBackground(.hidden)
.defaultScrollAnchor(.bottom)
```

### MessageBubbleView

**Layout:**
- User: Right-aligned, blue
- Assistant: Left-aligned, gray
- Image support with captions
- Context menu for copying
- Markdown rendering

**Styles:**
```swift
.foregroundColor(.white)
.background(isUser ? Color.blue : Color.secondary)
.clipShape(RoundedRectangle(cornerRadius: 12))
```

### HistoryListView

**Features:**
- Chat list with SwipeActions
- Sort by date (most recent first)
- Delete with confirmation
- Formatted dates (e.g., "Nov 17, 2025")
- Message count badge

### ImagePlaygroundSheetView

**iOS 18.2+ Only:**
```swift
@available(iOS 18.2, *)
private struct ImagePlaygroundSheetView: View
```

**Implementation:**
```swift
Color.clear
    .imagePlaygroundSheet(
        isPresented: $isPresented,
        concept: prompt
    ) { url in
        // Completion handler
    } onCancellation: {
        // Cancellation handler
    }
```

---

## 🛠️ Usage

### Normal Conversation

```
User: "Explain photosynthesis"
Assistant: [Detailed response with markdown]
```

### Web Search - Tutorial (1 source)

```
User: "How to make pasta carbonara"
System: 🔍 Searching for information on the web...
System: ✅ Found 1 source on the web.
Assistant: [Complete recipe with ingredients and instructions]
```

### Web Search - News (3 sources)

```
User: "Today's tech news"
System: 🔍 Searching for information on the web...
System: ✅ Found 3 sources on the web.
Assistant: [Unified summary of news from 3 outlets]
```

### Image Analysis

```
User: [Attaches photo of a document]
System: [Automatically analyzes]
Assistant: 📷 IMAGE ANALYSIS
         📄 DETECTED TEXT: [extracted text]
         🔍 OBJECTS: Document (98%), Text (95%)
User: "Summarize the content"
Assistant: [Summary based on OCR]
```

### Image Generation

```
User: "Create an image of a medieval castle"
System: 🎨 Opening Image Playground to create the image...
[Image Playground opens with pre-filled prompt]
[User generates the image]
Assistant: [Generated image] ✅ Image created with Image Playground!
```

### Conversation Management

**New Chat:**
- Tap "+" icon in toolbar
- Current chat is automatically archived
- Title generated by AI

**Load Chat:**
- Tap history icon (clock)
- Select a conversation
- Continue from where you left off

**Delete Chat:**
- Swipe left in history list
- Tap "Delete"
- Confirm action

---

## 🐛 Debug and Troubleshooting

### Integrated Logging

**Web Search Debug:**
```
🔍 DEBUG: Starting web search for: [query]
🎯 DEBUG: Will use N source(s) with query: [optimized]
🌐 DEBUG: Testing internet connection...
✅ DEBUG: Connection OK (status: 200)
📄 DEBUG: HTML downloaded: X characters
📋 DEBUG: Found N results
📰 DEBUG: Downloading content from: [title]
✅ DEBUG: Content downloaded (X characters)
```

**Image Generation Debug:**
```
🔍 DEBUG: Checking if '[text]' is an image request...
✅ DEBUG: Image request detected!
📝 DEBUG: Extracted prompt: '[prompt]'
🎨 DEBUG: showImagePlayground = true, should open sheet
```

**AI Response Debug:**
```
📏 DEBUG: Total prompt length: X characters
📏 DEBUG: webContext length: X characters
🤖 DEBUG: Sending request to AI model...
✅ DEBUG: Response received from model
```

### Common Issues

#### 1. AI Not Responding
**Symptom:** No response after sending message

**Possible causes:**
- Apple Intelligence not enabled
- Model not downloaded
- Incompatible device

**Solution:**
- Go to Settings → Apple Intelligence
- Enable Apple Intelligence
- Wait for model download

#### 2. Web Search Not Working
**Symptom:** "❌ Unable to connect to internet"

**Possible causes:**
- No internet connection
- DuckDuckGo blocked
- Firewall/VPN interference

**Solution:**
- Check WiFi/cellular connection
- Temporarily disable VPN
- Check console logs for details

#### 3. Image Playground Not Opening
**Symptom:** Shows "unavailable" or doesn't detect request

**Debug:**
1. Check console for:
   ```
   🔍 DEBUG: Checking if '...' is an image request...
   ```

2. Verify keyword used is in the list

3. Check iOS version:
   ```swift
   if #available(iOS 18.2, *)
   ```

4. Verify `supportsImagePlayground` environment

**Solution:**
- Update to iOS 18.2+
- Use compatible device
- Enable Apple Intelligence

#### 4. OCR Not Extracting Text
**Symptom:** "DETECTED TEXT" section empty

**Possible causes:**
- Blurry image
- Text too small
- Non-standard font
- Unsupported language

**Solution:**
- Use high-resolution images
- Ensure text is readable
- Try with text in major languages (IT, EN)

#### 5. Context Window Exceeded
**Symptom:** Error "An error occurred during response"

**Possible causes:**
- Too much text from web sources
- Conversation too long
- Multiple images in context

**Automatic solution:**
- Context limited to 6 recent messages
- With web search reduced to 2 messages
- Articles limited to 3000 characters
- Total max 10000 web characters

**Manual solution:**
- Start new chat (tap "+")
- Reduce web query

---

## 📊 Limits and Optimizations

### Context Limits
- **Recent messages**: Max 6 (2 with web search)
- **Characters per message**: Max 300 in context
- **Web articles**: Max 3000 characters each
- **Total web**: Max 10000 characters

### Timeouts
- **Connection test**: Immediate
- **DuckDuckGo search**: 15 seconds
- **Article download**: 10 seconds per site
- **AI Response**: No timeout (system managed)

### Performance
- **Lazy rendering**: Only visible messages
- **Image compression**: Automatic from PhotosPicker
- **Memory management**: SwiftUI handles automatically
- **Background tasks**: All operations async

---

## 🔐 Privacy and Security

### User Data
- **No persistent storage**: Chats in memory only
- **No tracking**: Zero analytics
- **No external servers**: Only Apple Intelligence locally

### Image Data
- **Local processing**: Vision framework on-device
- **Not sent to servers**: 100% local analysis
- **Temporary**: Removed with chat deletion

### Web Search
- **DuckDuckGo**: Privacy-focused search engine
- **No tracking**: No cookies or fingerprinting
- **HTTPS only**: Only secure connections

### Apple Intelligence
- **On-device**: Local processing when possible
- **Private Cloud Compute**: For complex requests, but end-to-end encrypted
- **No logging**: Apple doesn't save conversations

---

## 🚀 Future Development

### Planned Features
- [ ] Export conversations (PDF, TXT)
- [ ] Search in chat history
- [ ] Customizable themes (Dark/Light/Custom)
- [ ] Text-to-Speech synthesis
- [ ] Speech-to-Text input
- [ ] Other UI languages support
- [ ] iOS widgets for quick access
- [ ] Shortcuts integration
- [ ] iCloud conversation sync

### Possible Integrations
- [ ] Siri integration
- [ ] Apple Watch companion app
- [ ] iPad split view optimization
- [ ] macOS version
- [ ] Live Activities for image generation
- [ ] Focus Filters

---

## 👨‍💻 Technical Information

### Swift Version
- **Swift 5.9+**
- **SwiftUI 5.0+**

### Deployment Target
- **iOS 18.1** (for Apple Intelligence)
- **iOS 18.2** (for Image Playground)

### Dependencies
- **None**: 100% native Apple frameworks

### Build Configuration
```swift
// Info.plist
NSPhotoLibraryUsageDescription: "To analyze your images"
```

### Code Structure
- **Lines of Code**: ~1500
- **Files**: 6
- **Architecture**: MVVM
- **Test Coverage**: N/A (to be implemented)

---

## 📄 License

Educational project - Copyright © 2025 Alfonso Giuseppe Auriemma

---

## 🙏 Credits

- **Apple Intelligence**: Base AI system
- **Vision Framework**: OCR and object recognition
- **Image Playground**: Image generation
- **DuckDuckGo**: Privacy-focused search engine
- **SwiftUI**: Modern UI framework

---

## 📞 Support

For issues or questions:
1. Check the [Debug and Troubleshooting](#-debug-and-troubleshooting) section
2. Verify [System Requirements](#-system-requirements)
3. Review debug logs in Xcode console

---

**Last updated:** November 17, 2025  
**Version:** 1.0.0
