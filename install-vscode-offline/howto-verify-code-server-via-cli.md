# How to Verify Code Server via CLI (No GUI)

This guide shows how to confirm that a VS Code–style “code server” is running correctly using only command‑line tools.

---

## 1. Coder `code-server` (VS Code in the Browser)

If you are running [coder/code-server](https://github.com/coder/code-server) on a host or in a container:

1. Start `code-server` (example):
   ```bash
   code-server --bind-addr 127.0.0.1:8080
   ```

2. Check the built‑in health endpoint:
   ```bash
   curl -sS -o /dev/null -w "%{http_code}\n" http://127.0.0.1:8080/healthz
   ```
   - `200` ⇒ `code-server` is up and responding.
   - Anything else ⇒ service is not healthy or not listening on that address.

3. Optionally check the root endpoint:
   ```bash
   curl -I http://127.0.0.1:8080/
   ```
   You should see an HTTP 200 and basic HTML headers.

4. Confirm the process is running:
   ```bash
   pgrep -af code-server
   ```

These checks do not require a browser; they just confirm the HTTP service is live.

---

## 2. VS Code Server for Remote-SSH (Microsoft)

If you are using the official VS Code Server (installed by Remote‑SSH or `install-remote.ps1`):

1. Confirm the server files exist on the remote:
   ```bash
   ls -R ~/.vscode-server/cli/servers
   ```

2. Check that the server process is running:
   ```bash
   ps aux | grep vscode-server | grep -v grep
   ```

3. Inspect the latest server log (paths vary slightly by version):
   ```bash
   ls -t ~/.vscode-server*/**/*.log | head -n 1 | xargs -r tail -n 50
   ```
   Look for “Server started” or similar messages and absence of errors.

4. From the client side, you can also use the VS Code CLI to test a connection:
   ```bash
   code --remote ssh-remote+<host> --command workbench.action.files.openFile
   ```
   This verifies the Remote‑SSH tunnel and server handshake without relying on a visible editor window.

