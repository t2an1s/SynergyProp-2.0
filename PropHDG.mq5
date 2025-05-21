//+------------------------------------------------------------------+
//|                                                    PropEA_HDG.mq5 |
//|   Prop‑style Hedge Engine (paired with Synergy Strategy v1.01)   |
//|                                                                  |
//|  CHANGE LOG (v2.05 – 20‑May‑2025)                                |
//|   • Fixed excessive logging to reduce Experts tab clutter       |
//|   • Added LogVerbosity setting to control debug output          |
//|   • Reduced frequency of routine status messages                |
//|   • Only log important events: errors, signals, state changes   |
//|   • Added bidirectional heartbeat / link‑monitor                |
//|   • Dashboard shows "Hedge Link OK / NOT OK" status             |
//|   • Debug prints on link loss / recovery                        |
//|   • Minor refactors – consts, helpers, tidy dashboard code      |
//|   • Added advanced diagnostics for troubleshooting              |
//|   • Added cross-account file-based communication support        |
//|   • Fixed file paths and permissions for cross-terminal access  |
//+------------------------------------------------------------------+
#property copyright "t2an1s"
#property link      "http://www.yourwebsite.com"
#property version   "2.05"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

//────────────────────────────────────────────────────────────────────
// 1. ENUMS & INPUTS
//────────────────────────────────────────────────────────────────────

enum ENUM_COMMUNICATION_METHOD { GLOBAL_VARS, FILE_BASED };
enum ENUM_LOG_LEVEL { LOG_ERRORS_ONLY, LOG_IMPORTANT, LOG_VERBOSE };

input group "General Settings"
input string    EA_Name               = "PropEA Hedge";   // display only
input int       Magic_Number          = 789123;            // must match hedgeMagic in prop EA
input bool      EnableTrading         = true;
input ENUM_COMMUNICATION_METHOD CommunicationMethod = FILE_BASED; // Use FILE_BASED for cross-account
input ENUM_LOG_LEVEL LogVerbosity     = LOG_IMPORTANT;     // Control logging verbosity

input group "Hedge Settings"
input int       SourceEA_Magic        = 123456;            // magic of main strategy EA

input group "Cost Recovery Settings"
input bool      EnableBleedFeature    = true;
input double    MinimumLot            = 0.01;

//────────────────────────────────────────────────────────────────────
// 2. CONSTANTS & GLOBALS
//────────────────────────────────────────────────────────────────────

// Heart‑beat parameters (same values as prop side)
const int HEARTBEAT_SEC    = 5;
const int LINK_TIMEOUT_SEC = 15;

bool mainEALinkRequired = true;        // Hedge EA always requires main EA link
bool mainEALinkEstablished = false;    // Status of main EA connection
datetime lastMainEACheck = 0;          // Last time we checked main EA
bool hedgeReadyForTrading = false;     // Overall trading readiness status

ulong lastPulseSent   = 0;   // when we last pinged
bool  linkWasOK       = false;

// bleed flag (dashboard)
bool  bleedDone       = false;

double initialBalance = 0;

// dashboard prefix
string dash = "PropEA_Hedge_";

// Diagnostic counters
int timerCount = 0;

// File communication constants - USE RELATIVE PATHS
string COMM_FILE_PATH = "MQL5\\Files\\MT5com.txt";
string HEARTBEAT_FILE_PATH = "MQL5\\Files\\MT5com_hedge_heartbeat.txt";
string MAIN_HEARTBEAT_FILE_PATH = "MQL5\\Files\\MT5com_heartbeat.txt";
string HEDGE_DATA_FILE_PATH = "MQL5\\Files\\HedgeData.txt";
const int FILE_WRITE_RETRY = 3;   // Number of retries for file operations
const int FILE_CHECK_SECONDS = 5;  // How often to check for heartbeat

//────────────────────────────────────────────────────────────────────
// 3. LOGGING HELPERS
//────────────────────────────────────────────────────────────────────
void LogInfo(string message) {
   if(LogVerbosity >= LOG_VERBOSE) Print(message);
}

void LogImportant(string message) {
   if(LogVerbosity >= LOG_IMPORTANT) Print(message);
}

void LogError(string message) {
   Print("ERROR: ", message); // Always log errors
}

void LogWarning(string message) {
   if(LogVerbosity >= LOG_IMPORTANT) Print("WARNING: ", message);
}

//────────────────────────────────────────────────────────────────────
// 4. HELPER – STRING HASH (shared with prop EA)
//────────────────────────────────────────────────────────────────────
ulong StringGetTickCount(string text)
{
   ulong r=0; for(int i=0;i<StringLen(text);i++) r+=(ulong)StringGetCharacter(text,i);
   return r;
}

//────────────────────────────────────────────────────────────────────
// 5. HEART‑BEAT HELPERS
//────────────────────────────────────────────────────────────────────
void SendHeartbeat()
{
   if(CommunicationMethod == GLOBAL_VARS)
   {
      string name = "HEDGE_HB_" + IntegerToString(Magic_Number);
      double currentTime = (double)TimeCurrent();
      GlobalVariableSet(name, currentTime);
      lastPulseSent = (ulong)TimeCurrent();
      
      // Only log heartbeat on startup or errors - remove periodic spam
      static bool startupLogged = false;
      if(!startupLogged) {
         LogInfo("Hedge EA heartbeat initialized: " + name);
         startupLogged = true;
      }
   }
   else // FILE_BASED
   {
      // Create heartbeat file with timestamp - MUST USE FILE_COMMON FLAG
      int fileHandle = FileOpen(HEARTBEAT_FILE_PATH, FILE_WRITE|FILE_TXT|FILE_COMMON);
      if(fileHandle != INVALID_HANDLE)
      {
         string heartbeatData = "HEDGE_HEARTBEAT," + IntegerToString(Magic_Number) + "," + 
                               IntegerToString(TimeCurrent());
         FileWriteString(fileHandle, heartbeatData);
         FileClose(fileHandle);
         
         // Only report file creation once at startup
         static bool fileHeartbeatLogged = false;
         if(!fileHeartbeatLogged) {
            LogInfo("File-based heartbeat initialized: " + HEARTBEAT_FILE_PATH);
            fileHeartbeatLogged = true;
         }
      }
      else
      {
         int errorCode = GetLastError();
         static datetime lastErrorReport = 0;
         if(TimeCurrent() - lastErrorReport > 300) {  // Report errors every 5 minutes instead of 30 seconds
            LogError("Failed to write heartbeat file: " + IntegerToString(errorCode) + " - " + 
                  (errorCode == 5002 ? "Cannot create file (permissions?)" :
                   errorCode == 4103 ? "Invalid path" : 
                   errorCode == 5004 ? "No disk space" : "File error"));
            lastErrorReport = TimeCurrent();
         }
      }
      
      lastPulseSent = (ulong)TimeCurrent();
   }
}

