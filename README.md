# SynergyProp 2.0

This repository contains two MetaTrader 5 Expert Advisors that implement the TradingView "Synergy Strategy" with a prop-firm style hedge engine.

## Projects
- **PropMain** – main EA that trades the challenge account and dispatches hedge signals.
- **PropHDG** – hedge EA that runs on a separate MT5 account and executes opposite trades.
- **Synergy Strategy** – the original TradingView script for reference.

## Building
Compile `PropMain` and `PropHDG` in MetaEditor or using the `mql5compiler` command line. Each EA exposes an input named `CommunicationMethod`:

- `GLOBAL_VARS` (default) – share signals via MT5 global variables (same terminal only).
- `FILE_BASED` – share signals using a text file located in the common data folder.

Set `CommunicationMethod` to `FILE_BASED` when PropMain and PropHDG run on different terminals or accounts.

For further details about the shared-file fix see `docs/CONNECTION_FIX_NOTES.md`.
