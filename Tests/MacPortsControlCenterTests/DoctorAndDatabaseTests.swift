#if canImport(XCTest)
import XCTest
@testable import MacPortsControlCenter
#else
import Foundation
#endif

final class DoctorAndDatabaseTests: XCTestCase {
    func testParseShowDatabasesFiltersHeaderAndSystemSchemas() {
        let output = """
        Database
        information_schema
        mysql
        performance_schema
        sys
        db_siakurat_sifat
        sik
        """
        let dbs = DatabaseService.parseShowDatabases(output)
        XCTAssertTrue(dbs.contains("db_siakurat_sifat"))
        XCTAssertTrue(dbs.contains("sik"))
        XCTAssertFalse(dbs.contains("Database"))
        XCTAssertFalse(dbs.contains("information_schema"))
        XCTAssertFalse(dbs.contains("mysql"))
        XCTAssertFalse(dbs.contains("performance_schema"))
        XCTAssertFalse(dbs.contains("sys"))
    }

    func testBuildDumpAndImportCommandsUseSocketAndSafeQuoting() {
        let dump = DatabaseService.buildDumpDatabaseCommand(
            dbName: "db_siakurat_sifat",
            outputPath: "/tmp/backup.sql",
            socketPath: "/tmp/mysql.sock"
        )
        XCTAssertTrue(dump.contains("/opt/local/bin/mysqldump"))
        XCTAssertTrue(dump.contains("--socket='/tmp/mysql.sock'"))
        XCTAssertTrue(dump.contains("'db_siakurat_sifat' > '/tmp/backup.sql'"))

        let importCmd = DatabaseService.buildImportDatabaseCommand(
            dbName: "db_siakurat_sifat",
            inputPath: "/tmp/backup.sql",
            socketPath: "/tmp/mysql.sock"
        )
        XCTAssertTrue(importCmd.contains("/opt/local/bin/mysql"))
        XCTAssertTrue(importCmd.contains("--socket='/tmp/mysql.sock'"))
        XCTAssertTrue(importCmd.contains("'db_siakurat_sifat' < '/tmp/backup.sql'"))

        let createCmd = DatabaseService.buildCreateDatabaseCommand(
            dbName: "new_project_db",
            socketPath: "/tmp/mysql.sock"
        )
        XCTAssertTrue(createCmd.contains("/opt/local/bin/mysql"))
        XCTAssertTrue(createCmd.contains("--socket='/tmp/mysql.sock'"))
        XCTAssertTrue(createCmd.contains("CREATE DATABASE IF NOT EXISTS"))
        XCTAssertTrue(createCmd.contains("`new_project_db`"))

        let createWithCharset = DatabaseService.buildCreateDatabaseCommand(
            dbName: "project_utf8",
            charset: "utf8mb4",
            collation: "utf8mb4_unicode_ci",
            socketPath: "/tmp/mysql.sock"
        )
        XCTAssertTrue(createWithCharset.contains("CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci"))
    }

    func testDoctorServiceEvaluatesAllFiveGuardrailChecksAndBuildsAutoFixScript() {
        let checks = DoctorService.evaluateChecks(
            sudoersOK: true,
            nonCompliantFPMFiles: ["/opt/local/etc/php84/php-fpm.d/www.conf"],
            nginxServersWritable: true,
            mariaDBRunning: true,
            mysqlSocketExists: true,
            unreadableLogFiles: ["/opt/local/var/log/php83/php-fpm.log"]
        )
        XCTAssertEqual(checks.count, 5)
        XCTAssertTrue(checks.first(where: { $0.id == "sudoers" })?.isHealthy == true)
        XCTAssertFalse(checks.first(where: { $0.id == "fpm-user" })?.isHealthy == true)
        XCTAssertTrue(checks.first(where: { $0.id == "nginx-writable" })?.isHealthy == true)
        XCTAssertTrue(checks.first(where: { $0.id == "mysql-socket" })?.isHealthy == true)
        XCTAssertFalse(checks.first(where: { $0.id == "log-readable" })?.isHealthy == true)

        let script = DoctorService.buildPrivilegedAutoFixScript(currentUser: "adijaya")
        XCTAssertTrue(script.contains("/etc/sudoers.d/macports"))
        XCTAssertTrue(script.contains("/opt/local/etc/nginx/servers"))
        XCTAssertTrue(script.contains("/opt/local/var/log/php"))
    }

