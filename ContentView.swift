//
//  ContentView.swift
//  Challenge
//
//  Created by Alfonso Giuseppe Auriemma on 16/11/25.
//

import SwiftUI
import FoundationModels
import PhotosUI
import ImagePlayground

struct ContentView: View {
    @StateObject private var vm = ChatViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if let message = vm.availabilityMessage {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.yellow)
                        Text("Modello non disponibile")
                            .font(.title2).bold()
                        Text(message)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                        Button("Riprova") { vm.checkAvailability() }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ChatView(vm: vm)
                }
            }
        }
        .task { vm.checkAvailability() }
    }
}

private struct ChatView: View {
    @ObservedObject var vm: ChatViewModel
    @State private var scrollID = UUID()
    @State private var showingHistory = false
    @Environment(\.supportsImagePlayground) private var supportsImagePlayground

    var body: some View {
        VStack(spacing: 0) {
            MessagesList(vm: vm)
            InputBar(vm: vm)
        }
        .navigationTitle("AI Chat")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showingHistory = true
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 18, weight: .semibold))
                }
                .accessibilityLabel("Cronologia chat")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation {
                        vm.newChat()
                    }
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 18, weight: .semibold))
                }
                .accessibilityLabel("Nuova chat")
            }
        }
        .sheet(isPresented: $showingHistory) {
            HistoryView(vm: vm)
        }
        .sheet(isPresented: $vm.showImagePlayground) {
            if #available(iOS 18.2, *), supportsImagePlayground {
                ImagePlaygroundSheetView(
                    prompt: vm.imagePlaygroundPrompt,
                    isPresented: $vm.showImagePlayground
                )
            } else {
                UnavailableImagePlaygroundView(isPresented: $vm.showImagePlayground)
            }
        }
    }
}

// Fallback view when Image Playground is not available
private struct UnavailableImagePlaygroundView: View {
    @Binding var isPresented: Bool
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 64))
                    .foregroundStyle(.orange)
                
                Text("Image Playground non disponibile")
                    .font(.title2.bold())
                
                Text("Image Playground richiede:\n• iOS 18.2 o superiore\n• Dispositivo compatibile con Apple Intelligence")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                Spacer()
                
                Button("Chiudi") {
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Chiudi") {
                        isPresented = false
                    }
                }
            }
        }
    }
}

private struct MessagesList: View {
    @ObservedObject var vm: ChatViewModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(vm.messages) { msg in
                        MessageRow(message: msg)
                            .id(msg.id)
                    }
                    if vm.isResponding, let last = vm.messages.last, last.isUser {
                        HStack(alignment: .center, spacing: 12) {
                            ProgressView()
                                .tint(.blue)
                            Text("Sto pensando…")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .background(.ultraThinMaterial, in: .rect(cornerRadius: 16))
                        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
                        .id("typing")
                    }
                }
                .padding(20)
            }
            .background(
                LinearGradient(
                    colors: [
                        Color(.systemBackground),
                        Color(.systemGray6).opacity(0.3)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .onChange(of: vm.messages.count) { _, _ in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    if let last = vm.messages.last { 
                        proxy.scrollTo(last.id, anchor: .bottom) 
                    } else { 
                        proxy.scrollTo("typing", anchor: .bottom) 
                    }
                }
            }
        }
    }
}

private struct MessageRow: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.isUser { Spacer(minLength: 40) }
            
            // Avatar
            if !message.isUser {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32, height: 32)
                    .overlay {
                        Image(systemName: "sparkles")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                    }
            }
            
            Group {
                if let data = message.imageData, let uiImage = UIImage(data: data) {
                    VStack(alignment: message.isUser ? .trailing : .leading, spacing: 8) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: 300, maxHeight: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
                        if !message.text.isEmpty {
                            RichText(text: message.text)
                                .font(.body)
                                .foregroundStyle(bubbleForeground)
                        }
                    }
                    .padding(14)
                    .background(bubbleBackground, in: .rect(cornerRadius: 18))
                    .shadow(color: shadowColor, radius: 8, x: 0, y: 2)
                } else {
                    RichText(text: message.text)
                        .font(.body)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(bubbleBackground, in: .rect(cornerRadius: 18))
                        .foregroundStyle(bubbleForeground)
                        .shadow(color: shadowColor, radius: 8, x: 0, y: 2)
                }
            }
            
            if message.isUser {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.blue, .cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32, height: 32)
                    .overlay {
                        Image(systemName: "person.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                    }
            }
            
            if !message.isUser { Spacer(minLength: 40) }
        }
        .frame(maxWidth: .infinity, alignment: message.isUser ? .trailing : .leading)
        .transition(.scale.combined(with: .opacity))
    }

    private var bubbleBackground: some ShapeStyle {
        if message.isUser {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [.blue.opacity(0.7), .blue.opacity(0.5)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        } else {
            return AnyShapeStyle(.ultraThinMaterial)
        }
    }

    private var bubbleForeground: Color {
        message.isUser ? .white : .primary
    }
    
    private var shadowColor: Color {
        message.isUser ? .blue.opacity(0.3) : .black.opacity(0.08)
    }
}

private struct InputBar: View {
    @ObservedObject var vm: ChatViewModel

