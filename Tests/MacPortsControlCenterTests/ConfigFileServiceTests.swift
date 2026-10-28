#if canImport(XCTest)
import XCTest
@testable import MacPortsControlCenter
#else
import Foundation
#endif

final class ConfigFileServiceTests: XCTestCase {
    func testParseAndUpdateIgnoresCommentedDirectives() {
        let phpIni = """
        ;memory_limit = 128M
        memory_limit = 256M
        upload_max_filesize = 2M
        post_max_size = 8M
        max_execution_time = 30
        """
        let nginxConf = """
        http {
            # client_max_body_size 1M;
            client_max_body_size 64M;
        }
        """
        let tuning = ConfigFileService.parsePHPIniTuning(phpIniContent: phpIni, nginxConfContent: nginxConf)
        XCTAssertEqual(tuning.memoryLimit, "256M")
        XCTAssertEqual(tuning.nginxClientMaxBodySize, "64M")

        var newTuning = tuning
        newTuning.memoryLimit = "512M"
        newTuning.uploadMaxFilesize = "128M"
        let updatedIni = ConfigFileService.updatePHPIni(content: phpIni, tuning: newTuning)
        XCTAssertTrue(updatedIni.contains(";memory_limit = 128M"))
        XCTAssertTrue(updatedIni.contains("memory_limit = 512M"))
        XCTAssertTrue(updatedIni.contains("upload_max_filesize = 128M"))

        let updatedNginx = ConfigFileService.updateNginxClientMaxBodySize(content: nginxConf, maxBodySize: "128M")
        XCTAssertTrue(updatedNginx.contains("# client_max_body_size 1M;"))
        XCTAssertTrue(updatedNginx.contains("client_max_body_size 128M;"))
    }

    func testConfigureFPMWwwConfSetsUserAndUniquePort() {
        let raw = """
        [www]
        ; user = nobody
        user = nobody
        ; group = nobody
        group = nobody
        ; listen = 127.0.0.1:9000
        listen = 127.0.0.1:9000
        """
        let php82 = ConfigFileService.configureFPMWwwConf(content: raw, version: "82", user: "adijaya", group: "staff")
        XCTAssertTrue(php82.contains("; user = nobody"))
        XCTAssertTrue(php82.contains("user = adijaya"))
        XCTAssertTrue(php82.contains("group = staff"))
        XCTAssertTrue(php82.contains("listen = 127.0.0.1:9082"))

        let php83 = ConfigFileService.configureFPMWwwConf(content: raw, version: "83", user: "adijaya", group: "staff")
        XCTAssertTrue(php83.contains("listen = 127.0.0.1:9000"))
    }

