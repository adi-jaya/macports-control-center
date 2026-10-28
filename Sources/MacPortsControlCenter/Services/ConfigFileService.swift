import Foundation

// MARK: - PHPIniTuning
public struct PHPIniTuning: Equatable {
    public var memoryLimit: String
    public var uploadMaxFilesize: String
    public var postMaxSize: String
    public var maxExecutionTime: String
    public var nginxClientMaxBodySize: String

    public init(
        memoryLimit: String = "128M",
        uploadMaxFilesize: String = "2M",
        postMaxSize: String = "8M",
        maxExecutionTime: String = "30",
        nginxClientMaxBodySize: String = "64M"
    ) {
        self.memoryLimit = memoryLimit
        self.uploadMaxFilesize = uploadMaxFilesize
        self.postMaxSize = postMaxSize
        self.maxExecutionTime = maxExecutionTime
        self.nginxClientMaxBodySize = nginxClientMaxBodySize
    }
}

// MARK: - VHostTemplateType
public enum VHostTemplateType: String, CaseIterable {
    case laravel = "Laravel"
    case spa = "SPA / Static"
}

// MARK: - ConfigFileError
public enum ConfigFileError: Error, LocalizedError, Equatable {
    case validationFailed(String)
    case writeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .validationFailed(let msg):
            return "Configuration validation failed: \(msg)"
        case .writeFailed(let msg):
            return "Failed to write configuration file: \(msg)"
        }
    }
}

// MARK: - ConfigFileService
public enum ConfigFileService {

    // MARK: - Laravel .env Parsing
    public static func parseLaravelEnv(at envPath: String) -> (database: String?, appURL: String?) {
        guard let content = try? String(contentsOfFile: envPath, encoding: .utf8) else {
            return (nil, nil)
        }

        var database: String?
        var appURL: String?

        let lines = content.components(separatedBy: .newlines)
        for rawLine in lines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }

            guard let equalsIndex = trimmed.firstIndex(of: "=") else {
                continue
            }

            let key = String(trimmed[..<equalsIndex]).trimmingCharacters(in: .whitespaces)
            let rawVal = String(trimmed[trimmed.index(after: equalsIndex)...]).trimmingCharacters(in: .whitespaces)

            var val = rawVal
            if val.hasPrefix("\"") {
                let afterQuote = val.dropFirst()
                if let closingQuote = afterQuote.firstIndex(of: "\"") {
                    val = String(afterQuote[..<closingQuote])
                } else {
                    val = String(afterQuote)
                }
            } else if val.hasPrefix("'") {
                let afterQuote = val.dropFirst()
                if let closingQuote = afterQuote.firstIndex(of: "'") {
                    val = String(afterQuote[..<closingQuote])
                } else {
                    val = String(afterQuote)
                }
            } else {
                if let commentIndex = val.firstIndex(of: "#") {
                    val = String(val[..<commentIndex]).trimmingCharacters(in: .whitespaces)
                }
            }