    var body: some View {
        HStack(spacing: 10) {
            // TextField con stile custom
            HStack(spacing: 8) {
                TextField(text: $vm.input, axis: .vertical) {
                    Text("Scrivi un messaggio...")
                        .foregroundStyle(.secondary)
                }
                .font(.body)
                .lineLimit(1...4)
                .disabled(vm.isResponding)
                
                if let data = vm.pendingImageData, let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(alignment: .topTrailing) {
                            Button {
                                withAnimation(.spring(response: 0.3)) {
                                    vm.pendingImageData = nil
                                    vm.selectedPhoto = nil
                                }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundStyle(.white)
                                    .background(Circle().fill(.black.opacity(0.6)))
                            }
                            .offset(x: 6, y: -6)
                        }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: .rect(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(.secondary.opacity(0.2), lineWidth: 1)
            )
            
            // Pulsanti azione
            HStack(spacing: 8) {
                // Toggle ricerca web
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        vm.allowWebAccess.toggle()
                    }
                } label: {
                    Image(systemName: vm.allowWebAccess ? "globe" : "globe")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(vm.allowWebAccess ? .white : .secondary)
                        .frame(width: 44, height: 44)
                        .background(
                            vm.allowWebAccess ?
                            AnyShapeStyle(LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing)) :
                            AnyShapeStyle(.ultraThinMaterial)
                        )
                        .clipShape(Circle())
                        .shadow(color: vm.allowWebAccess ? .blue.opacity(0.3) : .clear, radius: 8, x: 0, y: 2)
                }
                .disabled(vm.isResponding || vm.availabilityMessage != nil)
                .help(vm.allowWebAccess ? "Ricerca web attiva" : "Ricerca web disattivata")
                
                // Photo picker
                PhotosPicker(selection: $vm.selectedPhoto, matching: .images) {
                    Image(systemName: "photo.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }
                .disabled(vm.isResponding || vm.availabilityMessage != nil)
                .onChange(of: vm.selectedPhoto) { _, newItem in
                    guard let item = newItem else { return }
                    Task {
                        if let data = try? await item.loadTransferable(type: Data.self) {
                            await MainActor.run { 
                                withAnimation(.spring(response: 0.3)) {
                                    vm.pendingImageData = data
                                }
                            }
                        }
                    }
                }
                
                // Send button
                Button {
                    vm.send()
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(Circle())
                        .shadow(color: .blue.opacity(0.4), radius: 8, x: 0, y: 4)
                }
                .disabled((vm.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && vm.pendingImageData == nil) || vm.isResponding || vm.availabilityMessage != nil)
                .scaleEffect((vm.input.isEmpty && vm.pendingImageData == nil) ? 0.9 : 1.0)
                .animation(.spring(response: 0.3), value: vm.input.isEmpty && vm.pendingImageData == nil)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThickMaterial)
    }
}

#Preview {
    ContentView()
}

private struct HistoryView: View {
    @ObservedObject var vm: ChatViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if vm.history.isEmpty {
                    ContentUnavailableView(
                        "Nessuna chat salvata",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Quando crei una nuova chat, quella corrente verrà salvata qui con un titolo."))
                } else {
                    List {
                        ForEach(vm.history) { thread in
                            Button {
                                withAnimation {
                                    vm.loadChat(thread)
                                }
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    Circle()
                                        .fill(
                                            LinearGradient(
                                                colors: [.blue, .purple],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .frame(width: 40, height: 40)
                                        .overlay {
                                            Image(systemName: "bubble.left.and.bubble.right.fill")
                                                .font(.system(size: 16))
                                                .foregroundStyle(.white)
                                        }
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(thread.title)
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                            .lineLimit(2)
                                        
                                        HStack(spacing: 4) {
                                            Image(systemName: "clock")
                                                .font(.caption2)
                                            Text(thread.date, style: .relative)
                                                .font(.caption)
                                        }
                                        .foregroundStyle(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                        .onDelete(perform: vm.deleteChats)
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Cronologia")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !vm.history.isEmpty {
                        EditButton()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

private struct RichText: View {
    let text: String

    var body: some View {
        Text(parseMarkdown(text))
            .textSelection(.enabled)
    }

    private func parseMarkdown(_ s: String) -> AttributedString {
        do {
            // SwiftUI's native Markdown parser (iOS 15+)
            // Supports: **bold**, *italic*, `code`, [links](url), # headers, lists, etc.
            return try AttributedString(
                markdown: s,
                options: AttributedString.MarkdownParsingOptions(
                    interpretedSyntax: .inlineOnlyPreservingWhitespace
                )
            )
        } catch {
            // Fallback to plain text if parsing fails
            print("⚠️ Markdown parsing failed: \(error)")
            return AttributedString(s)
        }
    }
}

// Image Playground Sheet View - Using Official API
@available(iOS 18.2, *)
private struct ImagePlaygroundSheetView: View {
    let prompt: String
    @Binding var isPresented: Bool
    
    var body: some View {
        Color.clear
            .imagePlaygroundSheet(
                isPresented: $isPresented,
                concept: prompt
            ) { url in
                // Image generated successfully
                if let imageData = try? Data(contentsOf: url) {
                    // Notify the view model about the new image
                    NotificationCenter.default.post(
                        name: NSNotification.Name("ImagePlaygroundGenerated"),
                        object: nil,
                        userInfo: ["imageData": imageData]
                    )
                }
            } onCancellation: {
                // User cancelled - just close
                isPresented = false
            }
    }
}