bool IsLinkAlive()
{
   if(CommunicationMethod == GLOBAL_VARS)
   {
      string peer = "PROP_HB_" + IntegerToString(SourceEA_Magic);
      
      if(!GlobalVariableCheck(peer)) {
         static datetime lastErrorTime = 0;
         if(TimeCurrent() - lastErrorTime > 300) { // Reduce frequency to 5 minutes
            LogWarning("Main EA heartbeat not found: " + peer);
            lastErrorTime = TimeCurrent();
         }
         return false;
      }
      
      double ts = GlobalVariableGet(peer);
      // calculate age using long to avoid uint cast warning
      long ageSecondsGV = TimeCurrent() - (datetime)ts;
      bool isAlive = ageSecondsGV <= LINK_TIMEOUT_SEC;
      
      // Only log when status changes, not periodically
      static bool wasAlive = true; // Assume alive at start
      static bool firstCheck = true;
      
      if(isAlive != wasAlive || firstCheck) {
         LogImportant("Main EA link status: " + (isAlive ? "ALIVE" : "DEAD") + 
               " (Last beat: " + TimeToString((datetime)ts) + 
               ", Age: " + IntegerToString((int)ageSecondsGV) + "s)");
         wasAlive = isAlive;
         firstCheck = false;
      }
      
      return isAlive;
   }
   else // FILE_BASED
   {
      if(!FileIsExist(MAIN_HEARTBEAT_FILE_PATH, FILE_COMMON))
      {
         static datetime lastErrorReport = 0;
         if(TimeCurrent() - lastErrorReport > 300) { // Reduce frequency to 5 minutes
            LogWarning("Main EA heartbeat file not found: " + MAIN_HEARTBEAT_FILE_PATH);
            lastErrorReport = TimeCurrent();
         }
         return false;
      }
      
      int fileHandle = FileOpen(MAIN_HEARTBEAT_FILE_PATH, FILE_READ|FILE_TXT|FILE_COMMON);
      if(fileHandle == INVALID_HANDLE)
      {
         static datetime lastErrorReport = 0;
         if(TimeCurrent() - lastErrorReport > 60) {
            LogError("Unable to open main heartbeat file. Error: " + IntegerToString(GetLastError()));
            lastErrorReport = TimeCurrent();
         }
         return false;
      }
      
      string content = FileReadString(fileHandle);
      FileClose(fileHandle);
      
      // Only log content in verbose mode
      LogInfo("Read from main file: " + content);
      
      // Parse heartbeat data: format is MAIN_HEARTBEAT,magicnumber,timestamp
      string parts[];
      int count = StringSplit(content, ',', parts);
            
      // Check if magic number matches
      if(parts[1] != IntegerToString(SourceEA_Magic))
      {
         static datetime lastMagicError = 0;
         if(TimeCurrent() - lastMagicError > 300) {
            LogError("Main heartbeat has incorrect magic number: " + parts[1] + 
                  " expected: " + IntegerToString(SourceEA_Magic));
            lastMagicError = TimeCurrent();
         }
         return false;
      }
      
      // Check timestamp - FIXED CALCULATION
      string timestampString = parts[2];
      if(StringLen(timestampString) > 0)
      {
         datetime heartbeatTime = (datetime)StringToInteger(timestampString);
         
         if(heartbeatTime > 0)
         {
            int ageSeconds = (int)(TimeCurrent() - heartbeatTime);
            bool isAlive = ageSeconds <= LINK_TIMEOUT_SEC;
            
            // Only log when status changes
            static bool wasAlive = true;
            static bool firstCheck = true;
            
            if(isAlive != wasAlive || firstCheck)
            {
               LogImportant("Main EA link status: " + (isAlive ? "ALIVE" : "DEAD") + 
                     " (Last heartbeat: " + TimeToString(heartbeatTime) + 
                     ", Age: " + IntegerToString((int)ageSeconds) + "s)");
               wasAlive = isAlive;
               firstCheck = false;
            }
            
            return isAlive;
         }
         else
         {
            LogError("Invalid timestamp value: " + timestampString + " parsed as " + IntegerToString(heartbeatTime));
            return false;
         }
      }
      else
      {
         LogError("Empty timestamp string in heartbeat");
         return false;
      }
   }
}

//────────────────────────────────────────────────────────────────────
// 6. INIT / DEINIT
//────────────────────────────────────────────────────────────────────
//+------------------------------------------------------------------+
//| Enhanced OnInit for Hedge EA with Link Verification              |
//+------------------------------------------------------------------+


