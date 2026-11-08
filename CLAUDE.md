# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Sigma File Manager: a Tauri 2 desktop app (Windows + Linux). The frontend is Vue 3 + TypeScript + Pinia + vue-i18n, built with Vite. The backend is Rust in `src-tauri/`. The Node version is pinned in `package.json` (`engines`/`volta`); Rust and the Tauri platform prerequisites are also needed.

## Commands

- `npm run tauri:dev`: run the full app (syncs version, then `tauri dev`). On Linux with visual glitches, use `npm run tauri:dev:webkit-igpu`.
- `npm run dev`: Vite only (port 1420, strict). Tauri APIs aren't available without the Tauri shell.
- `npm run check`: runs `ts` (vue-tsc), `lint:check` (eslint + stylelint, zero warnings) and unit tests in parallel. This is what CI runs, and it should pass before a change is done.
- `npm run ts`: type-check only. `npm run lint`: auto-fix eslint + stylelint.
- `npm test`: unit tests (vitest, jsdom), via the `scripts/vitest-run.mjs` wrapper.
  - Single file: `npm run test:unit:run -- src/stores/runtime/__tests__/clipboard.test.ts`
  - Filter by name: `npm run test:unit:run -- -t "name"`
  - Watch mode: `npm run test:unit`
- `npm run tauri:build`: production build (`tauri:build:linux` on Linux, `tauri:windows:build` for MSIX).
- E2E (WebDriver, Windows-oriented) lives in `e2e-webdriver/`: `npm run test:e2e`.
- Rust: `npm run tauri:cargo-build`, or `cargo` commands from `src-tauri/`.

## Side effects of the Vite dev server

`vite.config.ts` uses `vite-plugin-run`. While Vite is running:
- Editing `src/**/*.{vue,ts,js}` or `src-tauri/src/**/*.rs` runs `sync-license`, which rewrites the license header. Every source file starts with the 3-line SPDX/GPL header, so keep it on new files.
- Editing `src/localization/messages/en.json` runs `sync-i18n`, which propagates keys to the other locale files. Edit only `en.json` by hand.

## Architecture

**Frontend (`src/`)**, alias `@` → `src`, `@shared` → `src-shared`:
- `modules/`: feature areas (navigator, nav-sidebar, tab-bar, settings, extensions, global-search, lan-share, quick-view, print-view, dashboard, etc.). Each is largely self-contained, with its own `components/`, `composables/`, `pages/`, and an `index.ts`. `modules/shell.ts` ties the app shell together.
- `stores/` has three layers:
  - `runtime/`: in-memory Pinia stores (navigator state, jobs, clipboard, shortcuts, and so on).
  - `storage/`: persistent stores backed by `@tauri-apps/plugin-store` JSON files in the user-data dir. The file names are defined in `src-shared/user-storage-files.json`, which both TS and Rust read. This covers settings, workspaces, stats and extensions.
  - `schemas/`: schemas and defaults for the persisted data.
- Frontend-to-backend calls are Tauri `invoke('snake_case_command', {...})` against commands registered in `src-tauri/src/lib.rs`. Long-running work (copy/move, delete, archive, dir size, search) runs as Rust jobs. Progress comes back through events into the matching `stores/runtime/*-jobs.ts` store.
- `localization/messages/*.json` hold the i18n strings (`en.json` is the source). The eslint config includes a vue-i18n plugin, so use i18n keys rather than literal UI strings.
- `components/ui` is the shadcn-style primitive set (reka-ui based, configured by `sigma-ui.config.json`). `components/base` holds app-level shared components.
- `src/build/` has custom Vite plugins:
  - It forbids importing `src/assets/media/source-backgrounds/*` into the bundle.
  - It rejects test modules from production builds.
  - `src/test-support/` is test-only; do not import it from app code.

