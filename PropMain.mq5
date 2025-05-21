//+------------------------------------------------------------------+
//| Fixed bar confirmation function for true bar close               |
//+------------------------------------------------------------------+

// --- Placeholder global variables to allow successful compilation ---
double   Open[], High[], Low[], Close[];
datetime TimeSeries[];
int      BARS_REQUIRED      = 100;
bool     ShowPivotLines     = true;
bool     ShowMarketBias     = true;
double   synergyScore       = 0.0;
bool     currentBiasPositive = false;
bool     biasChangedToBullish = false;
bool     biasChangedToBearish = false;
bool     adxTrendCondition  = false;
double   effectiveADXThreshold = 0.0;
double   pivotStopLongEntry  = 0.0,
         pivotTpLongEntry    = 0.0,
         pivotStopShortEntry = 0.0,
         pivotTpShortEntry   = 0.0;

// Forward declarations for helper functions used later in the file
bool   IsNewBar();
bool   IsInTradingSession();
bool   HasOpenPosition();
void   UpdateDashboard();
void   DrawPivotLines();
void   DrawDetectedPivotLines();
void   ShowMarketBiasIndicator();
void   ManageOpenPositions();
void   OpenTrade(bool isBuy,double sl,double tp);
void   TryAlternativeSignalMethod(string data);
string GetErrorDescription(int code);
double FindDeepestPivotLowBelowClose(int lookbackBars);
double FindHighestPivotHighAboveClose(int lookbackBars);
void   CalculateSynergyScore();
void   CalculateMarketBias();
void   CalculateADXFilter();
void   CheckBleedCondition();
bool IsConfirmedBar()
{
   static datetime lastBarTime = 0;
   datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   
   // Check if we have enough history
   if(ArraySize(TimeSeries) < 2)
      return false;
   
   // Method 1: Check if we're in a new bar (just after previous bar closed)
   if(lastBarTime != currentBarTime)
   {
      lastBarTime = currentBarTime;
      // We're at the start of a new bar, so previous bar is confirmed closed
      Print("DEBUG: New bar detected at ", TimeToString(currentBarTime), " - previous bar confirmed closed");
      return true;
   }
   
   // Method 2: Alternative - check if current bar is near close (last 10 seconds)
   datetime nextBarTime = currentBarTime + PeriodSeconds();
   int secondsUntilClose = (int)(nextBarTime - TimeCurrent());
   
   if(secondsUntilClose <= 10) // Last 10 seconds of current bar
   {
      static datetime lastNearCloseWarning = 0;
      if(TimeCurrent() - lastNearCloseWarning > 30)
      {
         Print("DEBUG: Near bar close - ", secondsUntilClose, " seconds until next bar");
         lastNearCloseWarning = TimeCurrent();
      }
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Enhanced OnTick with strict bar close requirement                |
//+------------------------------------------------------------------+
void OnTick()
{
   // === DEBUGGING SECTION START ===
   static int debugCounter = 0;
   static datetime lastDebugTime = 0;
   debugCounter++;
   
   // Print basic status every 50 ticks or every 30 seconds
   if(debugCounter % 50 == 0 || TimeCurrent() - lastDebugTime > 30) {
      Print("=== BASIC STATUS CHECK #", debugCounter, " ===");
      Print("Time: ", TimeToString(TimeCurrent()));
      Print("EnableTrading: ", EnableTrading);
      Print("IsMarketOpen: ", IsMarketOpen());
      Print("Bars Available: ", Bars(_Symbol,PERIOD_CURRENT), " / Required: ", BARS_REQUIRED);
      Print("Has Open Position: ", HasOpenPosition());
      lastDebugTime = TimeCurrent();
   }
   
   // 0) global guards with detailed logging
   if(!EnableTrading) {
      if(debugCounter % 100 == 0) Print("DEBUG: Trading disabled");
      return;
   }
   if(!IsMarketOpen()) {
      if(debugCounter % 100 == 0) Print("DEBUG: Market closed");
      return;
   }
   if(Bars(_Symbol,PERIOD_CURRENT)<BARS_REQUIRED) {
      if(debugCounter % 100 == 0) Print("DEBUG: Insufficient bars - Available: ", Bars(_Symbol,PERIOD_CURRENT), " Required: ", BARS_REQUIRED);
      return;
   }

   // 1) update dashboard & visuals every tick
   UpdateDashboard();
   if(ShowPivotLines)  DrawPivotLines();
   if(ShowMarketBias)  ShowMarketBiasIndicator();

   // 2) CHECK FOR NEW BAR - CRITICAL FOR BAR CLOSE TRADING
   if(!IsNewBar()) return;
   
   // 3) WAIT FOR BAR CONFIRMATION - ONLY TRADE ON BAR CLOSE
   if(!IsConfirmedBar())
   {
      static datetime lastBarWait = 0;
      if(TimeCurrent() - lastBarWait > 30)
      {
         Print("DEBUG: Waiting for bar close confirmation...");
         lastBarWait = TimeCurrent();
      }
      return;
   }

   Print("====================================================");
   Print("=== BAR CLOSE ANALYSIS - ", TimeToString(TimeCurrent()), " ===");
   Print("====================================================");
   
   // 4) pull fresh history with detailed logging
   int needBars = MathMax(PivotTPBars + PivotLengthLeft + PivotLengthRight + 5 , 100);
   Print("DEBUG: Need ", needBars, " bars for analysis");
   
   if(CopyClose(_Symbol,PERIOD_CURRENT,0,needBars,Close) < needBars) {
      Print("ERROR: Failed to copy Close prices - got ", ArraySize(Close), " need ", needBars);
      return;
   }
   if(CopyOpen(_Symbol,PERIOD_CURRENT,0,needBars,Open) < needBars) {
      Print("ERROR: Failed to copy Open prices");
      return;
   }
   if(CopyHigh(_Symbol,PERIOD_CURRENT,0,needBars,High) < needBars) {
      Print("ERROR: Failed to copy High prices");
      return;
   }
   if(CopyLow(_Symbol,PERIOD_CURRENT,0,needBars,Low) < needBars) {
      Print("ERROR: Failed to copy Low prices");
      return;
   }
   if(CopyTime(_Symbol,PERIOD_CURRENT,0,needBars,TimeSeries) < needBars) {
      Print("ERROR: Failed to copy Time series");
      return;
   }
   Print("DEBUG: Successfully copied price data - Arrays size: ", ArraySize(Close));

   // 5) session filter with logging
   bool sessionAllowed = IsInTradingSession();
   Print("DEBUG: Trading Session Check: ", sessionAllowed ? "IN SESSION" : "OUT OF SESSION");
   if(!sessionAllowed) {
      Print("DEBUG: Outside trading session - exiting");
      return;
   }

   // 6) refresh indicators ONLY ON BAR CLOSE
   Print("--- INDICATOR CALCULATIONS (BAR CLOSE) ---");
   double oldSynergyScore = synergyScore;
   bool oldBiasPositive = currentBiasPositive;
   bool oldBiasChangedToBullish = biasChangedToBullish;
   bool oldBiasChangedToBearish = biasChangedToBearish;
   bool oldAdxCondition = adxTrendCondition;
   
   CalculateSynergyScore();
   CalculateMarketBias();
   CalculateADXFilter();
   
   Print("SYNERGY SCORE: ", DoubleToString(synergyScore, 3), " (was: ", DoubleToString(oldSynergyScore, 3), ") - Enabled: ", UseSynergyScore);
   Print("MARKET BIAS: Current=", currentBiasPositive ? "BULLISH" : "BEARISH", " (was: ", oldBiasPositive ? "BULLISH" : "BEARISH", ") - Enabled: ", UseMarketBias);
   Print("BIAS CHANGES: ToBullish=", biasChangedToBullish, " (was: ", oldBiasChangedToBullish, "), ToBearish=", biasChangedToBearish, " (was: ", oldBiasChangedToBearish, ")");
   Print("ADX TREND: ", adxTrendCondition ? "TRUE" : "FALSE", " (was: ", oldAdxCondition ? "TRUE" : "FALSE", ") - Enabled: ", EnableADXFilter);
   if(EnableADXFilter) Print("ADX Threshold: ", DoubleToString(effectiveADXThreshold, 2));

   // 7) derive swing-pivots with detailed logging and selection criteria
   Print("--- PIVOT CALCULATION ---");
   Print("Pivot Selection Criteria:");
   Print("  LONG SL  = DEEPEST pivot low BELOW current price (within ", PivotTPBars, " bars)");
   Print("  LONG TP  = HIGHEST pivot high ABOVE current price (within ", PivotTPBars, " bars)");
   Print("  SHORT SL = HIGHEST pivot high ABOVE current price (within ", PivotTPBars, " bars)");
   Print("  SHORT TP = DEEPEST pivot low BELOW current price (within ", PivotTPBars, " bars)");
   
   double slLong  = FindDeepestPivotLowBelowClose(PivotTPBars);   // Deepest (lowest) pivot low below price
   double tpLong  = FindHighestPivotHighAboveClose(PivotTPBars);  // Highest pivot high above price
   double slShort = FindHighestPivotHighAboveClose(PivotTPBars);  // Highest pivot high above price  
   double tpShort = FindDeepestPivotLowBelowClose(PivotTPBars);   // Deepest (lowest) pivot low below price

   Print("Current Price: ", DoubleToString(Close[0], 5));
   Print("SELECTED PIVOTS:");
   Print("  LONG  - SL: ", DoubleToString(slLong, 5), " (DEEPEST low below, valid: ", (slLong > 0 && slLong < Close[0]) ? "YES" : "NO", ")");
   Print("  LONG  - TP: ", DoubleToString(tpLong, 5), " (HIGHEST high above, valid: ", (tpLong > 0 && tpLong > Close[0]) ? "YES" : "NO", ")");
   Print("  SHORT - SL: ", DoubleToString(slShort, 5), " (HIGHEST high above, valid: ", (slShort > 0 && slShort > Close[0]) ? "YES" : "NO", ")");
   Print("  SHORT - TP: ", DoubleToString(tpShort, 5), " (DEEPEST low below, valid: ", (tpShort > 0 && tpShort < Close[0]) ? "YES" : "NO", ")");

   // NO FALLBACK - Strategy requires valid pivot points only
   bool hasValidLongPivots = (slLong > 0 && slLong < Close[0] && tpLong > 0 && tpLong > Close[0]);
   bool hasValidShortPivots = (slShort > 0 && slShort > Close[0] && tpShort > 0 && tpShort < Close[0]);
   
   if(!hasValidLongPivots && !hasValidShortPivots)
   {
      Print("DEBUG: No valid pivot combinations found - NO TRADE (Strategy requires strict pivot SL/TP)");
   }
   else if(!hasValidLongPivots)
   {
      Print("DEBUG: No valid LONG pivot combination (SL:", DoubleToString(slLong,5), " TP:", DoubleToString(tpLong,5), ")");
   }
   else if(!hasValidShortPivots)
   {
      Print("DEBUG: No valid SHORT pivot combination (SL:", DoubleToString(slShort,5), " TP:", DoubleToString(tpShort,5), ")");
   }

   // Draw pivot lines on chart
   DrawDetectedPivotLines();

   if(slLong  >0) pivotStopLongEntry  = slLong;
   if(tpLong  >0) pivotTpLongEntry    = tpLong;
   if(slShort >0) pivotStopShortEntry = slShort;
   if(tpShort >0) pivotTpShortEntry   = tpShort;

   // 8) build entry conditions with detailed breakdown
   Print("--- ENTRY CONDITIONS ANALYSIS ---");
   
   // Common conditions
   bool confirmedBar = true; // We already checked this above
   bool hasPosition = HasOpenPosition();
   bool inSessionCheck2 = IsInTradingSession(); // Double check
   
   Print("COMMON CONDITIONS:");
   Print("  ✓ Bar Close Confirmed: TRUE");
   Print("  ✓ Entry Triggers Enabled: ", entryTriggersEnabled ? "TRUE" : "FALSE");
   Print("  ✓ ADX Trend Condition: ", adxTrendCondition ? "TRUE" : "FALSE");
   Print("  ✓ In Trading Session: ", inSessionCheck2 ? "TRUE" : "FALSE");
   Print("  ✓ No Open Position: ", !hasPosition ? "TRUE" : "FALSE");
   
   // Long conditions breakdown
   bool longSynergyOK = UseSynergyScore ? synergyScore>0 : true;
   bool longBiasOK = UseMarketBias ? biasChangedToBullish : true; // Keep original logic as requested
   bool longPivotSLOK = slLong > 0 && slLong < Close[0];
   bool longPivotTPOK = tpLong > 0 && tpLong > Close[0];
   
   Print("LONG CONDITIONS:");
   Print("  ✓ Synergy OK: ", longSynergyOK ? "TRUE" : "FALSE", " (Score: ", DoubleToString(synergyScore, 3), ", Required: >0, Enabled: ", UseSynergyScore, ")");
   Print("  ✓ Bias OK: ", longBiasOK ? "TRUE" : "FALSE", " (ChangedToBullish: ", biasChangedToBullish, ", Enabled: ", UseMarketBias, ")");
   Print("  ✓ Pivot SL OK: ", longPivotSLOK ? "TRUE" : "FALSE", " (", DoubleToString(slLong, 5), " < ", DoubleToString(Close[0], 5), ")");
   Print("  ✓ Pivot TP OK: ", longPivotTPOK ? "TRUE" : "FALSE", " (", DoubleToString(tpLong, 5), " > ", DoubleToString(Close[0], 5), ")");

   bool longCond = confirmedBar && entryTriggersEnabled && adxTrendCondition && 
                   longSynergyOK && longBiasOK && longPivotSLOK && longPivotTPOK && 
                   inSessionCheck2 && !hasPosition;
   
   // Short conditions breakdown
   bool shortSynergyOK = UseSynergyScore ? synergyScore<0 : true;
   bool shortBiasOK = UseMarketBias ? biasChangedToBearish : true; // Keep original logic as requested
   bool shortPivotSLOK = slShort > 0 && slShort > Close[0];
   bool shortPivotTPOK = tpShort > 0 && tpShort < Close[0];
   
   Print("SHORT CONDITIONS:");
   Print("  ✓ Synergy OK: ", shortSynergyOK ? "TRUE" : "FALSE", " (Score: ", DoubleToString(synergyScore, 3), ", Required: <0, Enabled: ", UseSynergyScore, ")");
   Print("  ✓ Bias OK: ", shortBiasOK ? "TRUE" : "FALSE", " (ChangedToBearish: ", biasChangedToBearish, ", Enabled: ", UseMarketBias, ")");
   Print("  ✓ Pivot SL OK: ", shortPivotSLOK ? "TRUE" : "FALSE", " (", DoubleToString(slShort, 5), " > ", DoubleToString(Close[0], 5), ")");
   Print("  ✓ Pivot TP OK: ", shortPivotTPOK ? "TRUE" : "FALSE", " (", DoubleToString(tpShort, 5), " < ", DoubleToString(Close[0], 5), ")");

   bool shortCond = confirmedBar && entryTriggersEnabled && adxTrendCondition && 
                    shortSynergyOK && shortBiasOK && shortPivotSLOK && shortPivotTPOK && 
                    inSessionCheck2 && !hasPosition;

   Print("--- FINAL RESULTS ---");
   Print("LONG CONDITION RESULT: ", longCond ? "✓ TRUE - TRADE SIGNAL!" : "✗ FALSE");
   Print("SHORT CONDITION RESULT: ", shortCond ? "✓ TRUE - TRADE SIGNAL!" : "✗ FALSE");
   
   if(!longCond && !shortCond) {
      Print("❌ NO TRADE SIGNALS - Check failed conditions above");
      
      // Identify the most likely blockers
      if(!entryTriggersEnabled) Print("🚫 BLOCKER: Entry triggers disabled");
      if(!adxTrendCondition && EnableADXFilter) Print("🚫 BLOCKER: ADX condition failed");
      if(hasPosition) Print("🚫 BLOCKER: Position already open");
      if(!inSessionCheck2) Print("🚫 BLOCKER: Outside trading session");
      if(UseMarketBias && !biasChangedToBullish && !biasChangedToBearish) Print("🚫 BLOCKER: Market bias not changing (waiting for bias shift)");
      if(!hasValidLongPivots && !hasValidShortPivots) Print("🚫 BLOCKER: No valid pivot SL/TP combinations found (strict pivot strategy)");
   }

   // 9) execute with enhanced logging - ONLY ON BAR CLOSE
   if(longCond && !HasOpenPosition()) {
      Print("🚀 EXECUTING LONG TRADE ON BAR CLOSE!");
      Print("   Entry Price: ~", DoubleToString(Close[0], 5));
      Print("   Stop Loss: ", DoubleToString(slLong, 5));
      Print("   Take Profit: ", DoubleToString(tpLong, 5));
      Print("   Using Fallback Levels: NO - Strict pivot strategy");
      OpenTrade(true, slLong, tpLong);
   }
   if(shortCond && !HasOpenPosition()) {
      Print("🚀 EXECUTING SHORT TRADE ON BAR CLOSE!");
      Print("   Entry Price: ~", DoubleToString(Close[0], 5));
      Print("   Stop Loss: ", DoubleToString(slShort, 5));
      Print("   Take Profit: ", DoubleToString(tpShort, 5));
      Print("   Using Fallback Levels: NO - Strict pivot strategy");
      OpenTrade(false, slShort, tpShort);
   }

   // 10) manage & bleed
   ManageOpenPositions();
   CheckBleedCondition();
   
   Print("====================================================");
}

//+------------------------------------------------------------------+
//| Fixed SendHedgeSignal with correct SL/TP for hedge direction     |
//+------------------------------------------------------------------+
void SendHedgeSignal(string signalType, string direction, double volume, double tp, double sl)
{
   if(!EnableHedgeCommunication) 
   {
      Print("DEBUG: SendHedgeSignal called but communication disabled");
      return;
   }
   
   // CRITICAL FIX: Adjust SL/TP for hedge direction
   double adjustedSL = sl;
   double adjustedTP = tp;
   
   if(signalType == "OPEN")
   {
      double currentPrice = Close[0];
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      
      Print("=== HEDGE SIGNAL ADJUSTMENT ===");
      Print("Main trade SL: ", DoubleToString(sl, 5), " TP: ", DoubleToString(tp, 5));
      Print("Current Ask: ", DoubleToString(ask, 5), " Bid: ", DoubleToString(bid, 5));
      Print("Hedge Direction: ", direction);
      
      if(direction == "SELL") // Hedge for LONG main trade
      {
         // For hedge SELL: SL should be above entry, TP should be below entry
         // We need to ensure SL > current price and TP < current price
         if(sl < bid) // Original SL is below current price (from LONG trade)
         {
            // Swap: Use main TP as hedge SL, main SL as hedge TP
            adjustedSL = tp;  // Main TP becomes hedge SL (above price)
            adjustedTP = sl;  // Main SL becomes hedge TP (below price)
            Print("🔄 HEDGE SELL: Swapped SL/TP");
            Print("   Adjusted SL: ", DoubleToString(adjustedSL, 5), " (was TP)");
            Print("   Adjusted TP: ", DoubleToString(adjustedTP, 5), " (was SL)");
         }
      }
      else if(direction == "BUY") // Hedge for SHORT main trade
      {
         // For hedge BUY: SL should be below entry, TP should be above entry
         if(sl > ask) // Original SL is above current price (from SHORT trade)
         {
            // Swap: Use main TP as hedge SL, main SL as hedge TP
            adjustedSL = tp;  // Main TP becomes hedge SL (below price)
            adjustedTP = sl;  // Main SL becomes hedge TP (above price)
            Print("🔄 HEDGE BUY: Swapped SL/TP");
            Print("   Adjusted SL: ", DoubleToString(adjustedSL, 5), " (was TP)");
            Print("   Adjusted TP: ", DoubleToString(adjustedTP, 5), " (was SL)");
         }
      }
   }
   
   if(CommunicationMethod == GLOBAL_VARS)
   {
      // Original global variable code
      string magicStr = IntegerToString(HedgeEA_Magic);
      GlobalVariableSet("EASignal_Type_" + magicStr, (double)StringGetTickCount(signalType));
      GlobalVariableSet("EASignal_Direction_" + magicStr, (double)StringGetTickCount(direction));
      GlobalVariableSet("EASignal_Volume_" + magicStr, volume);
      GlobalVariableSet("EASignal_SL_" + magicStr, adjustedSL);
      GlobalVariableSet("EASignal_TP_" + magicStr, adjustedTP);
      GlobalVariableSet("EASignal_Time_" + magicStr, (double)TimeCurrent());
      
      Print("✅ Signal sent via GLOBAL_VARS: ", signalType, " ", direction, " ", 
            DoubleToString(volume, 2), " lots, TP: ", DoubleToString(adjustedTP, 5), 
            ", SL: ", DoubleToString(adjustedSL, 5));
   }
   else // FILE_BASED
   {
      // Create a signal string with ADJUSTED parameters
      string signalData = signalType + "," + 
                        direction + "," + 
                        DoubleToString(volume, 2) + "," + 
                        DoubleToString(adjustedTP, 5) + "," + 
                        DoubleToString(adjustedSL, 5) + "," + 
                        IntegerToString(Magic_Number) + "," +
                        IntegerToString(TimeCurrent());
      
      Print("📤 SENDING FILE SIGNAL: ", signalData);
      Print("   File path: ", COMM_FILE_PATH);
      
      // Force close any potentially open handles first
      CleanupFileHandles();
      
      // Try to write the signal file with retries
      bool success = false;
      for(int attempt = 1; attempt <= FILE_WRITE_RETRY && !success; attempt++)
      {
         Print("   Attempt ", attempt, " of ", FILE_WRITE_RETRY);
         
         // Reset last error before attempting
         ResetLastError();
         
         int fileHandle = INVALID_HANDLE;
         
         // Use appropriate flags based on which path we're using
         bool useFileCommon = (StringFind(COMM_FILE_PATH, "Common") >= 0);
         fileHandle = useFileCommon ? 
                     FileOpen(COMM_FILE_PATH, FILE_WRITE|FILE_TXT|FILE_COMMON) :
                     FileOpen(COMM_FILE_PATH, FILE_WRITE|FILE_TXT);
         
         if(fileHandle != INVALID_HANDLE)
         {
            // Successfully opened file
            int writeResult = FileWriteString(fileHandle, signalData);
            FileFlush(fileHandle);  // Force write to disk
            FileClose(fileHandle);  // Always close immediately
            fileHandle = INVALID_HANDLE; // Mark as closed
            
            if(writeResult > 0)
            {
               success = true;
               Print("✅ Signal sent to hedge EA via file successfully!");
               Print("   Signal: ", signalType, " ", direction, " ", DoubleToString(volume, 2), " lots");
               Print("   Adjusted TP: ", DoubleToString(adjustedTP, 5), " SL: ", DoubleToString(adjustedSL, 5));
               Print("   Bytes written: ", writeResult);
            }
            else
            {
               int writeError = GetLastError();
               Print("❌ File write failed. Error: ", writeError, " (", GetErrorDescription(writeError), ")");
            }
         }
         else
         {
            int errorCode = GetLastError();
            Print("❌ File open attempt ", attempt, " failed. Error: ", errorCode, " (", GetErrorDescription(errorCode), ")");
            Print("   Path: ", COMM_FILE_PATH);
            
            if(attempt < FILE_WRITE_RETRY)
            {
               Print("   Waiting 200ms before retry...");
               Sleep(200); // Increased wait time
               CleanupFileHandles(); // Clean up before retry
            }
         }
      }
      
      if(!success)
      {
         Print("💥 CRITICAL ERROR: Failed to send signal to hedge EA after ", 
               IntegerToString(FILE_WRITE_RETRY), " attempts!");
         Print("   Signal data: ", signalData);
         Print("   File path: ", COMM_FILE_PATH);
         
         // Try alternative method as last resort
         TryAlternativeSignalMethod(signalData);
      }
   }
}

// -----------------------------------------------------------------
// Stub implementations for missing helper functions
// -----------------------------------------------------------------

bool IsNewBar()
{
   static datetime lastBar = 0;
   datetime cur = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(cur!=lastBar){ lastBar=cur; return true; }
   return false;
}

bool IsInTradingSession()
{
   return true;
}

bool HasOpenPosition()
{
   return false;
}

void UpdateDashboard(){}

void DrawPivotLines(){}

void DrawDetectedPivotLines(){ DrawPivotLines(); }

void ShowMarketBiasIndicator(){}

void ManageOpenPositions(){}

void OpenTrade(bool isBuy,double sl,double tp)
{
   Print("[Stub] OpenTrade called: ", isBuy ? "BUY" : "SELL", " SL:", sl, " TP:", tp);
}

void TryAlternativeSignalMethod(string data)
{
   Print("[Stub] TryAlternativeSignalMethod: ", data);
}

string GetErrorDescription(int code)
{
   return IntegerToString(code);
}

double FindDeepestPivotLowBelowClose(int lookbackBars)
{
   return 0.0;
}

double FindHighestPivotHighAboveClose(int lookbackBars)
{
   return 0.0;
}

void CalculateSynergyScore(){}

void CalculateMarketBias(){}

void CalculateADXFilter(){}

void CheckBleedCondition(){}

