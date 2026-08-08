# Homebrew formula for the wiki-mcp daemon.
#
# Canonical copy lives in pdxmph/homebrew-tap as Formula/wiki-mcp.rb; this is
# the reviewable source of truth, and .github/workflows/release.yml bumps the
# tap's copy (version / tag / revision) on each tagged release.
#
# Source is fetched over git+SSH because mph-llm-experiments/mcp-wiki is
# private while the tap is public. The Mac mini already has SSH keys, so no new
# credential is introduced anywhere; the formula is simply inert for anyone
# without access to the repo.
#
# Deliberately builds from source at install time rather than shipping a
# prebuilt tarball: better-sqlite3 is a native module, and compiling it against
# whatever Node `brew` resolves is the only way to be sure the ABI matches.
class WikiMcp < Formula
  desc "Local daemon indexing a personal knowledge corpus over HTTP"
  homepage "https://github.com/mph-llm-experiments/mcp-wiki"
  url "git@github.com:mph-llm-experiments/mcp-wiki.git",
      using:    :git,
      tag:      "v0.2.0",
      revision: "8ee869935541b0f3b910e979ed4afb4d6cb96ebc"
  version "0.2.0"

  depends_on "node"

  def install
    # npm ci, never npm install — the lockfile records `libc` fields that an
    # older npm silently strips, turning an install into an unmarked downgrade.
    # Dev dependencies are needed here because the build runs tsc.
    system "npm", "ci"
    system "npm", "run", "daemon:build"
    system "npm", "prune", "--omit=dev"

    libexec.install "dist", "node_modules", "package.json"

    (bin/"wiki-mcp-daemon").write <<~SH
      #!/bin/bash
      exec "#{Formula["node"].opt_bin}/node" "#{libexec}/dist/daemon/index.js" "$@"
    SH
    chmod 0755, bin/"wiki-mcp-daemon"

    (var/"log/wiki-mcp").mkpath
  end

  # Replaces the hand-rolled launchd/com.mikehall.wiki-mcp.plist, which ran the
  # daemon straight out of a git working tree.
  #
  # No environment_variables block on purpose: this formula lives in a public
  # tap, and the daemon's settings include an Anthropic key and a GitHub token.
  # The daemon reads those itself from ~/.config/wiki-mcp/env at boot (see
  # src/daemon/config-file.ts), so secrets never touch the formula and an
  # upgrade never has to re-plumb them.
  service do
    run [opt_bin/"wiki-mcp-daemon"]
    keep_alive true
    log_path var/"log/wiki-mcp/daemon.log"
    error_log_path var/"log/wiki-mcp/daemon.err"
  end

  def caveats
    <<~EOS
      Configuration lives in a file the daemon reads at startup:

        ~/.config/wiki-mcp/env

      Example:

        WIKI_MCP_NOTES_DIR=#{Dir.home}/notes
        WIKI_MCP_DB_PATH=#{Dir.home}/.wiki-mcp/wiki-mcp.db
        WIKI_MCP_PORT=7891
        # ANTHROPIC_API_KEY=...        # enables artifact ingestion
        # WIKI_MCP_GITHUB_TOKEN=...    # enables the GitHub mirror
        # WIKI_MCP_GITHUB_REPO=owner/name

      Real environment variables take precedence over this file.

      Note: WIKI_MCP_NOTES_DIR must exist. The watcher ignores dot-prefixed
      paths (including its own root), and a missing directory is swallowed by
      chokidar — either way the daemon starts, reports healthy, and indexes
      nothing.

      Start it with:

        brew services start wiki-mcp
    EOS
  end

  test do
    # The daemon does not create its notes directory, and a missing one yields a
    # process that looks healthy while indexing nothing — so create it first.
    (testpath/"notes").mkpath
    port = free_port

    pid = spawn(
      {
        "HOME"               => testpath.to_s,
        "WIKI_MCP_NOTES_DIR" => "#{testpath}/notes",
        "WIKI_MCP_DB_PATH"   => "#{testpath}/db/wiki-mcp.db",
        "WIKI_MCP_PORT"      => port.to_s,
      },
      "#{bin}/wiki-mcp-daemon",
    )

    begin
      sleep 5
      assert_match "\"total_notes\":0", shell_output("curl -s http://127.0.0.1:#{port}/config")
      assert_match "ok", shell_output("curl -s http://127.0.0.1:#{port}/health")
    ensure
      Process.kill "TERM", pid
      Process.wait pid
    end
  end
end
