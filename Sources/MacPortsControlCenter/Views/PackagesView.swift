import SwiftUI
import AppKit

// MARK: - PackageFilterTab
public enum PackageFilterTab: String, CaseIterable, Identifiable {
    case all = "All"
    case installed = "Installed"
    case outdated = "Outdated"

    public var id: String { rawValue }
}

// MARK: - PackagesView
public struct PackagesView: View {
    @EnvironmentObject public var appState: AppState

    @State private var searchInput: String = ""
    @State private var selectedFilter: PackageFilterTab = .all
    @State private var isSelectGroupsExpanded: Bool = true
    @State private var packageToUninstall: PortPackageItem? = nil
    @State private var isUninstallAlertPresented: Bool = false
    @State private var feedbackMessage: String? = nil
    @State private var errorMessage: String? = nil

    public init() {}

    private var filteredPackages: [PortPackageItem] {
        switch selectedFilter {
        case .all:
            return appState.packages
        case .installed:
            return appState.packages.filter { $0.isInstalled }
        case .outdated:
            return appState.packages.filter { $0.isOutdated }
        }
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header & Maintenance Actions
                headerSection

                // Notification Banner
                if let feedback = feedbackMessage {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text(feedback)
                            .font(.system(size: 12))
                        Spacer()
                        Button("Dismiss") { feedbackMessage = nil }
                            .buttonStyle(.borderless)
                            .font(.system(size: 11))
                    }
                    .padding(10)
                    .background(Color.green.opacity(0.12))
                    .cornerRadius(8)
                }

