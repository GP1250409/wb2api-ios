import SwiftUI

struct ServerSwitcher: View {
    @EnvironmentObject private var session: SessionStore
    @State private var showingProfiles = false
    var body: some View {
        HStack(spacing: 12) {
            Menu {
                ForEach(session.profiles) { profile in
                    Button { session.selectProfile(profile.id) } label: {
                        Label(profile.name, systemImage: profile.id == session.activeProfileID ? "checkmark.circle.fill" : "server.rack")
                    }
                }
                Divider()
                Button("管理服务器") { showingProfiles = true }
            } label: {
                Label(session.activeProfile.name, systemImage: "server.rack")
                    .font(.headline)
                Image(systemName: "chevron.down").font(.caption)
            }
            Spacer()
            Text(session.backend.title).font(.caption).foregroundStyle(.secondary)
            Button { showingProfiles = true } label: { Image(systemName: "slider.horizontal.3") }
                .accessibilityLabel("管理服务器和独立登录配置")
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .sheet(isPresented: $showingProfiles) { ServerProfilesView() }
    }
}

struct ServerProfilesView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var editor: ServerProfile?
    @State private var pendingDeletion: String?
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(session.profiles) { profile in
                        HStack {
                            Button {
                                session.selectProfile(profile.id)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Label(profile.name, systemImage: profile.id == session.activeProfileID ? "checkmark.circle.fill" : "server.rack")
                                    Text(profile.address).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    Text(profile.backend.title).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                            Spacer()
                            Button { editor = profile } label: { Image(systemName: "pencil") }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("编辑 \(profile.name)")
                        }
                        .swipeActions {
                            if session.profiles.count > 1 {
                                Button("删除", role: .destructive) { pendingDeletion = profile.id }
                            }
                        }
                    }
                } footer: {
                    Text("RN 使用 API Key；DM/Hub 使用面板密码登录。凭据按服务器地址和类型分别保存，切换不会退出另一台。")
                }
            }
            .navigationTitle("服务器登录")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        editor = ServerProfile(id: UUID().uuidString, name: "新服务器", address: "", backend: .panel)
                    } label: { Image(systemName: "plus") }
                }
            }
            .sheet(item: $editor) { ServerProfileEditor(profile: $0) }
            .confirmationDialog("删除此服务器的本机登录配置？", isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }), titleVisibility: .visible) {
                Button("删除本机配置", role: .destructive) {
                    if let id = pendingDeletion { session.removeProfile(id) }
                    pendingDeletion = nil
                }
                Button("取消", role: .cancel) { pendingDeletion = nil }
            } message: { Text("不会删除远端账号、修改服务器密码或退出其他服务器。") }
        }
    }
}

private struct ServerProfileEditor: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss
    @State var profile: ServerProfile
    var body: some View {
        NavigationStack {
            Form {
                TextField("名称", text: $profile.name)
                TextField("https://…", text: $profile.address)
                    .textInputAutocapitalization(.never).keyboardType(.URL).autocorrectionDisabled()
                Picker("后端类型", selection: $profile.backend) {
                    ForEach(BackendKind.allCases) { Text($0.title).tag($0) }
                }
                Text("改变地址或后端类型后需要该站点自己的凭据，不会套用另一台服务器的密钥。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .navigationTitle("编辑服务器")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { session.saveProfile(profile); dismiss() }
                        .disabled(profile.name.trimmingCharacters(in: .whitespaces).isEmpty || profile.url == nil)
                }
            }
        }
    }
}
