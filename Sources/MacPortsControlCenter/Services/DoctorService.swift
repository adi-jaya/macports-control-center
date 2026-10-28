import Foundation

public struct DoctorService {
    public static let osascriptBinary: String = "/usr/bin/osascript"
    public static let sudoersMacPortsPath: String = "/etc/sudoers.d/macports"
    public static let nginxServersPath: String = "/opt/local/etc/nginx/servers"
    public static let defaultMySQLSocketPath: String = "/tmp/mysql.sock"

    /// Evaluates the 5 health guardrails specified in AGENTS.md
    public static func evaluateChecks(
        sudoersOK: Bool,
        nonCompliantFPMFiles: [String],
        nginxServersWritable: Bool,
        mariaDBRunning: Bool,
        mysqlSocketExists: Bool,
        unreadableLogFiles: [String]
    ) -> [DoctorCheckItem] {
        var items: [DoctorCheckItem] = []

        // Guardrail 1: Sudoers passwordless port access
        items.append(DoctorCheckItem(
            id: "sudoers",
            title: "Passwordless Sudo for MacPorts (/etc/sudoers.d/macports)",
            isHealthy: sudoersOK,
            detail: sudoersOK
                ? "Configured: User has passwordless sudo for /opt/local/bin/port."
                : "Missing or invalid /etc/sudoers.d/macports: sudo requires password for MacPorts commands.",
            fixActionDescription: "Create /etc/sudoers.d/macports with NOPASSWD: /opt/local/bin/port"
        ))

        // Guardrail 2: PHP-FPM worker user & group
        let fpmHealthy = nonCompliantFPMFiles.isEmpty
        items.append(DoctorCheckItem(
            id: "fpm-user",
            title: "PHP-FPM Worker User & Group (user = <user>, group = staff)",
            isHealthy: fpmHealthy,
            detail: fpmHealthy
                ? "All PHP-FPM pools are configured with user = <current_user> and group = staff."
                : "Non-compliant PHP-FPM pools found: \(nonCompliantFPMFiles.joined(separator: ", "))",
            fixActionDescription: "Update www.conf pool configuration to match current user and staff group"
        ))

        // Guardrail 3: Nginx servers directory writable without sudo
        items.append(DoctorCheckItem(
            id: "nginx-writable",
            title: "Nginx Virtual Hosts Directory Writable (/opt/local/etc/nginx/servers)",
            isHealthy: nginxServersWritable,
            detail: nginxServersWritable
                ? "Directory is writable without sudo by current user."
                : "/opt/local/etc/nginx/servers is not writable by current user.",
            fixActionDescription: "Change ownership to current user and admin group with 775 permissions"
        ))

        // Guardrail 4: MariaDB socket availability
        let socketHealthy = !mariaDBRunning || mysqlSocketExists
        items.append(DoctorCheckItem(
            id: "mysql-socket",
            title: "MariaDB Socket Availability (/tmp/mysql.sock)",
            isHealthy: socketHealthy,
            detail: mariaDBRunning
                ? (mysqlSocketExists
                    ? "MariaDB is running and /tmp/mysql.sock is available."
                    : "MariaDB is running but /tmp/mysql.sock was not found.")
                : "MariaDB service is not running (socket check skipped).",
            fixActionDescription: "Ensure MariaDB service is started and configured to create /tmp/mysql.sock"
        ))

        // Guardrail 5: Server logs readable
        let logsHealthy = unreadableLogFiles.isEmpty
        items.append(DoctorCheckItem(
            id: "log-readable",
            title: "Server Log Files Readability",
            isHealthy: logsHealthy,
            detail: logsHealthy
                ? "All monitored server log files are readable."
                : "Restricted log files found: \(unreadableLogFiles.joined(separator: ", "))",
            fixActionDescription: "Grant read permissions (chmod 644) to server log files"
        ))

        return items
    }

    /// Builds command to fix Laravel storage and bootstrap/cache permissions without sudo.
    /// Guards against empty string or root "/" to prevent dangerous operations on system root.
    public static func buildFixStoragePermissionsCommand(projectRootPath: String) -> String {
        let trimmed = projectRootPath.trimmingCharacters(in: .whitespacesAndNewlines)
        var cleanPath = trimmed
        while cleanPath.hasSuffix("/") && cleanPath.count > 1 {
            cleanPath.removeLast()
        }
        guard !cleanPath.isEmpty && cleanPath != "/" else {
            return ""
        }
        let safePath = cleanPath.replacingOccurrences(of: "'", with: "'\\''")
        return "chmod -R u+rwX '\(safePath)/storage' '\(safePath)/bootstrap/cache'"
    }