int OnInit()
{
   Print("===== HEDGE EA STARTUP v2.06 =====");
   Print("Magic_Number: ", Magic_Number);
   Print("SourceEA_Magic: ", SourceEA_Magic);
   Print("CommunicationMethod: ", CommunicationMethod == GLOBAL_VARS ? "GLOBAL_VARS" : "FILE_BASED");
   Print("LogVerbosity: ", LogVerbosity == LOG_ERRORS_ONLY ? "ERRORS_ONLY" : 
                           LogVerbosity == LOG_IMPORTANT ? "IMPORTANT" : "VERBOSE");
   
   trade.SetExpertMagicNumber(Magic_Number);
   initialBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   
   // Initialize link status
   mainEALinkEstablished = false;
   hedgeReadyForTrading = false;
   
   Print("=== HEDGE LINK REQUIREMENTS ===");
   Print("🔗 Main EA connection is REQUIRED for hedge operations");
   Print("   Hedge EA will NOT process signals until main EA link is established");
   Print("   Target Main EA Magic: ", SourceEA_Magic);
   
   CreateDashboard();
   
   if(CommunicationMethod == GLOBAL_VARS)
   {
      Print("=== GLOBAL VARIABLES SETUP ===");
      // CRITICAL: Register our heartbeat and check if it worked
      string heartbeatName = "HEDGE_HB_" + IntegerToString(Magic_Number);
      GlobalVariableSet(heartbeatName, (double)TimeCurrent());
      
      // Verify the heartbeat was set
      if(GlobalVariableCheck(heartbeatName)) {
         double checkValue = GlobalVariableGet(heartbeatName);
         LogImportant("✅ HEDGE HEARTBEAT VERIFIED: Variable " + heartbeatName + " = " + TimeToString((datetime)checkValue));
      } else {
         LogError("❌ Failed to set hedge heartbeat global variable: " + heartbeatName);
      }
      
      // Check if we can find the main EA's heartbeat
      string mainHeartbeat = "PROP_HB_" + IntegerToString(SourceEA_Magic);
      if(GlobalVariableCheck(mainHeartbeat)) {
         double mainValue = GlobalVariableGet(mainHeartbeat);
         LogImportant("✅ MAIN EA HEARTBEAT FOUND: " + mainHeartbeat + " = " + TimeToString((datetime)mainValue));
      } else {
         LogError("❌ Main EA heartbeat not found: " + mainHeartbeat);
         LogError("   Is the Main EA running? Is its Magic Number set correctly to " + IntegerToString(SourceEA_Magic) + "?");
      }
      
      // Only dump variables in verbose mode
      if(LogVerbosity >= LOG_VERBOSE) {
         Print("--- ALL GLOBAL VARIABLES AT STARTUP ---");
         for(int i=0; i<GlobalVariablesTotal(); i++) {
            string name = GlobalVariableName(i);
            double value = GlobalVariableGet(name);
            Print(i, ": ", name, " = ", value, " (time: ", TimeToString((datetime)value), ")");
         }
         Print("--------------------------------------");
      }
   }
   else // FILE_BASED mode
   {
      Print("=== FILE COMMUNICATION SETUP ===");
      LogImportant("File-based communication paths:");
      LogImportant("- Hedge heartbeat: " + HEARTBEAT_FILE_PATH);
      LogImportant("- Main heartbeat: " + MAIN_HEARTBEAT_FILE_PATH);
      LogImportant("- Signal file: " + COMM_FILE_PATH);
      HEDGE_DATA_FILE_PATH = commonPath + "HedgeData.txt";
      LogImportant("- Hedge data file: " + HEDGE_DATA_FILE_PATH);
      
      // Test file access for heartbeat with FILE_COMMON flag
      int fileHandle = FileOpen(HEARTBEAT_FILE_PATH, FILE_WRITE|FILE_TXT|FILE_COMMON);
      if(fileHandle != INVALID_HANDLE)
      {
         FileWriteString(fileHandle, "HEDGE_HEARTBEAT," + IntegerToString(Magic_Number) + "," + 
                        IntegerToString(TimeCurrent()));
         FileClose(fileHandle);
         LogImportant("✅ File-based hedge communication initialized. Magic: " + IntegerToString(Magic_Number));
      }
      else
      {
         int errorCode = GetLastError();
         LogError("❌ Failed to create heartbeat file: " + IntegerToString(errorCode) + " - " + 
               (errorCode == 5002 ? "Cannot create file (permissions?)" :
                errorCode == 4103 ? "Invalid path" : "File error"));
         LogError("   File path attempted: " + HEARTBEAT_FILE_PATH);
         LogWarning("   EA will continue but file communication may not work properly");
      }
   }
   
   // Start heartbeat timer
   EventSetTimer(2); // Check every 2 seconds initially
   SendHeartbeat();
   
   // Perform initial link check
   Print("=== INITIAL MAIN EA LINK CHECK ===");
   PerformInitialMainEALinkCheck();
   
   Print("=== HEDGE EA STATUS ===");
   Print("Main EA Link Required: ", mainEALinkRequired ? "TRUE" : "FALSE");
   Print("Main EA Link Established: ", mainEALinkEstablished ? "TRUE" : "FALSE");
   Print("Hedge Ready for Trading: ", hedgeReadyForTrading ? "TRUE" : "FALSE");
   
   if(mainEALinkEstablished)
   {
      Print("✅ HEDGE EA READY: Can process signals from Main EA");
   }
   else
   {
      Print("🚫 HEDGE EA WAITING: No signals will be processed until Main EA connects");
   }
   
   Print("PropEA Hedge initialized. Link ", mainEALinkEstablished ? "ESTABLISHED ✅" : "WAITING ❌");
   
   return(INIT_SUCCEEDED);
}


