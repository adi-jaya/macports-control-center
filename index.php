<?php
$files = [
    'README.md' => 'Panduan Utama & Cheatsheet CLI',
    'VIRTUAL_HOSTS_AND_DOMAINS_GUIDE.md' => 'Panduan Virtual Host, Domain .test & SSL',
    'FRESH_INSTALL_GUIDE.md' => 'Panduan Setup Laravel & Multi-Versi dari Nol',
    'FINAL_MACPORTS_ENVIRONMENT_SETUP.md' => 'Dokumentasi Konfigurasi & Stack MacPorts',
    'HANDOFF_MACPORTS_MIGRATION.md' => 'Riwayat & Detail Migrasi (FlyEnv & Herd)'
];

$viewFile = $_GET['file'] ?? 'README.md';
if (!array_key_exists($viewFile, $files)) {
    $viewFile = 'README.md';
}

$filePath = __DIR__ . '/' . $viewFile;
$content = file_exists($filePath) ? file_get_contents($filePath) : 'Berkas tidak ditemukan.';
?>
<!DOCTYPE html>
<html lang="id">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Dokumentasi MacPorts - <?= htmlspecialchars($viewFile) ?></title>
    <script src="https://cdn.jsdelivr.net/npm/marked/marked.min.js"></script>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; background: #0f172a; color: #f8fafc; margin: 0; padding: 0; }
        .wrapper { display: flex; min-height: 100vh; }
        .sidebar { width: 300px; background: #1e293b; border-right: 1px solid #334155; padding: 1.5rem; flex-shrink: 0; }
        .sidebar h2 { font-size: 1.1rem; color: #38bdf8; margin-top: 0; padding-bottom: 0.5rem; border-bottom: 1px solid #334155; }
        .sidebar a { display: block; color: #94a3b8; text-decoration: none; padding: 0.5rem 0.75rem; border-radius: 6px; margin-bottom: 0.25rem; font-size: 0.9rem; }
        .sidebar a:hover, .sidebar a.active { background: #334155; color: #f8fafc; font-weight: 600; }
        .content { flex-grow: 1; padding: 2.5rem 3.5rem; max-width: 900px; overflow-y: auto; }
        .back-link { display: inline-block; margin-bottom: 1.5rem; color: #38bdf8; text-decoration: none; font-size: 0.9rem; }
        .back-link:hover { text-decoration: underline; }
        #markdown-view { line-height: 1.6; color: #e2e8f0; }
        #markdown-view h1, #markdown-view h2, #markdown-view h3 { color: #f8fafc; border-bottom: 1px solid #334155; padding-bottom: 0.3rem; }
        #markdown-view pre { background: #0f172a; border: 1px solid #334155; border-radius: 8px; padding: 1rem; overflow-x: auto; }
        #markdown-view code { font-family: monospace; color: #38bdf8; background: #1e293b; padding: 0.2rem 0.4rem; border-radius: 4px; font-size: 0.9em; }
        #markdown-view pre code { background: none; padding: 0; color: #cbd5e1; }
        #markdown-view table { width: 100%; border-collapse: collapse; margin: 1rem 0; }
        #markdown-view th, #markdown-view td { border: 1px solid #334155; padding: 0.6rem 0.8rem; text-align: left; }
        #markdown-view th { background: #1e293b; color: #f8fafc; }
        #markdown-view blockquote { border-left: 4px solid #38bdf8; margin: 1rem 0; padding-left: 1rem; color: #94a3b8; }
        .path-info { background: #1e293b; border: 1px solid #334155; border-radius: 8px; padding: 0.75rem 1rem; margin-top: 2rem; font-size: 0.85rem; color: #94a3b8; }
    </style>
</head>
<body>
    <div class="wrapper">
        <aside class="sidebar">
            <h2>📖 MacPorts Docs</h2>
            <a href="/" style="margin-bottom: 1rem; color: #38bdf8;">&larr; Ke Dashboard Server</a>
            <div style="font-size: 0.75rem; text-transform: uppercase; letter-spacing: 0.05em; color: #64748b; margin-bottom: 0.5rem; font-weight: bold;">Dokumen Tersedia</div>
            <?php foreach ($files as $f => $label): ?>
                <a href="?file=<?= urlencode($f) ?>" class="<?= $f === $viewFile ? 'active' : '' ?>">
                    <?= htmlspecialchars($label) ?>
                </a>
            <?php endforeach; ?>

            <div class="path-info">
                <strong>Lokasi Finder macOS:</strong><br>
                <code>~/Documents/MacPorts_Docs</code>
            </div>
        </aside>

        <main class="content">
            <a href="/" class="back-link">&larr; Kembali ke Dashboard Server</a>
            <div id="markdown-view"></div>
        </main>
    </div>

    <script>
        const rawMarkdown = <?= json_encode($content) ?>;
        document.getElementById('markdown-view').innerHTML = marked.parse(rawMarkdown);
    </script>
</body>
</html>
