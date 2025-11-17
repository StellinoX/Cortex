import Foundation

struct ChatMessage: Identifiable, Hashable {
    enum Role: String, Codable, CaseIterable {
        case user
        case assistant
    }
    
    let id: UUID
    let role: Role
    let text: String
    let date: Date
    let imageData: Data?
    
    init(id: UUID = UUID(), role: Role, text: String, date: Date = Date(), imageData: Data? = nil) {
        self.id = id
        self.role = role
        self.text = text
        self.date = date
        self.imageData = imageData
    }
    
    static func user(_ text: String) -> ChatMessage {
        ChatMessage(role: .user, text: text)
    }
    
    static func assistant(_ text: String) -> ChatMessage {
        ChatMessage(role: .assistant, text: text)
    }
    
    static func userImage(_ data: Data, caption: String = "") -> ChatMessage {
        ChatMessage(role: .user, text: caption, imageData: data)
    }
    
    static func assistantImage(_ data: Data, caption: String = "") -> ChatMessage {
        ChatMessage(role: .assistant, text: caption, imageData: data)
    }
    
    var isUser: Bool {
        role == .user
    }
}