void OnDeinit(const int reason)
{
   EventKillTimer();
   DeleteDashboard();
   
   // Clean up files in file-based mode
   if(CommunicationMethod == FILE_BASED) {
      string commonPath = TerminalInfoString(TERMINAL_COMMONDATA_PATH) + "\\MQL5\\Files";
      string heartbeatFile = commonPath + "\\MT5com_hedge_heartbeat.txt";
      
      int fileHandle = FileOpen(heartbeatFile, FILE_READ|FILE_TXT);
      if(fileHandle != INVALID_HANDLE) {
         FileClose(fileHandle);
         if(FileDelete(heartbeatFile)) {
            LogInfo("Deleted hedge heartbeat file: " + heartbeatFile);
         } else {
            LogWarning("Failed to delete heartbeat file: " + IntegerToString(GetLastError()));
         }
      }
   }
   
   Print("PropEA Hedge stopped. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| Perform initial main EA link check during initialization         |
//+------------------------------------------------------------------+
void PerformInitialMainEALinkCheck()
{
   Print("Checking for Main EA connection...");
   
   // Give some time for Main EA to initialize if starting together
   Sleep(2000); // Wait 2 seconds
   
   bool linkStatus = IsLinkAlive();
   mainEALinkEstablished = linkStatus;
   hedgeReadyForTrading = linkStatus;
   linkWasOK = linkStatus;
   lastMainEACheck = TimeCurrent();
   
   if(mainEALinkEstablished)
   {
      Print("🔗 MAIN EA LINK ESTABLISHED!");
      Print("   ✅ Connection confirmed with Main EA (Magic: ", SourceEA_Magic, ")");
      Print("   ✅ Hedge EA is now READY to process signals");
   }
   else
   {
      Print("🔗 MAIN EA LINK NOT FOUND");
      Print("   ❌ No connection with Main EA (Magic: ", SourceEA_Magic, ")");
      Print("   🚫 Signal processing is BLOCKED until connection established");
      Print("   📋 To enable hedge operations:");
      Print("      1. Start Main EA with Magic Number ", SourceEA_Magic);
      Print("      2. Ensure same communication method (", CommunicationMethod == GLOBAL_VARS ? "GLOBAL_VARS" : "FILE_BASED", ")");
      Print("      3. Check that both EAs can access communication files/variables");
   }
}


//+------------------------------------------------------------------+
//| Enhanced OnTimer with main EA link monitoring                    |
//+------------------------------------------------------------------+
void OnTimer()
{
   timerCount++;
   
   // Send heartbeat
   SendHeartbeat();
   
   // Reduced startup debugging - only first 3 ticks instead of 10
   if(timerCount <= 3 && LogVerbosity >= LOG_VERBOSE) {
      if(CommunicationMethod == GLOBAL_VARS) {
         string heartbeatName = "HEDGE_HB_" + IntegerToString(Magic_Number);
         LogInfo("STARTUP DEBUG [" + IntegerToString(timerCount) + "]: Heartbeat " + heartbeatName + " sent");
         
         string mainHeartbeat = "PROP_HB_" + IntegerToString(SourceEA_Magic);
         if(GlobalVariableCheck(mainHeartbeat)) {
            LogInfo("  → Main EA heartbeat found: " + mainHeartbeat);
         } else {
            LogInfo("  → Main EA heartbeat missing: " + mainHeartbeat);
         }
      }
      else {
         LogInfo("STARTUP DEBUG [" + IntegerToString(timerCount) + "]: File heartbeat sent");
         LogInfo("  → My file exists: " + (FileIsExist(HEARTBEAT_FILE_PATH, FILE_COMMON) ? "YES" : "NO"));
         LogInfo("  → Main file exists: " + (FileIsExist(MAIN_HEARTBEAT_FILE_PATH, FILE_COMMON) ? "YES" : "NO"));
      }
   } 
   // After 3 ticks, switch to normal heartbeat interval
   else if(timerCount == 4) {
      EventKillTimer();
      EventSetTimer(HEARTBEAT_SEC);
      LogInfo("Switching to normal heartbeat interval of " + IntegerToString(HEARTBEAT_SEC) + " seconds");
   }
   
   // Check link status and update hedge readiness
   bool currentLinkStatus = IsLinkAlive();
   
   // Update main EA link status
   bool statusChanged = (currentLinkStatus != mainEALinkEstablished);
   mainEALinkEstablished = currentLinkStatus;
   hedgeReadyForTrading = currentLinkStatus;
   
   if(statusChanged)
   {
      if(mainEALinkEstablished)
      {
         Print("🔗 MAIN EA LINK ESTABLISHED! Hedge operations now ENABLED ✅");
      }
      else
      {
         Print("🔗 MAIN EA LINK LOST! Hedge operations now BLOCKED 🚫");
         Print("   Reconnect Main EA (Magic: ", SourceEA_Magic, ") to resume hedge operations");
      }
   }
   
   // Log status changes
   if(currentLinkStatus != linkWasOK)
   {
      Print("Main EA link status changed: ", currentLinkStatus ? "CONNECTED ✅" : "DISCONNECTED ❌");
      
      // When link fails, print diagnostics
      if(!currentLinkStatus) 
      {
         Print("--- MAIN EA LINK DIAGNOSTICS ---");
         Print("Communication Method: ", CommunicationMethod == GLOBAL_VARS ? "GLOBAL_VARS" : "FILE_BASED");
         Print("Target Magic Number: ", SourceEA_Magic);
         Print("Our Magic Number: ", Magic_Number);
         
         if(CommunicationMethod == GLOBAL_VARS)
         {
            Print("Expected Global Variable: PROP_HB_", SourceEA_Magic);
            Print("Current Global Variables:");
            for(int i=0; i<GlobalVariablesTotal(); i++) 
            {
               string name = GlobalVariableName(i);
               double value = GlobalVariableGet(name);
               Print("  ", name, " = ", value);
            }
         }
         else
         {
            Print("Expected File: ", MAIN_HEARTBEAT_FILE_PATH);
            Print("File Exists: ", FileIsExist(MAIN_HEARTBEAT_FILE_PATH, FILE_COMMON) ? "YES" : "NO");
         }
         Print("-----------------------------");
      }
      
      linkWasOK = currentLinkStatus;
   }
   
   lastMainEACheck = TimeCurrent();
}

//+------------------------------------------------------------------+
//| Check if hedge operations are allowed                            |
//+------------------------------------------------------------------+
bool IsHedgeOperationAllowed()
{
   // Basic trading enabled check
   if(!EnableTrading)
   {
      return false;
   }
   
   // Main EA link requirement check
   if(mainEALinkRequired && !mainEALinkEstablished)
   {
      // Periodically remind about blocked status
      static datetime lastReminder = 0;
      if(TimeCurrent() - lastReminder > 60) // Every minute
      {
         Print("⏳ Hedge operations blocked: Waiting for Main EA link (Magic: ", SourceEA_Magic, ")");
         lastReminder = TimeCurrent();
      }
      return false;
   }
   
   return true;
}


//+------------------------------------------------------------------+
//| Enhanced OnTick with link verification                           |
//+------------------------------------------------------------------+
void OnTick()
{
   if(!EnableTrading) return;

   UpdateDashboard();
   PublishHedgeMetrics();

   // Greatly reduced status logging - only every 10 minutes instead of 1 minute
   static datetime lastTickLog = 0;
   if(TimeCurrent() - lastTickLog > 600 && LogVerbosity >= LOG_VERBOSE) {
      if(CommunicationMethod == GLOBAL_VARS) {
         string peerHB = "PROP_HB_" + IntegerToString(SourceEA_Magic);
         string myHB = "HEDGE_HB_" + IntegerToString(Magic_Number);
         
         string peerStatus = GlobalVariableCheck(peerHB) ? "FOUND" : "NOT FOUND";
         string myStatus = GlobalVariableCheck(myHB) ? "FOUND" : "NOT FOUND";
         
         LogInfo("HEDGE EA STATUS: My heartbeat (" + myHB + "): " + myStatus + 
               ", Main EA heartbeat (" + peerHB + "): " + peerStatus);
      }
      else {
         LogInfo("HEDGE EA STATUS: My heartbeat file: " + (FileIsExist(HEARTBEAT_FILE_PATH, FILE_COMMON) ? "EXISTS" : "MISSING") + 
               ", Main heartbeat file: " + (FileIsExist(MAIN_HEARTBEAT_FILE_PATH, FILE_COMMON) ? "EXISTS" : "MISSING"));
      }
      
      lastTickLog = TimeCurrent();
   }

   // CRITICAL: Only process hedge signals if operations are allowed
   if(!IsHedgeOperationAllowed())
   {
      static datetime lastBlockWarning = 0;
      if(TimeCurrent() - lastBlockWarning > 300) // Every 5 minutes
      {
         LogWarning("Hedge operations blocked: Main EA link not established");
         lastBlockWarning = TimeCurrent();
      }
      return;
   }

   // Only process hedge traffic if link alive (double check)
   bool linkStatus = IsLinkAlive();
   if(!linkStatus) {
      static datetime lastLinkWarning = 0;
      if(TimeCurrent() - lastLinkWarning > 300) { // Reduce warning frequency to 5 minutes
         LogWarning("Main EA link is DOWN. Hedge operations paused.");
         lastLinkWarning = TimeCurrent();
      }
      return;
   }

   CheckForHedgeSignals();
   ManageHedgePositions();
}


//────────────────────────────────────────────────────────────────────
// 9. COMMUNICATION LAYER (read signals)
//────────────────────────────────────────────────────────────────────

void ProcessSignal(string signalType,string direction,double volume,double tp,double sl); // fwd decl

//+------------------------------------------------------------------+
//| Enhanced CheckForHedgeSignals with link verification             |
//+------------------------------------------------------------------+
void CheckForHedgeSignals()
{
   // Additional safety check
   if(!IsHedgeOperationAllowed())
   {
      return;
   }
   
   if(CommunicationMethod == GLOBAL_VARS)
   {
      string base = IntegerToString(SourceEA_Magic);
      string signalTimeVar = "EASignal_Time_" + base;
      
      // Reduce variable check frequency to every 5 minutes in verbose mode only
      static datetime lastCheckTime = 0;
      if(TimeCurrent() - lastCheckTime > 300 && LogVerbosity >= LOG_VERBOSE) {
         if(!GlobalVariableCheck(signalTimeVar)) {
            LogInfo("Signal variable not found: " + signalTimeVar + " (normal if no signals sent)");
         }
         lastCheckTime = TimeCurrent();
      }
      
      if(!GlobalVariableCheck(signalTimeVar)) return;
      datetime sigTime = (datetime)GlobalVariableGet(signalTimeVar);
      static datetime last = 0; 
      
      if(sigTime == 0 || sigTime == last) return;

      ulong typeCode = (ulong)GlobalVariableGet("EASignal_Type_" + base);
      ulong dirCode = (ulong)GlobalVariableGet("EASignal_Direction_" + base);
      double vol = GlobalVariableGet("EASignal_Volume_" + base);
      double sl = GlobalVariableGet("EASignal_SL_" + base);
      double tp = GlobalVariableGet("EASignal_TP_" + base);

      string sType = "", dir = "";
      if(typeCode == StringGetTickCount("OPEN")) sType = "OPEN";
      else if(typeCode == StringGetTickCount("MODIFY")) sType = "MODIFY";
      else if(typeCode == StringGetTickCount("PARTIAL_CLOSE")) sType = "PARTIAL_CLOSE";
      else if(typeCode == StringGetTickCount("BLEED")) sType = "BLEED";
      else LogWarning("Unknown signal type code: " + IntegerToString(typeCode));

      if(dirCode == StringGetTickCount("BUY")) dir = "BUY";
      else if(dirCode == StringGetTickCount("SELL")) dir = "SELL";
      else LogWarning("Unknown direction code: " + IntegerToString(dirCode));

      if(sType != "" && dir != "") {
         LogImportant("Signal received from Main EA: " + sType + " " + dir + " " + DoubleToString(vol, 2) + 
               " lots, TP: " + DoubleToString(tp, 5) + ", SL: " + DoubleToString(sl, 5));
         ProcessSignal(sType, dir, vol, tp, sl);
      } else {
         LogWarning("Invalid signal - Type: " + sType + ", Direction: " + dir);
      }

      last = sigTime;
   }
   else // FILE_BASED
   {
      if(!FileIsExist(COMM_FILE_PATH, FILE_COMMON)) return;
      
      int fileHandle = FileOpen(COMM_FILE_PATH, FILE_READ|FILE_TXT|FILE_COMMON);
      if(fileHandle == INVALID_HANDLE)
      {
         static datetime lastErrorReport = 0;
         if(TimeCurrent() - lastErrorReport > 60)
         {
            LogError("Unable to open signal file. Error: " + IntegerToString(GetLastError()));
            lastErrorReport = TimeCurrent();
         }
         return;
      }
      
      string content = FileReadString(fileHandle);
      FileClose(fileHandle);
      
      if(!FileDelete(COMM_FILE_PATH, FILE_COMMON))
      {
         LogWarning("Failed to delete signal file after reading. Error: " + IntegerToString(GetLastError()));
      }
      
      // Process signal data - format: signalType,direction,volume,tp,sl,magicNumber,timestamp
      string parts[];
      int count = StringSplit(content, ',', parts);
      
      if(count < 7)
      {
         LogError("Invalid signal format: " + content);
         return;
      }
      
      string signalType = parts[0];
      string direction = parts[1];
      double volume = StringToDouble(parts[2]);
      double tp = StringToDouble(parts[3]);
      double sl = StringToDouble(parts[4]);
      int magicNumber = (int)StringToInteger(parts[5]);
      datetime signalTime = (datetime)StringToInteger(parts[6]);
      
      if(magicNumber != SourceEA_Magic)
      {
         LogWarning("Received signal with unexpected magic number: " + IntegerToString(magicNumber) + 
               " expected: " + IntegerToString(SourceEA_Magic));
         return;
      }
      
      if(TimeCurrent() - signalTime > 60)
      {
         LogWarning("Ignoring old signal from " + TimeToString(signalTime));
         return;
      }
      
      LogImportant("Signal received from Main EA: " + signalType + " " + direction + " " + 
            DoubleToString(volume, 2) + " lots, TP: " + DoubleToString(tp, 5) + 
            ", SL: " + DoubleToString(sl, 5));
      
      ProcessSignal(signalType, direction, volume, tp, sl);
   }
}


//────────────────────────────────────────────────────────────────────
// 10. EXECUTE/UPDATE/CLOSE TRADES
//────────────────────────────────────────────────────────────────────

string GetRetcodeDescription(int retcode)
{
   switch(retcode)
   {
      case 10004: return "TRADE_RETCODE_REQUOTE - Requote";
      case 10006: return "TRADE_RETCODE_REJECT - Request rejected";
      case 10007: return "TRADE_RETCODE_CANCEL - Request canceled";
      case 10008: return "TRADE_RETCODE_PLACED - Order placed";
      case 10009: return "TRADE_RETCODE_DONE - Request completed";
      case 10010: return "TRADE_RETCODE_DONE_PARTIAL - Request completed partially";
      case 10011: return "TRADE_RETCODE_ERROR - Request processing error";
      case 10012: return "TRADE_RETCODE_TIMEOUT - Request timeout";
      case 10013: return "TRADE_RETCODE_INVALID - Invalid request";
      case 10014: return "TRADE_RETCODE_INVALID_VOLUME - Invalid volume";
      case 10015: return "TRADE_RETCODE_INVALID_PRICE - Invalid price";
      case 10016: return "TRADE_RETCODE_INVALID_STOPS - Invalid stops";
      case 10017: return "TRADE_RETCODE_TRADE_DISABLED - Trade disabled";
      case 10018: return "TRADE_RETCODE_MARKET_CLOSED - Market closed";
      case 10019: return "TRADE_RETCODE_NO_MONEY - Not enough money";
      case 10020: return "TRADE_RETCODE_PRICE_CHANGED - Price changed";
      case 10021: return "TRADE_RETCODE_PRICE_OFF - Price off";
      case 10022: return "TRADE_RETCODE_INVALID_EXPIRATION - Invalid expiration";
      case 10023: return "TRADE_RETCODE_ORDER_CHANGED - Order changed";
      case 10024: return "TRADE_RETCODE_TOO_MANY_REQUESTS - Too many requests";
      case 10025: return "TRADE_RETCODE_NO_CHANGES - No changes";
      case 10026: return "TRADE_RETCODE_SERVER_DISABLES_AT - Server disables AT";
      case 10027: return "TRADE_RETCODE_CLIENT_DISABLES_AT - Client disables AT";
      case 10028: return "TRADE_RETCODE_LOCKED - Request locked";
      case 10029: return "TRADE_RETCODE_FROZEN - Order frozen";
      case 10030: return "TRADE_RETCODE_INVALID_FILL - Invalid fill";
      case 10031: return "TRADE_RETCODE_CONNECTION - No connection";
      case 10032: return "TRADE_RETCODE_ONLY_REAL - Only real accounts";
      case 10033: return "TRADE_RETCODE_LIMIT_ORDERS - Order limit reached";
      case 10034: return "TRADE_RETCODE_LIMIT_VOLUME - Volume limit reached";
      case 10035: return "TRADE_RETCODE_INVALID_ORDER - Invalid order";
      case 10036: return "TRADE_RETCODE_POSITION_CLOSED - Position closed";
      default: return "Unknown retcode: " + IntegerToString(retcode);
   }
}

bool ValidateTradeParameters(string direction, double volume, double sl, double tp)
{
   // Check if market is open
   if(!SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE))
   {
      LogError("Trading is disabled for " + _Symbol);
      return false;
   }
   
   // Get symbol specifications
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   // Validate volume
   if(volume < minLot)
   {
      LogError("Volume too small: " + DoubleToString(volume, 2) + " < min: " + DoubleToString(minLot, 2));
      return false;
   }
   
   if(volume > maxLot)
   {
      LogError("Volume too large: " + DoubleToString(volume, 2) + " > max: " + DoubleToString(maxLot, 2));
      return false;
   }
   
   // Normalize volume to lot step
   double normalizedVolume = MathRound(volume / lotStep) * lotStep;
   if(MathAbs(volume - normalizedVolume) > 0.0001)
   {
      LogWarning("Volume adjusted from " + DoubleToString(volume, 2) + " to " + DoubleToString(normalizedVolume, 2));
   }
   
   // Check account margin
   if(AccountInfoInteger(ACCOUNT_TRADE_ALLOWED) == false)
   {
      LogError("Trading is not allowed for this account");
      return false;
   }
   
   // Check if we have enough margin
   double requiredMargin = 0;
   if(direction == "BUY")
   {
      if(!OrderCalcMargin(ORDER_TYPE_BUY, _Symbol, volume, SymbolInfoDouble(_Symbol, SYMBOL_ASK), requiredMargin))
      {
         LogError("Cannot calculate margin for BUY order");
         return false;
      }
   }
   else
   {
      if(!OrderCalcMargin(ORDER_TYPE_SELL, _Symbol, volume, SymbolInfoDouble(_Symbol, SYMBOL_BID), requiredMargin))
      {
         LogError("Cannot calculate margin for SELL order");
         return false;
      }
   }
   
   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   if(requiredMargin > freeMargin)
   {
      LogError("Not enough margin: Required " + DoubleToString(requiredMargin, 2) + 
               " > Available " + DoubleToString(freeMargin, 2));
      return false;
   }
   
   return true;
}

void ProcessSignal(string signalType, string direction, double volume, double tp, double sl)
{
   if(volume < MinimumLot && volume > 0) volume = MinimumLot;

   if(signalType == "OPEN")
   {
      LogInfo("Processing OPEN signal: " + direction + " " + DoubleToString(volume, 2) + 
              " lots, TP: " + DoubleToString(tp, 5) + ", SL: " + DoubleToString(sl, 5));
      
      // Validate trading parameters first
      if(!ValidateTradeParameters(direction, volume, sl, tp))
      {
         LogError("Trade validation failed - signal rejected");
         return;
      }
      
      // Normalize SL/TP values - set to 0 if they are very small
      if(MathAbs(sl) < 0.00001) sl = 0;
      if(MathAbs(tp) < 0.00001) tp = 0;
      
      // Get current prices
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      
      if(ask == 0 || bid == 0)
      {
         LogError("Cannot get current prices - ASK: " + DoubleToString(ask, 5) + 
                 " BID: " + DoubleToString(bid, 5));
         return;
      }
      
      bool ok = false;
      if(direction == "BUY" && volume > 0)
      {
         LogInfo("Executing BUY order at ASK: " + DoubleToString(ask, 5));
         ok = trade.Buy(volume, _Symbol, ask, sl, tp, "Hedge");
      }
      else if(direction == "SELL" && volume > 0)
      {
         LogInfo("Executing SELL order at BID: " + DoubleToString(bid, 5));
         ok = trade.Sell(volume, _Symbol, bid, sl, tp, "Hedge");
      }
      else
      {
         LogError("Invalid trade direction or volume: " + direction + " " + DoubleToString(volume, 2));
         return;
      }

      uint ret = trade.ResultRetcode();
      
      if(!ok)
      {
         string errorDetail = GetRetcodeDescription(ret);
         LogError("Hedge OPEN failed: " + errorDetail + " (code: " + IntegerToString(ret) + 
                 ") LastError: " + IntegerToString(GetLastError()));
         
         // Additional diagnostic info
         LogError("Symbol: " + _Symbol + ", Volume: " + DoubleToString(volume, 2) + 
                 ", Ask: " + DoubleToString(ask, 5) + ", Bid: " + DoubleToString(bid, 5));
         LogError("Account margin free: " + DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN_FREE), 2));
         LogError("Trading allowed: " + (AccountInfoInteger(ACCOUNT_TRADE_ALLOWED) ? "Yes" : "No"));
      }
      else
      {
                  LogImportant("✅ Hedge OPEN " + direction + " " + DoubleToString(volume, 2) + 
                        " lots SUCCESS (retcode: " + IntegerToString(ret) + ")");
         
         // Log the actual order details
         if(trade.ResultOrder() > 0)
         {
            LogImportant("Order ticket: " + IntegerToString((long)trade.ResultOrder()) + 
                        ", Fill price: " + DoubleToString(trade.ResultPrice(), 5));
         }
      }
   }
   else if(signalType == "MODIFY")
   {
      bool found = false;
      for(int i = 0; i < PositionsTotal(); i++)
      {
         if(PositionSelectByTicket(PositionGetTicket(i)))
         {
            if(PositionGetInteger(POSITION_MAGIC) == Magic_Number && 
               PositionGetString(POSITION_SYMBOL) == _Symbol)
            {
               ulong ticket = PositionGetTicket(i);
               
               // Normalize SL/TP values
               if(MathAbs(sl) < 0.00001) sl = 0;
               if(MathAbs(tp) < 0.00001) tp = 0;
               
               bool modifyOk = trade.PositionModify(ticket, sl, tp);
               
               if(modifyOk)
               {
                  LogImportant("✅ Hedge MODIFY successful - Ticket: " + IntegerToString(ticket) + 
                              " SL: " + DoubleToString(sl, 5) + " TP: " + DoubleToString(tp, 5));
               }
               else
               {
                  uint ret = trade.ResultRetcode();
                  LogError("Hedge MODIFY failed: " + GetRetcodeDescription(ret) + 
                          " (code: " + IntegerToString(ret) + ") Ticket: " + IntegerToString(ticket));
               }
               
               found = true;
               break;
            }
         }
      }
      
      if(!found)
      {
         LogWarning("MODIFY signal received but no hedge position found");
      }
   }
   else if((signalType == "PARTIAL_CLOSE" || signalType == "BLEED") && volume > 0)
   {
      bool found = false;
      for(int i = 0; i < PositionsTotal(); i++)
      {
         if(PositionSelectByTicket(PositionGetTicket(i)))
         {
            if(PositionGetInteger(POSITION_MAGIC) == Magic_Number && 
               PositionGetString(POSITION_SYMBOL) == _Symbol)
            {
               ulong ticket = PositionGetTicket(i);
               double positionVolume = PositionGetDouble(POSITION_VOLUME);
               
               // Ensure we don't try to close more than available
               if(volume > positionVolume)
               {
                  LogWarning("Requested close volume " + DoubleToString(volume, 2) + 
                           " > position volume " + DoubleToString(positionVolume, 2) + 
                           ". Adjusting to position volume.");
                  volume = positionVolume;
               }
               
               bool closeOk = trade.PositionClosePartial(ticket, volume);
               
               if(closeOk)
               {
                  LogImportant("✅ Hedge " + signalType + " successful - Closed " + 
                              DoubleToString(volume, 2) + " lots from ticket " + IntegerToString(ticket));
                  
                  if(signalType == "BLEED") bleedDone = true;
               }
               else
               {
                  uint ret = trade.ResultRetcode();
                  LogError("Hedge " + signalType + " failed: " + GetRetcodeDescription(ret) + 
                          " (code: " + IntegerToString(ret) + ") Ticket: " + IntegerToString(ticket));
               }
               
               found = true;
               break;
            }
         }
      }
      
      if(!found)
      {
         LogWarning(signalType + " signal received but no hedge position found");
      }
   }
   else
   {
      LogWarning("Unknown signal type or invalid parameters: " + signalType + 
                " " + direction + " " + DoubleToString(volume, 2));
   }
}