    func testDoctorServiceOsascriptCommandAndStoragePermissionsCommand() {
        let fixStorage = DoctorService.buildFixStoragePermissionsCommand(projectRootPath: "/Users/adijaya/Projects/my-app")
        XCTAssertTrue(fixStorage.contains("chmod -R u+rwX"))
        XCTAssertTrue(fixStorage.contains("/Users/adijaya/Projects/my-app/storage"))
        XCTAssertTrue(fixStorage.contains("/Users/adijaya/Projects/my-app/bootstrap/cache"))

        let osascriptCmd = DoctorService.buildOsascriptAdminCommand(shellScript: "echo 'hello world'")
        XCTAssertEqual(osascriptCmd.count, 2)
        XCTAssertEqual(osascriptCmd[0], "-e")
        XCTAssertTrue(osascriptCmd[1].contains("do shell script"))
        XCTAssertTrue(osascriptCmd[1].contains("with administrator privileges"))
    }

    func testDoctorServiceEdgeCasesAllHealthyAndSocketLogic() {
        // When MariaDB is not running, missing socket should NOT trigger failure
        let stoppedDBChecks = DoctorService.evaluateChecks(
            sudoersOK: true,
            nonCompliantFPMFiles: [],
            nginxServersWritable: true,
            mariaDBRunning: false,
            mysqlSocketExists: false,
            unreadableLogFiles: []
        )
        XCTAssertEqual(stoppedDBChecks.count, 5)
        XCTAssertTrue(stoppedDBChecks.allSatisfy { $0.isHealthy })

        // When MariaDB IS running, but socket is missing -> unhealthy
        let missingSocketChecks = DoctorService.evaluateChecks(
            sudoersOK: true,
            nonCompliantFPMFiles: [],
            nginxServersWritable: true,
            mariaDBRunning: true,
            mysqlSocketExists: false,
            unreadableLogFiles: []
        )
        XCTAssertFalse(missingSocketChecks.first(where: { $0.id == "mysql-socket" })?.isHealthy == true)

        // Trailing slash handling in project path
        let fixWithSlash = DoctorService.buildFixStoragePermissionsCommand(projectRootPath: "/var/www/site/")
        XCTAssertTrue(fixWithSlash.contains("'/var/www/site/storage'"))
        XCTAssertFalse(fixWithSlash.contains("//storage"))

        // Guard against empty string and root "/"
        XCTAssertEqual(DoctorService.buildFixStoragePermissionsCommand(projectRootPath: ""), "")
        XCTAssertEqual(DoctorService.buildFixStoragePermissionsCommand(projectRootPath: "   "), "")
        XCTAssertEqual(DoctorService.buildFixStoragePermissionsCommand(projectRootPath: "/"), "")
        XCTAssertEqual(DoctorService.buildFixStoragePermissionsCommand(projectRootPath: "///"), "")

        // Validation for currentUser in buildPrivilegedAutoFixScript
        let invalidUserScript = DoctorService.buildPrivilegedAutoFixScript(currentUser: "evil;rm -rf /")
        XCTAssertFalse(invalidUserScript.contains("evil;rm -rf /"))
        XCTAssertTrue(invalidUserScript.contains("ALL=(ALL) NOPASSWD: /opt/local/bin/port"))

        let emptyUserScript = DoctorService.buildPrivilegedAutoFixScript(currentUser: "")
        XCTAssertFalse(emptyUserScript.contains("  ALL=(ALL)"))
        XCTAssertTrue(emptyUserScript.contains("ALL=(ALL) NOPASSWD: /opt/local/bin/port"))
    }

    func testDatabaseServiceSpecialCharactersAndEmptyOutputs() {
        let empty = DatabaseService.parseShowDatabases("")
        XCTAssertEqual(empty, [])

        let onlySystem = DatabaseService.parseShowDatabases("""
        Database
        information_schema
        mysql
        performance_schema
        sys
        """)
        XCTAssertEqual(onlySystem, [])

        // Special characters in DB name & socket path - quotes SQL string cleanly with quoteArg
        let create = DatabaseService.buildCreateDatabaseCommand(dbName: "my`db'name", socketPath: "/custom'path/mysql.sock")
        XCTAssertTrue(create.contains("`my``db'\\''name`"))
        XCTAssertTrue(create.contains("--socket='/custom'\\''path/mysql.sock'"))
        XCTAssertTrue(create.contains("-e 'CREATE DATABASE IF NOT EXISTS `my``db'\\''name`;'"))

        let drop = DatabaseService.buildDropDatabaseCommand(dbName: "my`db'name", socketPath: "/tmp/mysql.sock")
        XCTAssertTrue(drop.contains("-e 'DROP DATABASE IF EXISTS `my``db'\\''name`;'"))

        let show = DatabaseService.buildShowDatabasesCommand(socketPath: "/tmp/mysql.sock")
        XCTAssertTrue(show.contains("-e 'SHOW DATABASES;'"))
    }
}