    func testParseLaravelEnvHandlesQuotesAndComments() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let envContent = """
        APP_NAME="SiAkurat"
        APP_URL="http://localhost:8080" # local url
        # DB_DATABASE=wrong_db
        DB_DATABASE = 'db_siakurat_sifat' # main db
        """
        try envContent.write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let parsed = ConfigFileService.parseLaravelEnv(at: tmp.path)
        XCTAssertEqual(parsed.database, "db_siakurat_sifat")
        XCTAssertEqual(parsed.appURL, "http://localhost:8080")
    }

    func testIsNginxTestOutputValidHandlesNonRootPidWarningAndRejectsSyntaxErrors() {
        let nonRootValidOutput = """
        nginx: [alert] could not open error log file: open() "/opt/local/var/log/nginx/error.log" failed (13: Permission denied)
        nginx: the configuration file /opt/local/etc/nginx/nginx.conf syntax is ok
        2026/10/27 20:43:41 [emerg] 4076#0: open() "/opt/local/var/run/nginx/nginx.pid" failed (13: Permission denied)
        nginx: configuration file /opt/local/etc/nginx/nginx.conf test failed
        """
        XCTAssertTrue(ConfigFileService.isNginxTestOutputValid(exitCode: 1, output: nonRootValidOutput))

        let realSyntaxErrorOutput = """
        2026/10/27 20:43:41 [emerg] 4076#0: unknown directive "fastcgi_pass_typo" in /opt/local/etc/nginx/servers/test.conf:12
        nginx: configuration file /opt/local/etc/nginx/nginx.conf test failed
        """
        XCTAssertFalse(ConfigFileService.isNginxTestOutputValid(exitCode: 1, output: realSyntaxErrorOutput))
    }

    func testSaveVHostRollsBackWhenValidatorFails() async throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let confFile = tmpDir.appendingPathComponent("test.conf")
        try "original-valid-config".write(to: confFile, atomically: true, encoding: .utf8)

        do {
            try await ConfigFileService.saveVHostWithValidation(filePath: confFile.path, content: "broken-config") {
                return (false, "nginx: [emerg] invalid directive")
            }
            XCTFail("Expected validation error")
        } catch {
            let restored = try String(contentsOf: confFile, encoding: .utf8)
            XCTAssertEqual(restored, "original-valid-config")
        }
    }

    func testGenerateAndParseLaravelVHost() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let projectDir = tmpDir.appendingPathComponent("my-laravel")
        let publicDir = projectDir.appendingPathComponent("public")
        try FileManager.default.createDirectory(at: publicDir, withIntermediateDirectories: true)

        let envFile = projectDir.appendingPathComponent(".env")
        try "DB_DATABASE=\"my_blog_db\"\nAPP_URL=\"http://localhost:8085\"\n".write(to: envFile, atomically: true, encoding: .utf8)

        let generated = ConfigFileService.generateVHostConfig(
            serverName: "localhost 127.0.0.1",
            listenPort: "8085",
            rootPath: publicDir.path,
            fpmPort: 9082,
            template: .laravel,
            sslCertPath: nil,
            sslKeyPath: nil
        )

        let confFile = tmpDir.appendingPathComponent("my-laravel.conf")
        try generated.write(to: confFile, atomically: true, encoding: .utf8)

        let parsed = ConfigFileService.parseVHost(filePath: confFile.path)
        XCTAssertNotEqual(parsed, nil)
        XCTAssertEqual(parsed?.fileName, "my-laravel.conf")
        XCTAssertEqual(parsed?.listenPort, "8085")
        XCTAssertEqual(parsed?.serverName, "localhost 127.0.0.1")
        XCTAssertEqual(parsed?.rootPath, publicDir.path)
        XCTAssertEqual(parsed?.fastcgiPass, "127.0.0.1:9082")
        XCTAssertEqual(parsed?.sslEnabled, false)
        XCTAssertEqual(parsed?.laravelDatabase, "my_blog_db")
        XCTAssertEqual(parsed?.laravelAppURL, "http://localhost:8085")
    }

    func testGenerateAndParseSPAVHostWithSSL() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let distDir = tmpDir.appendingPathComponent("dist")
        try FileManager.default.createDirectory(at: distDir, withIntermediateDirectories: true)

        let certPath = "/opt/local/etc/nginx/ssl/frontend.test.pem"
        let keyPath = "/opt/local/etc/nginx/ssl/frontend.test-key.pem"

        let generated = ConfigFileService.generateVHostConfig(
            serverName: "frontend.test",
            listenPort: "443",
            rootPath: distDir.path,
            fpmPort: 9000,
            template: .spa,
            sslCertPath: certPath,
            sslKeyPath: keyPath
        )

        let confFile = tmpDir.appendingPathComponent("frontend.conf")
        try generated.write(to: confFile, atomically: true, encoding: .utf8)

        let parsed = ConfigFileService.parseVHost(filePath: confFile.path)
        XCTAssertNotEqual(parsed, nil)
        XCTAssertEqual(parsed?.fileName, "frontend.conf")
        XCTAssertEqual(parsed?.listenPort, "443")
        XCTAssertEqual(parsed?.serverName, "frontend.test")
        XCTAssertEqual(parsed?.rootPath, distDir.path)
        XCTAssertEqual(parsed?.sslEnabled, true)
    }

    func testParseRealHostConfigsIfPresent() {
        let siakuratPath = "/opt/local/etc/nginx/servers/siakurat.conf"
        guard FileManager.default.fileExists(atPath: siakuratPath) else { return }

        let parsed = ConfigFileService.parseVHost(filePath: siakuratPath)
        XCTAssertNotEqual(parsed, nil)
        XCTAssertEqual(parsed?.fileName, "siakurat.conf")
        XCTAssertEqual(parsed?.listenPort, "8080")
        XCTAssertEqual(parsed?.serverName, "localhost 127.0.0.1")
        XCTAssertEqual(parsed?.fastcgiPass, "127.0.0.1:9000")
        XCTAssertEqual(parsed?.sslEnabled, false)
        XCTAssertEqual(parsed?.laravelDatabase, "db_siakurat_sifat")
        XCTAssertEqual(parsed?.laravelAppURL, "http://localhost")
    }
}
