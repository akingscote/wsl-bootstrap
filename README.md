# wsl-bootstrap

Dev environments are personal — when you're set up properly they feel like an extension of yourself and make you dramatically more productive. This repo contains my very personal preferences for WSL environments: tools, aliases, zsh, Powerlevel10k theme settings, and everything else that makes a shell feel like home. The intention is to fire up multiple WSL environments and run concurrent workloads without spending hours hand-configuring each one.

The toolchain includes `zsh`, Powerlevel10k, `nvm`/Node, Python + `uv`, Go, OpenTofu, Terragrunt, Azure CLI, GitHub CLI, Copilot CLI, `git-credential-manager`, `mise`, and the shell aliases/integration used across my Ubuntu 24.04 distros.

## How it works

The setup is split into two layers:

1. A text-based bootstrap repo you can version, edit, and rerun.
2. An optional exported WSL base image you can clone quickly when you want speed.

One command spins up a fully configured distro. Run it again with a different name and you have a second isolated environment ready to go.

## Layout

- `new-wsl-profile.ps1` is the single host-side entrypoint: it installs the mandatory font, configures Windows host settings, and creates the named WSL profile.
- `bootstrap/linux/bootstrap.sh` installs packages and copies runtime config into a distro.
- `bootstrap/windows/create-wsl-distro.ps1` creates/imports a distro and runs Linux bootstrap.
- `bootstrap/windows/export-base-distro.ps1` captures a WSL distro as a reusable base tar.
- `bootstrap/windows/configure-host-fonts.ps1` installs MesloLGS NF for the current Windows user and configures Windows Terminal and VS Code to use it.
- `manifests/apt-packages.txt` is the apt package baseline.
- `manifests/tool-versions.env` pins the workstation tool versions.
- `dotfiles/home/` contains the runtime files copied into each distro user profile.
- `assets/fonts/meslo-lgs-nf/` is the packaged cache location for the MesloLGS NF font files and URLs.

## Quick start

### 1. Keep the repo on the Windows host

Suggested location:

```powershell
C:\Users\akingscote\wsl-bootstrap
```

The repo stays on Windows, but the Linux bootstrap copies the active dotfiles into the distro's ext4 home directory for better shell startup performance.

### 2. Create or refresh a WSL profile with one host-side command

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\new-wsl-profile.ps1 -ProfileName ubuntu-dev-01
```

This single entrypoint does three things in order:

1. prompts for the Linux username and password you want inside the new distro;
2. shows a blocking warning/confirmation before any long-running or disruptive action;
3. downloads and installs the mandatory MesloLGS NF font into the current Windows user profile;
4. updates Windows Terminal and VS Code terminal settings to use that font;
5. creates/imports the named WSL profile and runs Linux bootstrap inside it.

By default, this uses a **fresh Ubuntu 24.04 rootfs** and bootstraps it. It does **not** export or clone an existing distro unless you explicitly ask for clone mode.

If you have already reviewed the warning flow and want to skip the confirmation prompt on later runs, add `-Force`.

If you explicitly want clone mode anyway:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\new-wsl-profile.ps1 -ProfileName ubuntu-dev-02 -CloneFromDistro Ubuntu-24.04
```

If you already have a preferred exported base tar:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\new-wsl-profile.ps1 -ProfileName ubuntu-dev-03 -BaseTarPath "$env:USERPROFILE\WSL\images\Ubuntu-24.04.tar"
```

### 3. Advanced helper scripts

Use these only when you want to run one piece of the workflow directly:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\bootstrap\windows\export-base-distro.ps1 -SourceDistro Ubuntu-24.04 -OutputTarPath "$env:USERPROFILE\WSL\images\Ubuntu-24.04.tar"
```

`export-base-distro.ps1` now warns before exporting because exporting a live distro can be slow and can interfere with active WSL sessions.

If you ran an older clone-first version of this package and do not want the exported archive anymore, you can delete `C:\Users\akingscote\WSL\images\Ubuntu-24.04.tar` manually after confirming you no longer need it.

### 4. Refresh an existing distro in place

```bash
/mnt/c/Users/akingscote/wsl-bootstrap/bootstrap/linux/bootstrap.sh --apply --repo-root /mnt/c/Users/akingscote/wsl-bootstrap
```

## Customizing

- Update `manifests/tool-versions.env` when you want newer pinned versions.
- Update `manifests/apt-packages.txt` when you want more baseline Ubuntu packages.
- Edit the files under `dotfiles/home/` and rerun bootstrap to push them into a distro.
- Put machine-specific shell tweaks in `~/.config/wsl-bootstrap/zsh/95-local.zsh` inside a distro rather than hardcoding them into the shared repo.

## Deliberate exclusions

These are intentionally **not** versioned here:

- `~/.ssh`
- `gh` auth state
- `az` login cache
- personal tokens
- machine-local Docker socket overrides beyond the default provided shell env

Instead, bootstrap lays down the config and then you run `gh auth login` and `az login` inside each new distro.

## Known assumptions

- The primary Linux username is `ashley` by default. Override with `-LinuxUser` if needed.
- This repo targets Ubuntu-based WSL distros first.
- Powerlevel10k settings were seeded from the current `~/.p10k.zsh`, and the host entrypoint now installs the required MesloLGS NF font automatically.
- `appendWindowsPath` is **disabled** in each distro's `/etc/wsl.conf` to prevent Windows executables (e.g. `az.cmd`) from shadowing Linux binaries. Windows paths for `explorer.exe` and VS Code are selectively re-added in `10-path-and-env.zsh`. This ensures tools like `AZURE_CONFIG_DIR` work correctly for per-distro isolation.
