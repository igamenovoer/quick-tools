Here are reliable ways to run SSH commands from **Windows** non-interactively **without sshpass**.

### Option A — Use Windows’ built-in OpenSSH (recommended)

1. **Create a key and load it into the agent**

```powershell
# generate a modern key
ssh-keygen -t ed25519 -a 100

# start the Windows ssh-agent and load your key
Get-Service ssh-agent | Set-Service -StartupType Automatic
Start-Service ssh-agent
ssh-add $env:USERPROFILE\.ssh\id_ed25519
```

Windows documents key-based auth and the ssh-agent service here. ([Microsoft Learn][1])

2. **Install your public key on the remote and set perms**
   Append `~/.ssh/id_ed25519.pub` to the remote’s `~/.ssh/authorized_keys` (one-time). The OpenSSH manual shows the standard `authorized_keys` location. ([man.openbsd.org][2])

3. **Pre-trust the host key (so there’s no prompt)**

* EITHER add it ahead of time:

```powershell
ssh-keyscan -t rsa,ecdsa,ed25519 your.host >> $env:USERPROFILE\.ssh\known_hosts
```

`ssh-keyscan` is the canonical way to gather host keys for non-interactive use. ([man.openbsd.org][3])

* OR use OpenSSH’s **auto-add** on first connect:

```powershell
ssh -o StrictHostKeyChecking=accept-new user@your.host 'true'
```

(`accept-new` adds new hosts but still **blocks** on changed keys; great for scripts.) ([man7.org][4])

4. **Run commands non-interactively**

```powershell
# no TTY, no prompts, fails fast if auth needed
ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -T user@your.host 'uname -a && whoami'
```

* `BatchMode=yes` disables any password/passphrase prompts. ([man7.org][4])
* `-T` disables pseudo-terminal allocation (cleaner for scripts). ([man.openbsd.org][2])
* Add `-n` if you might run it in the background or pipe input. ([man.openbsd.org][2])

> Tip (PowerShell quoting): put the remote command in **single quotes** so PowerShell doesn’t expand it.

---

### Option B — Use PuTTY’s `plink.exe` (also passwordless)

1. **Use a key**
   Either convert/import a key with **PuTTYgen** or load it into **Pageant** (the PuTTY agent). ([tartarus.org][5])

2. **Avoid host-key prompts**

* One-time interactive acceptance caches the host key in your user registry so later runs are silent. ([the.earth.li][6])
* For fully non-interactive first use, pass the expected fingerprint:

```cmd
plink -batch -ssh -hostkey "SHA256:AAA...your-fingerprint..." -i C:\keys\my.ppk user@your.host "uname -a"
```

`-batch` disables all prompts; `-hostkey` pins the server key. ([Documentation Help][7])

3. **Examples**

```cmd
:: single command with a PPK key
plink -batch -ssh -i C:\keys\my.ppk user@your.host "sudo systemctl restart mysvc"

:: run a list of commands from a local file
plink -batch -ssh -i C:\keys\my.ppk user@your.host -m C:\path\commands.txt
```

(Non-interactive/batch usage is a core Plink feature.) ([the.earth.li][8])

---

### Option C — PowerShell remoting **over SSH** (nice for Windows↔Windows/Linux)

If you prefer PowerShell cmdlets and sessions:

```powershell
Invoke-Command -HostName your.host -UserName user `
  -KeyFilePath $env:USERPROFILE\.ssh\id_ed25519 `
  -ScriptBlock { Get-Process | Select-Object -First 3 }
```

PowerShell 7+ supports SSH transport via `-HostName/-UserName/-KeyFilePath`. ([Microsoft Learn][9])

---

## Why this works (and why no `sshpass` is needed)

* **Key-based auth + agent** provides non-interactive logins safely on Windows (no plaintext passwords, no extra tools). ([Microsoft Learn][1])
* **Host key handling** is what normally triggers an interactive prompt; solve it by **pre-seeding** with `ssh-keyscan`, using `StrictHostKeyChecking=accept-new`, or (with PuTTY) the `-hostkey` pin. ([man.openbsd.org][3])

If you hit a “unknown host key” or “prompt blocked my script” situation with **Plink** under a different Windows account (e.g., Task Scheduler), remember host keys are cached **per-user** in the registry—pre-seed or use `-hostkey`. ([kb.catalogicsoftware.com][10])

If you need SSO in an AD domain: Windows OpenSSH supports **GSSAPI/Kerberos** (set `GSSAPIAuthentication yes` / use `ssh -K`), but that’s optional. ([Microsoft Learn][11])

That’s it—pick OpenSSH or Plink, install your key once, pre-trust the host key properly, and your Windows box can run SSH commands non-interactively and safely.

[1]: https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_keymanagement "Key-Based Authentication in OpenSSH for Windows | Microsoft Learn"
[2]: https://man.openbsd.org/ssh.1 "ssh(1) - OpenBSD manual pages"
[3]: https://man.openbsd.org/ssh-keyscan.1?utm_source=chatgpt.com "ssh-keyscan(1) - OpenBSD manual pages"
[4]: https://man7.org/linux/man-pages/man5/ssh_config.5.html "ssh_config(5) - Linux manual page"
[5]: https://tartarus.org/~simon/putty-snapshots/htmldoc/Chapter8.html?utm_source=chatgpt.com "Using public keys for SSH authentication"
[6]: https://the.earth.li/~sgtatham/putty/0.62/puttydoc.txt?utm_source=chatgpt.com "PuTTY User Manual"
[7]: https://documentation.help/PuTTY/plink-option-batch.html?utm_source=chatgpt.com "-batch: disable all interactive prompts - PuTTY Documentation"
[8]: https://the.earth.li/~sgtatham/putty/0.58/htmldoc/Chapter7.html?utm_source=chatgpt.com "Using the command-line connection tool Plink"
[9]: https://learn.microsoft.com/en-us/powershell/scripting/security/remoting/ssh-remoting-in-powershell?view=powershell-7.5 "PowerShell Remoting Over SSH - PowerShell | Microsoft Learn"
[10]: https://kb.catalogicsoftware.com/s/article/46630?utm_source=chatgpt.com "Using PuTTY's plink Command to Automate SSH Actions on ..."
[11]: https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh-server-configuration?utm_source=chatgpt.com "OpenSSH Server Configuration for Windows"
