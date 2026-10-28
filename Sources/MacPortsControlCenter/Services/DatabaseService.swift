import Foundation

public struct DatabaseService {
    public static let defaultSocketPath: String = "/tmp/mysql.sock"
    public static let mysqlBinary: String = "/opt/local/bin/mysql"
    public static let mysqldumpBinary: String = "/opt/local/bin/mysqldump"

    /// System schemas and headers to ignore when listing user databases
    public static let systemSchemas: Set<String> = [
        "database",
        "information_schema",
        "mysql",
        "performance_schema",
        "sys"
    ]

    /// Parses output of `SHOW DATABASES;` from mysql CLI and filters out headers & internal system schemas.
    public static func parseShowDatabases(_ output: String) -> [String] {
        let lines = output.components(separatedBy: .newlines)
        var databases: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            if systemSchemas.contains(trimmed.lowercased()) { continue }
            databases.append(trimmed)
        }

        return databases
    }

    /// Safely escapes single quotes for POSIX / Zsh command strings
    private static func quoteArg(_ arg: String) -> String {
        return "'" + arg.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Builds command to list all databases via socket
    public static func buildShowDatabasesCommand(socketPath: String = defaultSocketPath) -> String {
        let safeSocket = quoteArg(socketPath)
        return "\(mysqlBinary) -u root --socket=\(safeSocket) -e \(quoteArg("SHOW DATABASES;"))"
    }

    /// Builds command to create a new database safely
    public static func buildCreateDatabaseCommand(dbName: String, socketPath: String = defaultSocketPath) -> String {
        let safeSocket = quoteArg(socketPath)
        let sanitizedDbName = dbName.replacingOccurrences(of: "`", with: "``")
        let escapedSql = "CREATE DATABASE IF NOT EXISTS `\(sanitizedDbName)`;"
        return "\(mysqlBinary) -u root --socket=\(safeSocket) -e \(quoteArg(escapedSql))"
    }

    /// Builds command to dump / export database to .sql file
    public static func buildDumpDatabaseCommand(dbName: String, outputPath: String, socketPath: String = defaultSocketPath) -> String {
        let safeSocket = quoteArg(socketPath)
        let safeDb = quoteArg(dbName)
        let safeOutput = quoteArg(outputPath)
        return "\(mysqldumpBinary) -u root --socket=\(safeSocket) \(safeDb) > \(safeOutput)"
    }

    /// Builds command to import a .sql file into database
    public static func buildImportDatabaseCommand(dbName: String, inputPath: String, socketPath: String = defaultSocketPath) -> String {
        let safeSocket = quoteArg(socketPath)
        let safeDb = quoteArg(dbName)
        let safeInput = quoteArg(inputPath)
        return "\(mysqlBinary) -u root --socket=\(safeSocket) \(safeDb) < \(safeInput)"
    }

    /// Builds command to drop a database safely
    public static func buildDropDatabaseCommand(dbName: String, socketPath: String = defaultSocketPath) -> String {
        let safeSocket = quoteArg(socketPath)
        let sanitizedDbName = dbName.replacingOccurrences(of: "`", with: "``")
        let escapedSql = "DROP DATABASE IF EXISTS `\(sanitizedDbName)`;"
        return "\(mysqlBinary) -u root --socket=\(safeSocket) -e \(quoteArg(escapedSql))"
    }
}