// Simple housekeeping print - greatly reduced frequency
void ManageHedgePositions()
{
   static datetime last=0; 
   if(TimeCurrent()-last<600) return; // Changed from 60 to 600 seconds (10 minutes)
   last=TimeCurrent();
   
   int cnt=0; double vol=0;
   for(int i=0;i<PositionsTotal();i++)
      if(PositionSelectByTicket(PositionGetTicket(i)))
         if(PositionGetInteger(POSITION_MAGIC)==Magic_Number && PositionGetString(POSITION_SYMBOL)==_Symbol)
         { cnt++; vol+=PositionGetDouble(POSITION_VOLUME);}  
   
   if(cnt > 0 || LogVerbosity >= LOG_VERBOSE) { // Only log if positions exist or verbose mode
      LogInfo("Active hedge pos: " + IntegerToString(cnt) + " total " + DoubleToString(vol,2) + " lots");
   }
}

//────────────────────────────────────────────────────────────────────
// 11. DASHBOARD (very lightweight)
//────────────────────────────────────────────────────────────────────
void CreateLabel(string name,string txt,int x,int y,color c){
   ObjectCreate(0,name,OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
   ObjectSetString (0,name,OBJPROP_TEXT,txt);
   ObjectSetInteger(0,name,OBJPROP_COLOR,c);
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
}

//+------------------------------------------------------------------+
//| Enhanced Dashboard with hedge status                             |
//+------------------------------------------------------------------+
void CreateDashboard()
{
   DeleteDashboard();
   ObjectCreate(0,dash+"bg",OBJ_RECTANGLE_LABEL,0,0,0);
   ObjectSetInteger(0,dash+"bg",OBJPROP_XDISTANCE,20);
   ObjectSetInteger(0,dash+"bg",OBJPROP_YDISTANCE,20);
   ObjectSetInteger(0,dash+"bg",OBJPROP_XSIZE,260);
   ObjectSetInteger(0,dash+"bg",OBJPROP_YSIZE,240); // Increased height for new status
   ObjectSetInteger(0,dash+"bg",OBJPROP_BGCOLOR,clrNavy);
   ObjectSetInteger(0,dash+"bg",OBJPROP_STYLE,STYLE_SOLID);
   ObjectSetInteger(0,dash+"bg",OBJPROP_HIDDEN,true);

   CreateLabel(dash+"title","PropEA Hedge v2.06", 150,35, clrGold);
   CreateLabel(dash+"commL","Comm",  40,60, clrWhite);
   CreateLabel(dash+"commV",CommunicationMethod == GLOBAL_VARS ? "Global" : "Files", 120,60, clrYellow);
   CreateLabel(dash+"linkL","Main EA Link",   40,80, clrWhite);
   CreateLabel(dash+"linkV","--",    120,80, clrRed);
   CreateLabel(dash+"statusL","Hedge Status", 40,100, clrWhite);
   CreateLabel(dash+"statusV","WAITING", 120,100, clrRed);
   CreateLabel(dash+"bleedL","Bleed", 40,120, clrWhite);
   CreateLabel(dash+"bleedV","Pending",120,120, clrRed);
   CreateLabel(dash+"logL","Log Level", 40,140, clrWhite);
   CreateLabel(dash+"logV",LogVerbosity == LOG_ERRORS_ONLY ? "Errors" : 
                          LogVerbosity == LOG_IMPORTANT ? "Important" : "Verbose", 120,140, clrCyan);
   
   // Add diagnostic info to dashboard
   CreateLabel(dash+"magicL","Magic", 40,160, clrWhite);
   CreateLabel(dash+"magicV",IntegerToString(Magic_Number),120,160, clrWhite);
   CreateLabel(dash+"sourceL","Source", 40,180, clrWhite);
   CreateLabel(dash+"sourceV",IntegerToString(SourceEA_Magic),120,180, clrWhite);
   CreateLabel(dash+"hbL","Last HB", 40,200, clrWhite);
   CreateLabel(dash+"hbV","--",120,200, clrWhite);
}

void UpdateDashboard()
{
   // Main EA Link Status
   color linkCol = mainEALinkEstablished ? clrLime : clrRed;
   string linkTxt = mainEALinkEstablished ? "CONNECTED" : "WAITING";
   ObjectSetString (0,dash+"linkV",OBJPROP_TEXT, linkTxt);
   ObjectSetInteger(0,dash+"linkV",OBJPROP_COLOR, linkCol);
   
   // Hedge Status 
   color statusCol = hedgeReadyForTrading ? clrLime : clrRed;
   string statusTxt = hedgeReadyForTrading ? "READY" : "BLOCKED";
   ObjectSetString (0,dash+"statusV",OBJPROP_TEXT, statusTxt);
   ObjectSetInteger(0,dash+"statusV",OBJPROP_COLOR, statusCol);

   // Bleed Status
   ObjectSetString (0,dash+"bleedV",OBJPROP_TEXT, bleedDone ? "Executed" : "Pending");
   ObjectSetInteger(0,dash+"bleedV",OBJPROP_COLOR, bleedDone ? clrLime : clrRed);
   
   // Update heartbeat time
   ObjectSetString(0,dash+"hbV",OBJPROP_TEXT, TimeToString(TimeCurrent(), TIME_SECONDS));
}

//+------------------------------------------------------------------+
//| Get hedge status description                                     |
//+------------------------------------------------------------------+
string GetHedgeStatusDescription()
{
   if(!EnableTrading)
      return "DISABLED (EnableTrading = false)";
   
   if(!mainEALinkEstablished)
      return "BLOCKED (Waiting for Main EA)";
   
   return "READY (Main EA connected)";
}


void DeleteDashboard(){ ObjectsDeleteAll(0,dash); }

//+------------------------------------------------------------------+
//| Publish hedge account metrics                                     |
//+------------------------------------------------------------------+
void PublishHedgeMetrics()
{
   string data = DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2) + "," +
                  DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2) + "," +
                  DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN_FREE), 2);

   int handle = FileOpen(HEDGE_DATA_FILE_PATH, FILE_WRITE|FILE_TXT|FILE_COMMON);
   if(handle != INVALID_HANDLE)
   {
      FileWriteString(handle, data);
      FileClose(handle);
   }
   else
   {
      LogError("Failed to write hedge metrics: " + IntegerToString(GetLastError()));
   }
}