**Extensions system.** Extensions are third-party packages that add commands, pages, settings and so on.
- Frontend: `src/modules/extensions/` has `api/` (the `create-*-api.ts` factories that build the API object handed to an extension), `runtime/` (the sandboxed worker), and `builtin-commands/`.
- Backend: `src-tauri/src/extensions/` handles install, registry storage, permissions (`manifest_permissions.rs`, `security.rs`), sandboxed fs/http/process access, and the binary manager.
- Public contract: `packages/api/` (`index.d.ts`, `manifest.schema.json`) is a publishable npm package (CI runs `npm pack --dry-run`). Changing the extension API means updating it, the frontend `api/` factories and the Rust permission checks together.

**Backend (`src-tauri/src/`)**: one Rust module per capability (`dir_reader`, `dir_watcher`, `global_search`, `lan_share`, `archive`, `terminal`, `system_clipboard`, `open_with`, `app_updater`, `default_file_manager`, and so on). `lib.rs` declares the modules and registers commands. Two auxiliary windows, `quick-view` and `print-view`, are hidden rather than closed. Windows-only code is gated with `#[cfg(windows)]`. Two extra workspace crates, `default-file-manager-common` and `default-file-manager-launcher`, back the Windows "replace File Explorer" feature. Platform packaging lives in `flatpak/`, `snap/` and `.signpath/`.

## Code style (enforced by eslint/stylelint, zero warnings allowed)

- Semicolons; `function` declarations only (`func-style: declaration`); multi-line objects with one property per line.
- Vue: PascalCase component names in templates, max one attribute per line when wrapping.
- File naming is checked by `eslint-plugin-check-file`; follow the existing kebab-case conventions (`use-*.ts` composables, `__tests__/` directories next to the code).
- Stylelint enforces BEM selectors and idiomatic property ordering in `src/**/*.{css,vue}`.

## Cross-platform policy

This is a cross-platform file manager (Windows + Linux, and the Tauri config also targets macOS bundles). Linux is the primary platform for day-to-day work on this fork, so Linux behavior and settings come first. Never remove or break the Windows code paths to do it: keep platform differences behind `#[cfg(...)]` in Rust and `platform-info` checks in TS. `deploy.sh` is Linux-only tooling; the app and the npm scripts stay portable.

## Git workflow (mandatory)

- Always work directly in the main project directory (`/home/masteteams/Projects/file-manager`) on the existing development branch `development`. It was renamed from `dev/ui-fixes` on 2026-11-07, so any older reference to that name means `development`.
- Do not create or enter Git worktrees: no `EnterWorktree` tool, no `--worktree` flag.
- Do not create feature branches or switch away from `development` unless explicitly asked.
- Before making changes, verify the working directory and the current branch. Before committing, inspect the diff (`git diff --check`, `git diff`), stage only the relevant files, and keep one logical fix per commit.
- Never run `npm audit fix --force`. It rewrote `package.json`/`package-lock.json` once and had to be reverted (`abbbb469` was reverted by `02d7d618`). Dependency upgrades are deliberate, per-package changes.
- Remotes: `origin` is the fork (`masterteams/file-manager`). `upstream` is the original Sigma repo with push disabled; only fetch from it. `main` mirrors the original project's main and is not where fork work goes.
- Pushing needs the `masterteams` GitHub account. The machine also holds other `gh` accounts, and using one of them gives a 403. `./deploy.sh push` checks this.

## Running the fork on this machine

The fork is used daily while it is developed. `./deploy.sh` at the repo root manages it. It is Linux-only, needs no sudo, and refuses to run as root. `push` and `pull` sync the `development` branch with the GitHub remote. The other commands run the app on this machine in one of two modes:

- **debug** (default): `tauri dev` + Vite HMR. Use it while developing; edits show up live.
- **permanent**: a release build installed to `~/.local/opt/masterteams-file-manager/` and run as a normal app. Use it for day-to-day use. It does not change while you edit code; refresh it with `build`.

