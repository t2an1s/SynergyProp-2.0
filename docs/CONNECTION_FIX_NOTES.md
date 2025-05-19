# Fixing PropMain ↔ PropHDG connectivity

The current releases of the EAs (`PropMain` and `PropHDG`) rely on **global variables** to exchange heartbeat and trading signals. Global variables are only visible inside the same MetaTrader 5 terminal. If each EA runs on a different terminal (e.g. prop account vs live account), the global-variable link never appears and the dashboard reports *NOT OK*.

A simple workaround is switching to the file-based communication mode and storing the signal file inside the **common data folder** so both terminals can access it.

## Steps
1. In the EA inputs set `CommunicationMethod` to `FILE_BASED` for both EAs.
2. Modify the source code so the signal file path uses `TerminalInfoString(TERMINAL_COMMONDATA_PATH)`:

```mql5
string commFile = TerminalInfoString(TERMINAL_COMMONDATA_PATH) + "\\Synergy_Signals.txt";
int fileHandle = FileOpen(commFile, FILE_WRITE|FILE_TXT);
```
3. Recompile both EAs using the changed path.
4. Ensure both terminals have permission to read/write the common data folder.

Using the common data location lets the heartbeat file be shared across installations and the link becomes stable.