            if key == "DB_DATABASE" {
                database = val
            } else if key == "APP_URL" {
                appURL = val
            }
        }

        return (database, appURL)
    }

    // MARK: - Virtual Host Generator
    public static func generateVHostConfig(
        serverName: String,
        listenPort: String,
        rootPath: String,
        fpmPort: Int = 9000,
        template: VHostTemplateType = .laravel,
        sslCertPath: String? = nil,
        sslKeyPath: String? = nil
    ) -> String {
        let hasSSL = (sslCertPath != nil && !sslCertPath!.isEmpty && sslKeyPath != nil && !sslKeyPath!.isEmpty)

        switch template {
        case .laravel:
            if hasSSL {
                let cert = sslCertPath!
                let key = sslKeyPath!
                if listenPort == "443" || listenPort == "80" {
                    return """
                    server {
                        listen 80;
                        server_name \(serverName);
                        return 301 https://$host$request_uri;
                    }

                    server {
                        listen 443 ssl http2;
                        server_name \(serverName);
                        root \(rootPath);

                        ssl_certificate \(cert);
                        ssl_certificate_key \(key);

                        ssl_protocols TLSv1.2 TLSv1.3;
                        ssl_ciphers HIGH:!aNULL:!MD5;

                        index index.php index.html;
                        charset utf-8;

                        location / {
                            try_files $uri $uri/ /index.php?$query_string;
                        }

                        location = /favicon.ico { access_log off; log_not_found off; }
                        location = /robots.txt  { access_log off; log_not_found off; }

                        error_page 404 /index.php;

                        location ~ \\.php$ {
                            fastcgi_pass 127.0.0.1:\(fpmPort);
                            fastcgi_param SCRIPT_FILENAME $realpath_root$fastcgi_script_name;
                            include fastcgi.conf;
                        }

                        location ~ /\\.(?!well-known).* {
                            deny all;
                        }
                    }

                    """
                } else {
                    return """
                    server {
                        listen \(listenPort) ssl http2;
                        server_name \(serverName);
                        root \(rootPath);

                        ssl_certificate \(cert);
                        ssl_certificate_key \(key);

                        ssl_protocols TLSv1.2 TLSv1.3;
                        ssl_ciphers HIGH:!aNULL:!MD5;

                        index index.php index.html;
                        charset utf-8;

                        location / {
                            try_files $uri $uri/ /index.php?$query_string;
                        }

                        location = /favicon.ico { access_log off; log_not_found off; }
                        location = /robots.txt  { access_log off; log_not_found off; }

                        error_page 404 /index.php;

                        location ~ \\.php$ {
                            fastcgi_pass 127.0.0.1:\(fpmPort);
                            fastcgi_param SCRIPT_FILENAME $realpath_root$fastcgi_script_name;
                            include fastcgi.conf;
                        }

                        location ~ /\\.(?!well-known).* {
                            deny all;
                        }
                    }

                    """
                }
            } else {
                return """
                server {
                    listen \(listenPort);
                    server_name \(serverName);
                    root \(rootPath);

                    index index.php index.html;
                    charset utf-8;

                    location / {
                        try_files $uri $uri/ /index.php?$query_string;
                    }

                    location = /favicon.ico { access_log off; log_not_found off; }
                    location = /robots.txt  { access_log off; log_not_found off; }

                    error_page 404 /index.php;

                    location ~ \\.php$ {
                        fastcgi_pass 127.0.0.1:\(fpmPort);
                        fastcgi_param SCRIPT_FILENAME $realpath_root$fastcgi_script_name;
                        include fastcgi.conf;
                    }

                    location ~ /\\.(?!well-known).* {
                        deny all;
                    }
                }

                """
            }

        case .spa:
            if hasSSL {
                let cert = sslCertPath!
                let key = sslKeyPath!
                if listenPort == "443" || listenPort == "80" {
                    return """
                    server {
                        listen 80;
                        server_name \(serverName);
                        return 301 https://$host$request_uri;
                    }

                    server {
                        listen 443 ssl http2;
                        server_name \(serverName);
                        root \(rootPath);

                        ssl_certificate \(cert);
                        ssl_certificate_key \(key);

                        ssl_protocols TLSv1.2 TLSv1.3;
                        ssl_ciphers HIGH:!aNULL:!MD5;

                        index index.html;

                        location / {
                            try_files $uri $uri/ /index.html;
                        }

                        location ~* \\.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
                            expires max;
                            log_not_found off;
                        }
                    }

                    """
                } else {
                    return """
                    server {
                        listen \(listenPort) ssl http2;
                        server_name \(serverName);
                        root \(rootPath);

                        ssl_certificate \(cert);
                        ssl_certificate_key \(key);

                        ssl_protocols TLSv1.2 TLSv1.3;
                        ssl_ciphers HIGH:!aNULL:!MD5;

                        index index.html;

                        location / {
                            try_files $uri $uri/ /index.html;
                        }

                        location ~* \\.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
                            expires max;
                            log_not_found off;
                        }
                    }

                    """
                }
            } else {
                return """
                server {
                    listen \(listenPort);
                    server_name \(serverName);
                    root \(rootPath);

                    index index.html;

                    location / {
                        try_files $uri $uri/ /index.html;
                    }

                    location ~* \\.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
                        expires max;
                        log_not_found off;
                    }
                }

                """
            }
        }
    }

    // MARK: - Virtual Host Parser
    public static func parseVHost(filePath: String) -> VHostItem? {
        guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else {
            return nil
        }

        let fileName = URL(fileURLWithPath: filePath).lastPathComponent
        var listenPort = ""
        var serverName = ""
        var rootPath = ""
        var fastcgiPass = ""
        var sslEnabled = false

        let lines = content.components(separatedBy: .newlines)
        for rawLine in lines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }

            var cleanLine = trimmed
            if let hashIdx = cleanLine.firstIndex(of: "#") {
                cleanLine = String(cleanLine[..<hashIdx]).trimmingCharacters(in: .whitespaces)
            }

            guard cleanLine.hasSuffix(";") else {
                if cleanLine.contains("ssl_certificate") {
                    sslEnabled = true
                }
                continue
            }

            let stmt = String(cleanLine.dropLast()).trimmingCharacters(in: .whitespaces)
            let tokens = stmt.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard let directive = tokens.first else { continue }

            switch directive {
            case "listen":
                if tokens.contains("ssl") {
                    sslEnabled = true
                }
                if tokens.count > 1 {
                    let portToken = tokens[1]
                    if portToken.contains(":") {
                        if let colonIdx = portToken.lastIndex(of: ":") {
                            let p = String(portToken[portToken.index(after: colonIdx)...])
                            if !p.isEmpty && (listenPort.isEmpty || !portToken.contains("[")) {
                                listenPort = p
                            }
                        }
                    } else if CharacterSet.decimalDigits.isSuperset(of: CharacterSet(charactersIn: portToken)) {
                        if listenPort.isEmpty || (tokens.contains("ssl") && listenPort == "80") {
                            listenPort = portToken
                        }
                    }
                }
            case "server_name":
                serverName = tokens.dropFirst().joined(separator: " ")
            case "root":
                if tokens.count > 1 {
                    rootPath = tokens[1]
                }
            case "fastcgi_pass":
                if tokens.count > 1 {
                    fastcgiPass = tokens[1]
                }
            case "ssl_certificate":
                sslEnabled = true
            default:
                break
            }
        }

        if rootPath.isEmpty && listenPort.isEmpty {
            return nil
        }

        var laravelDatabase: String?
        var laravelAppURL: String?

        if !rootPath.isEmpty {
            let envPath: String
            if rootPath.hasSuffix("/public") {
                let parent = URL(fileURLWithPath: rootPath).deletingLastPathComponent().path
                envPath = URL(fileURLWithPath: parent).appendingPathComponent(".env").path
            } else {
                envPath = URL(fileURLWithPath: rootPath).appendingPathComponent(".env").path
            }

            if FileManager.default.fileExists(atPath: envPath) {
                let parsedEnv = parseLaravelEnv(at: envPath)
                laravelDatabase = parsedEnv.database
                laravelAppURL = parsedEnv.appURL
            }
        }

        return VHostItem(
            id: fileName,
            fileName: fileName,
            filePath: filePath,
            listenPort: listenPort,
            serverName: serverName,
            rootPath: rootPath,
            fastcgiPass: fastcgiPass,
            sslEnabled: sslEnabled,
            laravelDatabase: laravelDatabase,
            laravelAppURL: laravelAppURL
        )
    }

    // MARK: - Nginx -t Output Validation
    public static func isNginxTestOutputValid(exitCode: Int32, output: String) -> Bool {
        if exitCode == 0 {
            return true
        }
        guard output.contains("syntax is ok") else {
            return false
        }
        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            if line.contains("[emerg]") {
                if !line.contains("nginx.pid") {
                    return false
                }
            }
        }
        return true
    }

    // MARK: - Atomic Save with Rollback
    public static func saveVHostWithValidation(
        filePath: String,
        content: String,
        validator: () async -> (Bool, String)
    ) async throws {
        let fileManager = FileManager.default
        let fileExisted = fileManager.fileExists(atPath: filePath)
        let originalContent = fileExisted ? (try? String(contentsOfFile: filePath, encoding: .utf8)) : nil

        do {
            try content.write(toFile: filePath, atomically: true, encoding: .utf8)
        } catch {
            throw ConfigFileError.writeFailed(error.localizedDescription)
        }

        let (isValid, errorMessage) = await validator()
        if !isValid {
            if fileExisted, let original = originalContent {
                try? original.write(toFile: filePath, atomically: true, encoding: .utf8)
            } else {
                try? fileManager.removeItem(atPath: filePath)
            }
            throw ConfigFileError.validationFailed(errorMessage)
        }
    }

    // MARK: - Multi-PHP FPM www.conf Normalizer
    public static func configureFPMWwwConf(
        content: String,
        version: String,
        user: String,
        group: String
    ) -> String {
        let digits = version.replacingOccurrences(of: "php", with: "").replacingOccurrences(of: ".", with: "")
        let port: Int
        if digits == "83" {
            port = 9000
        } else if let num = Int(digits), num > 0 {
            port = 9000 + num
        } else {
            port = 9000
        }

        var lines = content.components(separatedBy: .newlines)
        var userUpdated = false
        var groupUpdated = false
        var listenUpdated = false

        for i in 0..<lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix(";") || trimmed.hasPrefix("#") {
                continue
            }

            if trimmed.hasPrefix("user") {
                let afterKey = trimmed.dropFirst(4).trimmingCharacters(in: .whitespaces)
                if afterKey.hasPrefix("=") {
                    lines[i] = "user = \(user)"
                    userUpdated = true
                    continue
                }
            }

            if trimmed.hasPrefix("group") {
                let afterKey = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
                if afterKey.hasPrefix("=") {
                    lines[i] = "group = \(group)"
                    groupUpdated = true
                    continue
                }
            }

            if trimmed.hasPrefix("listen") {
                let afterKey = trimmed.dropFirst(6).trimmingCharacters(in: .whitespaces)
                if afterKey.hasPrefix("=") {
                    lines[i] = "listen = 127.0.0.1:\(port)"
                    listenUpdated = true
                    continue
                }
            }
        }

        if !userUpdated {
            lines.append("user = \(user)")
        }
        if !groupUpdated {
            lines.append("group = \(group)")
        }
        if !listenUpdated {
            lines.append("listen = 127.0.0.1:\(port)")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - PHP & Nginx Quick Tuning
    public static func parsePHPIniTuning(phpIniContent: String, nginxConfContent: String) -> PHPIniTuning {
        var memoryLimit = "128M"
        var uploadMaxFilesize = "2M"
        var postMaxSize = "8M"
        var maxExecutionTime = "30"
        var nginxClientMaxBodySize = "64M"

        let iniLines = phpIniContent.components(separatedBy: .newlines)
        for rawLine in iniLines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix(";") || trimmed.hasPrefix("#") {
                continue
            }
            guard let eqIdx = trimmed.firstIndex(of: "=") else { continue }
            let key = String(trimmed[..<eqIdx]).trimmingCharacters(in: .whitespaces)
            var val = String(trimmed[trimmed.index(after: eqIdx)...]).trimmingCharacters(in: .whitespaces)
            if let commentIdx = val.firstIndex(where: { $0 == ";" || $0 == "#" }) {
                val = String(val[..<commentIdx]).trimmingCharacters(in: .whitespaces)
            }

            switch key {
            case "memory_limit":
                memoryLimit = val
            case "upload_max_filesize":
                uploadMaxFilesize = val
            case "post_max_size":
                postMaxSize = val
            case "max_execution_time":
                maxExecutionTime = val
            default:
                break
            }
        }

        let nginxLines = nginxConfContent.components(separatedBy: .newlines)
        for rawLine in nginxLines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }
            if trimmed.hasPrefix("client_max_body_size") {
                var directive = trimmed
                if let hashIdx = directive.firstIndex(of: "#") {
                    directive = String(directive[..<hashIdx]).trimmingCharacters(in: .whitespaces)
                }
                if directive.hasSuffix(";") {
                    directive = String(directive.dropLast()).trimmingCharacters(in: .whitespaces)
                }
                let tokens = directive.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                if tokens.count > 1 {
                    nginxClientMaxBodySize = tokens[1]
                }
            }
        }

        return PHPIniTuning(
            memoryLimit: memoryLimit,
            uploadMaxFilesize: uploadMaxFilesize,
            postMaxSize: postMaxSize,
            maxExecutionTime: maxExecutionTime,
            nginxClientMaxBodySize: nginxClientMaxBodySize
        )
    }

    public static func updatePHPIni(content: String, tuning: PHPIniTuning) -> String {
        var lines = content.components(separatedBy: .newlines)
        var updated = Set<String>()

        for i in 0..<lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix(";") || trimmed.hasPrefix("#") {
                continue
            }

            guard let eqIdx = trimmed.firstIndex(of: "=") else { continue }
            let key = String(trimmed[..<eqIdx]).trimmingCharacters(in: .whitespaces)

            switch key {
            case "memory_limit":
                lines[i] = "memory_limit = \(tuning.memoryLimit)"
                updated.insert("memory_limit")
            case "upload_max_filesize":
                lines[i] = "upload_max_filesize = \(tuning.uploadMaxFilesize)"
                updated.insert("upload_max_filesize")
            case "post_max_size":
                lines[i] = "post_max_size = \(tuning.postMaxSize)"
                updated.insert("post_max_size")
            case "max_execution_time":
                lines[i] = "max_execution_time = \(tuning.maxExecutionTime)"
                updated.insert("max_execution_time")
            default:
                break
            }
        }

        if !updated.contains("memory_limit") {
            lines.append("memory_limit = \(tuning.memoryLimit)")
        }
        if !updated.contains("upload_max_filesize") {
            lines.append("upload_max_filesize = \(tuning.uploadMaxFilesize)")
        }
        if !updated.contains("post_max_size") {
            lines.append("post_max_size = \(tuning.postMaxSize)")
        }
        if !updated.contains("max_execution_time") {
            lines.append("max_execution_time = \(tuning.maxExecutionTime)")
        }

        return lines.joined(separator: "\n")
    }

    public static func updateNginxClientMaxBodySize(content: String, maxBodySize: String) -> String {
        var lines = content.components(separatedBy: .newlines)
        var updated = false

        for i in 0..<lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") {
                continue
            }

            if trimmed.hasPrefix("client_max_body_size") {
                let indent = line.prefix { $0 == " " || $0 == "\t" }
                lines[i] = "\(indent)client_max_body_size \(maxBodySize);"
                updated = true
                break
            }
        }

        if !updated {
            var inserted = false
            for i in 0..<lines.count {
                let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("http") && trimmed.contains("{") {
                    lines.insert("    client_max_body_size \(maxBodySize);", at: i + 1)
                    inserted = true
                    break
                }
            }
            if !inserted {
                lines.append("client_max_body_size \(maxBodySize);")
            }
        }

        return lines.joined(separator: "\n")
    }
}