| Command | What it does |
| --- | --- |
| `./deploy.sh start [debug\|permanent]` | Starts the app in the background in its own process group. Debug mode installs deps only if `package-lock.json` is newer than `node_modules` and refuses to start if port 1420 is taken. Permanent mode needs a prior `build`. Both refuse to run off the `development` branch. |
| `./deploy.sh stop` | SIGTERMs the whole process group, then SIGKILL after 15s. |
| `./deploy.sh restart [mode]` | stop, then start. Keeps the current mode unless one is given. |
| `./deploy.sh status` | Mode, process, port 1420, installed build time, Node version vs the pin, branch, uncommitted count, ahead/behind `origin`, active `gh` account. |
| `./deploy.sh build` | `tauri build --no-bundle` (release binary, no AppImage/deb), then installs it atomically. Run it after finishing a feature, then `restart permanent`. |
| `./deploy.sh autostart enable\|disable\|status` | Manages `~/.config/autostart/masterteams-file-manager.desktop`, which runs `deploy.sh start permanent` at every login (5 s delay). It needs a prior `build`. It starts after a graphical login, so a reboot without auto-login waits at the login screen. |
| `./deploy.sh push` | Pushes `development` to `origin/development` using `gh` credentials for that one command. Aborts if the active `gh` account isn't `masterteams`. |
| `./deploy.sh pull` | Fetches and fast-forwards `development` from `origin`. It aborts on a dirty tree and runs `npm ci` if the lockfile changed. |
| `./deploy.sh logs [-f]` | Shows the app log with the Wayland clipboard warning spam filtered out. |

Facts that shape the setup:
- **Data dirs.** Debug mode sets `SFM_E2E_DATA_DIR=~/.local/share/masterteams-file-manager-dev`, which moves data, config, cache and logs there (`src-tauri/src/app_dirs.rs`). The override is compiled out of release builds and **disables single-instance** in debug builds, so run just one debug instance per data dir. A permanent (release) build uses the normal Tauri paths for the app identifier, so it does not share settings with debug mode. The script's pid, mode and log files live in `run/` under the debug data dir.
- **What reloads.** Vue/CSS/TS edits hot-reload. Rust edits make `tauri dev` rebuild and relaunch the app. Changes to `package.json`, `Cargo.toml` or `tauri.conf.json` need `./deploy.sh restart`.
- **Node.** The shell default may differ from the pin (`volta.node` in `package.json`, currently 24.16.0). The script prefers `~/.nvm/versions/node/v<pin>/bin`.
- **Port.** Vite uses port 1420 with `strictPort`; a stale Vite blocks `start`. Find it with `ss -ltnp 'sport = :1420'`.
- **Known log noise.** The clipboard watcher polls about every 400 ms (`clipboard_watcher.rs`). On GNOME Wayland, `arboard` logs a data-control warning each time and falls back to X11. It is harmless. Also harmless: the libayatana-appindicator deprecation message and the `stdout` dead-code warning in `process_runner.rs`.
- **Linux gaps.** `default_file_manager_available()` is false on Linux, so Sigma can't be set as the default file manager from inside the app. Don't bind `inode/directory` to the dev launcher.
- **Verified baseline (2026-11-07, Node 24.16.0, after reverting the `npm audit fix --force` commit).** `npm run check` exits 0: tsc, eslint and stylelint at zero warnings, and 176 test files / 1184 tests passing. `cargo check` in `src-tauri/` passes with one warning, the unread `ProcessRunOutput.stdout` field. Check its callers before removing it. `npm ci` reports 43 audit advisories. Assess them per package; do not bulk-fix.
- **Clipboard bug (unfixed).** In `src-tauri/src/system_clipboard/files.rs` on Unix, the `operation` argument is ignored when writing, and reading always returns `"copy"`. Cut/copy of files between Sigma and other apps can't be told apart.
- `~/.local/bin/file-manager-dev` and the `masterteams-file-manager-dev.desktop` launcher run the debug app in the foreground with a terminal. `deploy.sh` is the background, scriptable variant.
- A packaged AppImage/`.deb` (`npm run tauri:build:linux`) is for when a stable state is reached; `deploy.sh build` deliberately skips bundling.

## Workflow notes

- `CONTRIBUTING.md` asks that a feature be discussed in an issue before it is implemented. The default branch is `main`. The working branch is `development`, and the app identity in `src-tauri/tauri.conf.json` has been set up for an independent dev build.
- `CHANGELOG.md` tracks releases; `npm run sync-version` propagates the `package.json` version to the Tauri/Cargo configs.