    /// Builds the root-level shell script executed via osascript with administrator privileges.
    /// Validates `currentUser` against `^[a-zA-Z0-9_.-]+$` to prevent sudoers corruption or injection.
    public static func buildPrivilegedAutoFixScript(currentUser: String) -> String {
        let trimmedUser = currentUser.trimmingCharacters(in: .whitespacesAndNewlines)
        let usernameRegex = "^[a-zA-Z0-9_.-]+$"
        let isValid = !trimmedUser.isEmpty && trimmedUser.range(of: usernameRegex, options: .regularExpression) != nil
        let targetUser = isValid ? trimmedUser : NSUserName()
        let safeUser = (!targetUser.isEmpty && targetUser.range(of: usernameRegex, options: .regularExpression) != nil) ? targetUser : "admin"

        return """
        #!/bin/bash
        set -e

        # 1. Setup passwordless sudo for MacPorts
        mkdir -p /etc/sudoers.d
        echo '\(safeUser) ALL=(ALL) NOPASSWD: /opt/local/bin/port' > /etc/sudoers.d/macports
        chmod 0440 /etc/sudoers.d/macports

        # 2. Fix Nginx virtual hosts directory ownership and permissions
        mkdir -p /opt/local/etc/nginx/servers
        chown -R '\(safeUser):admin' /opt/local/etc/nginx/servers
        chmod -R 775 /opt/local/etc/nginx/servers

        # 3. Fix permissions for logs and run directories
        mkdir -p /opt/local/var/log/nginx /opt/local/var/run/nginx
        chown -R '\(safeUser):admin' /opt/local/var/log/nginx /opt/local/var/run/nginx 2>/dev/null || true
        chmod -R 775 /opt/local/var/log/nginx /opt/local/var/run/nginx 2>/dev/null || true

        mkdir -p /opt/local/var/log/php81 /opt/local/var/log/php82 /opt/local/var/log/php83 /opt/local/var/log/php84 /opt/local/var/log/php85 2>/dev/null || true
        chmod 644 /opt/local/var/log/php*/*.log 2>/dev/null || true
        chmod 644 /opt/local/var/log/nginx/*.log 2>/dev/null || true
        chown -R '\(safeUser):admin' /opt/local/var/log/php* 2>/dev/null || true

        # 4. Fix PHP-FPM pool user, group, and permissions
        mkdir -p /opt/local/etc
        chown -R '\(safeUser):admin' /opt/local/etc/php* 2>/dev/null || true
        chmod 775 /opt/local/etc/php* /opt/local/etc/php*/php-fpm.d 2>/dev/null || true
        chmod 664 /opt/local/etc/php*/php-fpm.d/*.conf 2>/dev/null || true

        for conf in /opt/local/etc/php*/php-fpm.d/www.conf; do
            if [ -f "$conf" ]; then
                if grep -q -E '^[[:space:]]*user[[:space:]]*=' "$conf"; then
                    sed -i '' -E 's/^[[:space:]]*user[[:space:]]*=.*/user = \(safeUser)/' "$conf"
                else
                    echo "user = \(safeUser)" >> "$conf"
                fi

                if grep -q -E '^[[:space:]]*group[[:space:]]*=' "$conf"; then
                    sed -i '' -E 's/^[[:space:]]*group[[:space:]]*=.*/group = staff/' "$conf"
                else
                    echo "group = staff" >> "$conf"
                fi
            fi
        done
        """
    }

    /// Builds the argument array for `/usr/bin/osascript` to run a script with administrator privileges
    public static func buildOsascriptAdminCommand(shellScript: String) -> [String] {
        let escapedScript = shellScript
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r\n", with: "\\n")
            .replacingOccurrences(of: "\n", with: "\\n")

        let appleScript = "do shell script \"\(escapedScript)\" with administrator privileges"
        return ["-e", appleScript]
    }

    /// Checks if `/opt/local/etc/nginx/servers` is writable by the current process
    public static func isNginxServersWritable(path: String = nginxServersPath) -> Bool {
        return FileManager.default.isWritableFile(atPath: path)
    }

    /// Checks if MariaDB unix domain socket exists at given path
    public static func isMySQLSocketPresent(path: String = defaultMySQLSocketPath) -> Bool {
        return FileManager.default.fileExists(atPath: path)
    }

    /// Returns list of paths that exist on disk but are not readable
    public static func findUnreadableLogFiles(paths: [String]) -> [String] {
        var unreadable: [String] = []
        for path in paths {
            if FileManager.default.fileExists(atPath: path) {
                if !FileManager.default.isReadableFile(atPath: path) {
                    unreadable.append(path)
                }
            }
        }
        return unreadable
    }

    /// Default log file locations to monitor
    public static func defaultMonitoredLogPaths() -> [String] {
        var paths = [
            "/opt/local/var/log/nginx/error.log",
            "/opt/local/var/log/nginx/access.log"
        ]
        let versions = ["81", "82", "83", "84", "85"]
        for v in versions {
            paths.append("/opt/local/var/log/php\(v)/php-fpm.log")
        }
        return paths
    }
}