                if let error = errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text(error)
                            .font(.system(size: 12))
                        Spacer()
                        Button("Dismiss") { errorMessage = nil }
                            .buttonStyle(.borderless)
                            .font(.system(size: 11))
                    }
                    .padding(10)
                    .background(Color.red.opacity(0.12))
                    .cornerRadius(8)
                }

                // Dynamic Global Version Switcher (port select --summary)
                portSelectSection

                // Search Box & Filters
                searchAndFilterBar

                // Packages List
                packagesListSection
            }
            .padding(24)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            if appState.packages.isEmpty {
                Task {
                    await appState.loadInstalledPackages()
                }
            }
            if appState.portSelectGroups.isEmpty {
                Task {
                    await appState.refreshPortSelect()
                }
            }
        }
        .alert(isPresented: $isUninstallAlertPresented) {
            Alert(
                title: Text("Uninstall Package?"),
                message: Text("Are you sure you want to uninstall '\(packageToUninstall?.name ?? "") \(packageToUninstall?.version ?? "")'?"),
                primaryButton: .destructive(Text("Uninstall")) {
                    if let pkg = packageToUninstall {
                        Task {
                            await appState.uninstallPackage(name: pkg.name, version: pkg.version)
                            feedbackMessage = "Uninstalled \(pkg.name) \(pkg.version)."
                        }
                    }
                },
                secondaryButton: .cancel()
            )
        }
    }

    // MARK: - Header & Maintenance Actions
    private var headerSection: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("MacPorts Packages")
                    .font(.system(size: 20, weight: .bold))
                Text("Search ports, manage multi-version activations, maintain packages, and configure port select toolchains")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Maintenance Toolbar Buttons
            HStack(spacing: 8) {
                // Sync MacPorts (selfupdate)
                Button(action: {
                    Task {
                        feedbackMessage = "Starting port selfupdate..."
                        await appState.runSelfUpdate()
                        feedbackMessage = "MacPorts base system & PortIndex updated."
                    }
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("Sync MacPorts")
                    }
                    .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .help("Executes sudo -n port selfupdate to sync PortIndex")

                // Upgrade Outdated
                Button(action: {
                    Task {
                        feedbackMessage = "Upgrading outdated packages..."
                        await appState.runUpgradeOutdated()
                        feedbackMessage = "Outdated packages upgraded."
                    }
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.up.circle.fill")
                        Text("Upgrade Outdated")
                    }
                    .font(.system(size: 11))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .help("Executes sudo -n port upgrade outdated")

                // Clean Leaves
                Button(action: {
                    Task {
                        feedbackMessage = "Uninstalling leaves..."
                        await appState.runUninstallLeaves()
                        feedbackMessage = "Orphaned package leaves removed."
                    }
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "leaf.arrow.triangle.circlepath")
                        Text("Clean Leaves")
                    }
                    .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .help("Executes sudo -n port -N uninstall leaves")
            }
        }
    }

    // MARK: - Dynamic Global Version Switcher (port select --summary)
    private var portSelectSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isSelectGroupsExpanded.toggle()
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: isSelectGroupsExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.secondary)
                        Image(systemName: "arrow.left.arrow.right.circle.fill")
                            .font(.system(size: 13))
                            .foregroundColor(.accentColor)
                        Text("Global Version Switcher (`port select`)")
                            .font(.system(size: 13, weight: .bold))
                        Text("(\(appState.portSelectGroups.count) Groups)")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: {
                    Task { await appState.refreshPortSelect() }
                }) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
                .help("Rescan port select --summary")
            }

            if isSelectGroupsExpanded {
                if appState.portSelectGroups.isEmpty {
                    Text("No port select toolchains discovered on this system.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .padding(.vertical, 8)
                } else {
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ], spacing: 12) {
                        ForEach(appState.portSelectGroups) { group in
                            portSelectCard(group: group)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }

    private func portSelectCard(group: PortSelectGroup) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(group.group)
                    .font(.system(size: 12, weight: .bold))
                Spacer()
                Text(group.selected)
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.15))
                    .foregroundColor(.accentColor)
                    .cornerRadius(4)
            }

            // Option selection menu
            Picker("", selection: Binding(
                get: { group.selected },
                set: { newOption in
                    guard newOption != group.selected else { return }
                    Task {
                        await appState.runPortSelect(group: group.group, option: newOption)
                        feedbackMessage = "Switched '\(group.group)' default to '\(newOption)'."
                    }
                }
            )) {
                ForEach(group.options, id: \.self) { opt in
                    Text(opt).tag(opt)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.small)
        }
        .padding(10)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }

    // MARK: - Search & Filter Bar
    private var searchAndFilterBar: some View {
        HStack(spacing: 14) {
            // Search Input Box
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                TextField("Search MacPorts packages (e.g. nginx, redis, php83)...", text: $searchInput, onCommit: {
                    triggerSearch()
                })
                .textFieldStyle(.plain)
                .font(.system(size: 12))

                if !searchInput.isEmpty {
                    Button(action: {
                        searchInput = ""
                        Task { await appState.loadInstalledPackages() }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.borderless)
                }

                Button("Search") {
                    triggerSearch()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(appState.isSearchingPackages)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )

            // Filter Tabs
            Picker("", selection: $selectedFilter) {
                ForEach(PackageFilterTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 240)
        }
    }

    private func triggerSearch() {
        let trimmed = searchInput.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            if trimmed.isEmpty {
                await appState.loadInstalledPackages()
            } else {
                await appState.searchPackages(query: trimmed)
            }
        }
    }

    // MARK: - Packages List Section
    private var packagesListSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("\(filteredPackages.count) Package\(filteredPackages.count == 1 ? "" : "s")")
                    .font(.system(size: 13, weight: .bold))

                if appState.isSearchingPackages {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                }

                Spacer()
            }

            if filteredPackages.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "shippingbox")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary.opacity(0.6))
                    Text(appState.isSearchingPackages ? "Searching MacPorts repository..." : "No packages found.")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    if !searchInput.isEmpty {
                        Button("Show Installed Packages") {
                            searchInput = ""
                            Task { await appState.loadInstalledPackages() }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(40)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(filteredPackages) { package in
                        packageRow(package: package)
                    }
                }
            }
        }
    }

    private func packageRow(package: PortPackageItem) -> some View {
        HStack(alignment: .center, spacing: 14) {
            // Icon
            Image(systemName: package.isInstalled ? (package.isActive ? "checkmark.circle.fill" : "circle.dashed") : "shippingbox")
                .font(.system(size: 18))
                .foregroundColor(package.isActive ? .green : (package.isInstalled ? .secondary : .accentColor))
                .frame(width: 24)

            // Package Details
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(package.name)
                        .font(.system(size: 13, weight: .bold))

                    Text(package.version)
                        .font(.system(size: 11, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.12))
                        .cornerRadius(4)

                    if !package.category.isEmpty {
                        Text(package.category)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }

                    // Status Badges
                    if package.isActive {
                        Text("Active")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.green.opacity(0.15))
                            .cornerRadius(4)
                    } else if package.isInstalled {
                        Text("Inactive")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.15))
                            .cornerRadius(4)
                    }

                    if package.isOutdated {
                        Text("Outdated")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.15))
                            .cornerRadius(4)
                    }
                }

                if !package.summary.isEmpty {
                    Text(package.summary)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Lifecycle Action Buttons
            HStack(spacing: 6) {
                if !package.isInstalled {
                    // Install Action
                    Button(action: {
                        Task {
                            await appState.installPackage(name: package.name)
                            feedbackMessage = "Installed package \(package.name)."
                        }
                    }) {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.down.circle")
                            Text("Install")
                        }
                        .font(.system(size: 11))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                } else {
                    // Upgrade Outdated
                    if package.isOutdated {
                        Button(action: {
                            Task {
                                await appState.upgradePackage(name: package.name)
                                feedbackMessage = "Upgraded \(package.name)."
                            }
                        }) {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.up.circle")
                                Text("Upgrade")
                            }
                            .font(.system(size: 11))
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .tint(.orange)
                    }

                    // Multi-version Activate / Deactivate
                    if !package.isActive {
                        Button(action: {
                            Task {
                                await appState.activatePackage(name: package.name, version: package.version)
                                feedbackMessage = "Activated \(package.name) \(package.version)."
                            }
                        }) {
                            Text("Activate")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    } else {
                        Button(action: {
                            Task {
                                await appState.deactivatePackage(name: package.name, version: package.version)
                                feedbackMessage = "Deactivated \(package.name) \(package.version)."
                            }
                        }) {
                            Text("Deactivate")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    // Uninstall
                    Button(action: {
                        packageToUninstall = package
                        isUninstallAlertPresented = true
                    }) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundColor(.red.opacity(0.8))
                    }
                    .buttonStyle(.borderless)
                    .help("Uninstall package")
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }
}
