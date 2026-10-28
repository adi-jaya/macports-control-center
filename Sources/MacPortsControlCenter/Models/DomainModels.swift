import Foundation

// MARK: - ServiceItem
public struct ServiceItem: Identifiable, Equatable, Hashable {
    public let id: String
    public let name: String
    public let plistName: String
    public var isRunning: Bool
    public var isEnabledAtBoot: Bool
    public var detail: String

    public init(
        id: String,
        name: String,
        plistName: String,
        isRunning: Bool,
        isEnabledAtBoot: Bool,
        detail: String
    ) {
        self.id = id
        self.name = name
        self.plistName = plistName
        self.isRunning = isRunning
        self.isEnabledAtBoot = isEnabledAtBoot
        self.detail = detail
    }
}

// MARK: - VHostItem
public struct VHostItem: Identifiable, Equatable, Hashable {
    public let id: String
    public var fileName: String
    public var filePath: String
    public var listenPort: String
    public var serverName: String
    public var rootPath: String
    public var fastcgiPass: String
    public var sslEnabled: Bool
    public var laravelDatabase: String?
    public var laravelAppURL: String?

    public init(
        id: String,
        fileName: String,
        filePath: String,
        listenPort: String,
        serverName: String,
        rootPath: String,
        fastcgiPass: String,
        sslEnabled: Bool,
        laravelDatabase: String? = nil,
        laravelAppURL: String? = nil
    ) {
        self.id = id
        self.fileName = fileName
        self.filePath = filePath
        self.listenPort = listenPort
        self.serverName = serverName
        self.rootPath = rootPath
        self.fastcgiPass = fastcgiPass
        self.sslEnabled = sslEnabled
        self.laravelDatabase = laravelDatabase
        self.laravelAppURL = laravelAppURL
    }
}

// MARK: - PHPVersionItem
public struct PHPVersionItem: Identifiable, Equatable, Hashable {
    public var id: String { version }
    public let version: String
    public let portName: String
    public var isInstalled: Bool
    public var isCLIDefault: Bool
    public var fpmPort: Int
    public var isFPMRunning: Bool
    public var installedExtensions: Set<String>

    public init(
        version: String,
        portName: String,
        isInstalled: Bool,
        isCLIDefault: Bool,
        fpmPort: Int,
        isFPMRunning: Bool,
        installedExtensions: Set<String> = []
    ) {
        self.version = version
        self.portName = portName
        self.isInstalled = isInstalled
        self.isCLIDefault = isCLIDefault
        self.fpmPort = fpmPort
        self.isFPMRunning = isFPMRunning
        self.installedExtensions = installedExtensions
    }
}

// MARK: - PortPackageItem
public struct PortPackageItem: Identifiable, Equatable, Hashable {
    public var id: String {
        if version.hasPrefix("@") {
            return "\(name)\(version)"
        } else {
            return "\(name)@\(version)"
        }
    }
    public let name: String
    public let version: String
    public var category: String
    public var summary: String
    public var isInstalled: Bool
    public var isActive: Bool
    public var isOutdated: Bool

    public init(
        name: String,
        version: String,
        category: String,
        summary: String,
        isInstalled: Bool,
        isActive: Bool,
        isOutdated: Bool
    ) {
        self.name = name
        self.version = version
        self.category = category
        self.summary = summary
        self.isInstalled = isInstalled
        self.isActive = isActive
        self.isOutdated = isOutdated
    }
}

// MARK: - PortSelectGroup
public struct PortSelectGroup: Identifiable, Equatable, Hashable {
    public var id: String { group }
    public let group: String
    public var selected: String
    public var options: [String]

    public init(group: String, selected: String, options: [String]) {
        self.group = group
        self.selected = selected
        self.options = options
    }
}

// MARK: - DoctorCheckItem
public struct DoctorCheckItem: Identifiable, Equatable, Hashable {
    public let id: String
    public var title: String
    public var isHealthy: Bool
    public var detail: String
    public var fixActionDescription: String

    public init(
        id: String,
        title: String,
        isHealthy: Bool,
        detail: String,
        fixActionDescription: String
    ) {
        self.id = id
        self.title = title
        self.isHealthy = isHealthy
        self.detail = detail
        self.fixActionDescription = fixActionDescription
    }
}

// MARK: - DocItem
public struct DocItem: Identifiable, Equatable, Hashable {
    public let id: String
    public var fileName: String
    public var title: String
    public var filePath: String

    public init(id: String, fileName: String, title: String, filePath: String) {
        self.id = id
        self.fileName = fileName
        self.title = title
        self.filePath = filePath
    }
}
