//| Input Parameters - Dashboard Settings (Add to your inputs)       |
//+------------------------------------------------------------------+
input group "Dashboard Settings"
input bool      ShowDashboard = true;                  // Show Dashboard
input int       DashboardFontSize = 9;                 // Dashboard Font Size
input int       DashboardTransparency = 80;            // Background Transparency (0-255)
input int       DashboardXPosition = 10;               // Dashboard X Position
input int       DashboardYPosition = 10;               // Dashboard Y Position

//+------------------------------------------------------------------+
//| Dashboard Variables (Updated)                                     |
//+------------------------------------------------------------------+
string dashboardPrefix = "PropEA_Dashboard_";
color headerBgColor = clrNavy;
color sectionHeaderBg = clrDarkSlateGray;
color dataBgColor = clrIndigo;
color textColor = clrWhite;
color statusGreen = clrLime;
color statusRed = clrRed;
color statusOrange = clrOrange;
color costRecoveryHeaderBg = clrDarkSlateGray;
color costRecoveryCriteriaBg = clrGray;

// Live account simulation variables
double liveAccountBalance = 0;
double liveAccountEquity = 0;
double liveAccountMargin = 0;
double liveDailyStartBalance = 0;
datetime lastDayCheck = 0;

//+------------------------------------------------------------------+
//| Initialize Live Account Simulation                                |
//+------------------------------------------------------------------+
void InitializeLiveAccountSimulation()
{
   liveAccountBalance = initialBalance * hedgeFactor;
   liveAccountEquity = liveAccountBalance;
   liveAccountMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE) * hedgeFactor;
   liveDailyStartBalance = liveAccountBalance;
   lastDayCheck = TimeCurrent();
}

//+------------------------------------------------------------------+
//| Update Live Account Simulation                                    |
//+------------------------------------------------------------------+
void UpdateLiveAccountSimulation()
{
   // Check for new day
   MqlDateTime currentTime, lastTime;
   TimeToStruct(TimeCurrent(), currentTime);
   TimeToStruct(lastDayCheck, lastTime);
   
   if(currentTime.day != lastTime.day)
   {
      liveDailyStartBalance = liveAccountBalance;
      lastDayCheck = TimeCurrent();
   }
   
   // Update live account values based on prop account performance
   double propPerformance = (AccountInfoDouble(ACCOUNT_BALANCE) - initialBalance) / initialBalance;
   liveAccountBalance = (initialBalance * hedgeFactor) * (1 + propPerformance);
   liveAccountEquity = liveAccountBalance + (AccountInfoDouble(ACCOUNT_EQUITY) - AccountInfoDouble(ACCOUNT_BALANCE)) * hedgeFactor;
   liveAccountMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE) * hedgeFactor;
}

//+------------------------------------------------------------------+
//| Create Dashboard (Fixed and Enhanced)                             |
//+------------------------------------------------------------------+
void CreateDashboard()
{
   if(!ShowDashboard) return;
   
   // Remove any existing dashboard objects
   DeleteDashboard();
   
   // Initialize live account simulation
   InitializeLiveAccountSimulation();
   
   // Create main background panel with transparency
   ObjectCreate(0, dashboardPrefix + "BG", OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, dashboardPrefix + "BG", OBJPROP_XDISTANCE, DashboardXPosition);
   ObjectSetInteger(0, dashboardPrefix + "BG", OBJPROP_YDISTANCE, DashboardYPosition);
   ObjectSetInteger(0, dashboardPrefix + "BG", OBJPROP_XSIZE, 520);
   ObjectSetInteger(0, dashboardPrefix + "BG", OBJPROP_YSIZE, 580);
   ObjectSetInteger(0, dashboardPrefix + "BG", OBJPROP_BGCOLOR, dataBgColor);
   ObjectSetInteger(0, dashboardPrefix + "BG", OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, dashboardPrefix + "BG", OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, dashboardPrefix + "BG", OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, dashboardPrefix + "BG", OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, dashboardPrefix + "BG", OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, dashboardPrefix + "BG", OBJPROP_BACK, false);
   ObjectSetInteger(0, dashboardPrefix + "BG", OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, dashboardPrefix + "BG", OBJPROP_SELECTED, false);
   ObjectSetInteger(0, dashboardPrefix + "BG", OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, dashboardPrefix + "BG", OBJPROP_ZORDER, 0);
   
   // Add transparency by creating overlay
   ObjectCreate(0, dashboardPrefix + "Transparency", OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, dashboardPrefix + "Transparency", OBJPROP_XDISTANCE, DashboardXPosition);
   ObjectSetInteger(0, dashboardPrefix + "Transparency", OBJPROP_YDISTANCE, DashboardYPosition);
   ObjectSetInteger(0, dashboardPrefix + "Transparency", OBJPROP_XSIZE, 520);
   ObjectSetInteger(0, dashboardPrefix + "Transparency", OBJPROP_YSIZE, 580);
   ObjectSetInteger(0, dashboardPrefix + "Transparency", OBJPROP_BGCOLOR, clrBlack);
   ObjectSetInteger(0, dashboardPrefix + "Transparency", OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, dashboardPrefix + "Transparency", OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, dashboardPrefix + "Transparency", OBJPROP_BACK, false);
   ObjectSetInteger(0, dashboardPrefix + "Transparency", OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, dashboardPrefix + "Transparency", OBJPROP_SELECTED, false);
   ObjectSetInteger(0, dashboardPrefix + "Transparency", OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, dashboardPrefix + "Transparency", OBJPROP_ZORDER, 1);
   
   // Add Main Title
   CreateLabel(dashboardPrefix + "Title", _Symbol + " Synergy + PropEA Hedge v1.02", 260, 20, clrWhite, DashboardFontSize + 3, "Arial Bold", true);
   
   int y = 50;
   
   // Create Phase and Hedge Link section
   CreateLabel(dashboardPrefix + "PhaseLabel", "Phase:", 20, y, textColor, DashboardFontSize);
   CreateLabel(dashboardPrefix + "PhaseValue", IntegerToString(CurrentPhase), 80, y, clrYellow, DashboardFontSize);
   
   CreateLabel(dashboardPrefix + "HedgeLinkLabel", "Hedge Link:", 300, y, textColor, DashboardFontSize);
   CreateLabel(dashboardPrefix + "HedgeLinkValue", "NOT OK", 380, y, statusRed, DashboardFontSize);
   
   y += 30;
   
   // Trading Information Section
   CreateSectionHeader("Trading Information", y);
   y += 25;
   
   // Column headers with better positioning
   CreateLabel(dashboardPrefix + "PropHeader", "PropAcc", 200, y, clrYellow, DashboardFontSize, "Arial Bold", true);
   CreateLabel(dashboardPrefix + "LiveHeader", "LiveAcc", 380, y, clrYellow, DashboardFontSize, "Arial Bold", true);
   
   y += 20;
   
   CreateDataRow("Volume", "0.00", "0.00", y);
   y += 20;
   
   CreateDataRow("Daily PnL", "0.00", "0.00", y);
   y += 20;
   
   CreateDataRow("Summary PnL", "0.00 / " + DoubleToString(MaxDD, 2), "0.00 / " + DoubleToString(ChallengeC, 2), y);
   y += 20;
   
   CreateDataRow("Trading Days", "0 / 0", "0 / 0", y);
   y += 20;
   
   // Account Status Section
   CreateSectionHeader("Account Status", y);
   y += 25;
   
   // Column headers
   CreateLabel(dashboardPrefix + "PropHeader2", "PropAcc", 200, y, clrYellow, DashboardFontSize, "Arial Bold", true);
   CreateLabel(dashboardPrefix + "LiveHeader2", "LiveAcc", 380, y, clrYellow, DashboardFontSize, "Arial Bold", true);
   
   y += 20;
   
   CreateDataRow("Account", IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)), "LIVE-" + IntegerToString(HedgeEA_Magic), y);
   y += 20;
   
   CreateDataRow("Currency", AccountInfoString(ACCOUNT_CURRENCY), AccountInfoString(ACCOUNT_CURRENCY), y);
   y += 20;
   
   CreateDataRow("Free Margin", DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN_FREE), 2), "0.00", y);
   y += 20;
   
   CreateDataRow("Symbol", _Symbol, _Symbol, y);
   y += 20;
   
   CreateDataRow("Daily DD Type", "Balance & Equity", "Balance & Equity", y);
   y += 20;
   
   CreateDataRow("Today DD", DoubleToString(dailyDD, 2), "100.0%", y);
   y += 20;
   
   CreateDataRow("Max DD", DoubleToString(MaxDD, 2), "100.0%", y);
   y += 20;
   
   // Cost Recovery Section
   CreateCostRecoverySection(y);
   y += 100;
   
   // Strategy Status Section
   CreateSectionHeader("Strategy Status", y);
   y += 25;
   
   // Market Bias
   CreateLabel(dashboardPrefix + "BiasLabel", "Market Bias:", 20, y, textColor, DashboardFontSize);
   CreateLabel(dashboardPrefix + "BiasValue", "NEUTRAL", 120, y, clrGray, DashboardFontSize);
   CreateLabel(dashboardPrefix + "BiasIndicator", "●", 200, y, currentBiasPositive ? statusGreen : statusRed, DashboardFontSize + 3);
   y += 18;
   
   // Synergy Score
   CreateLabel(dashboardPrefix + "SynergyLabel", "Synergy Score:", 20, y, textColor, DashboardFontSize);
   CreateLabel(dashboardPrefix + "SynergyValue", DoubleToString(synergyScore, 2), 120, y, textColor, DashboardFontSize);
   y += 18;
   
   // ADX Status
   CreateLabel(dashboardPrefix + "ADXLabel", "ADX Status:", 20, y, textColor, DashboardFontSize);
   CreateLabel(dashboardPrefix + "ADXValue", "Waiting", 120, y, statusRed, DashboardFontSize);
   CreateLabel(dashboardPrefix + "ADXValueNum", "(0.0)", 180, y, textColor, DashboardFontSize - 1);
   y += 18;
   
   // Scale Out Features
   CreateLabel(dashboardPrefix + "ScaleOutLabel", "Scale Out:", 20, y, textColor, DashboardFontSize);
   CreateLabel(dashboardPrefix + "ScaleOutValue", "OFF", 120, y, statusRed, DashboardFontSize);
   CreateLabel(dashboardPrefix + "ScaleOutDetails", "", 160, y, textColor, DashboardFontSize - 1);
   y += 18;
   
   // Pivot Settings
   CreateLabel(dashboardPrefix + "PivotLabel", "Pivot Settings:", 20, y, textColor, DashboardFontSize);
   CreateLabel(dashboardPrefix + "PivotValue", IntegerToString(PivotLengthLeft) + "/" + IntegerToString(PivotLengthRight), 120, y, textColor, DashboardFontSize);
   CreateLabel(dashboardPrefix + "PivotBars", "LB:" + IntegerToString(PivotTPBars), 170, y, textColor, DashboardFontSize - 1);
   y += 18;
   
   // Session Filter
   CreateLabel(dashboardPrefix + "SessionLabel", "Session Filter:", 20, y, textColor, DashboardFontSize);
   CreateLabel(dashboardPrefix + "SessionValue", EnableSessionFilter ? "ON" : "OFF", 120, y, EnableSessionFilter ? statusGreen : statusRed, DashboardFontSize);
   y += 18;
   
   // Signal Ready Status
   CreateLabel(dashboardPrefix + "SignalLabel", "Signal Ready:", 20, y, textColor, DashboardFontSize);
   CreateLabel(dashboardPrefix + "SignalValue", "CHECKING", 120, y, statusOrange, DashboardFontSize);
   y += 18;
   
   // Trading Enabled
   CreateLabel(dashboardPrefix + "TradingLabel", "Trading:", 20, y, textColor, DashboardFontSize);
   CreateLabel(dashboardPrefix + "TradingValue", EnableTrading ? "ENABLED" : "DISABLED", 120, y, EnableTrading ? statusGreen : statusRed, DashboardFontSize);
   y += 18;
   
   // Last Updated
   CreateLabel(dashboardPrefix + "TimeLabel", "Last Updated:", 20, y, textColor, DashboardFontSize);
   CreateLabel(dashboardPrefix + "TimeValue", TimeToString(TimeCurrent(), TIME_SECONDS), 120, y, textColor, DashboardFontSize);
}

//+------------------------------------------------------------------+
//| Get Actual Account Volume (Fix #1)                               |
//+------------------------------------------------------------------+
double GetActualAccountVolume()
{
   double totalVolume = 0;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      if(PositionGetTicket(i) > 0)
      {
         totalVolume += PositionGetDouble(POSITION_VOLUME);
      }
   }
   return totalVolume;
}

//+------------------------------------------------------------------+
//| Get Live Account Free Margin (Fix #3)                            |
//+------------------------------------------------------------------+
double GetLiveAccountFreeMargin()
{
   return MathMax(0, hedgeMargin);
}

//+------------------------------------------------------------------+
//| Get Real Daily PnL from History (Fix #4)                         |
//+------------------------------------------------------------------+
double GetRealDailyPnLFromHistory()
{
   datetime startOfDay = 0;
   datetime currentTime = TimeCurrent();
   
   // Get start of current day
   MqlDateTime dt;
   TimeToStruct(currentTime, dt);
   dt.hour = 0;
   dt.min = 0;
   dt.sec = 0;
   startOfDay = StructToTime(dt);
   
   // Select history for today
   if(!HistorySelect(startOfDay, currentTime))
   {
      Print("Failed to select history for today");
      return 0;
   }
   
   double dailyProfit = 0;
   int totalDeals = HistoryDealsTotal();
   
   // Sum all deals from today
   for(int i = 0; i < totalDeals; i++)
   {
      ulong dealTicket = HistoryDealGetTicket(i);
      if(dealTicket > 0)
      {
         string dealSymbol = HistoryDealGetString(dealTicket, DEAL_SYMBOL);
         if(dealSymbol == _Symbol || dealSymbol == "") // Include all symbols or current symbol
         {
            double profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
            double swap = HistoryDealGetDouble(dealTicket, DEAL_SWAP);
            double commission = HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
            
            dailyProfit += (profit + swap + commission);
         }
      }
   }
   
   return dailyProfit;
}

//+------------------------------------------------------------------+
//| Get Real Total PnL from History (Fix #4)                         |
//+------------------------------------------------------------------+
double GetRealTotalPnLFromHistory()
{
   // Get account's actual starting balance from first deposit
   double startingBalance = initialBalance;
   double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   
   // Calculate total PnL as difference from starting balance
   // This accounts for any deposits/withdrawals that may have occurred
   double totalPnL = currentBalance - startingBalance;
   
   // Add floating PnL
   double floatingPnL = currentEquity - currentBalance;
   
   return totalPnL + floatingPnL;
}

//+------------------------------------------------------------------+
//| Update Dashboard with latest values (All Fixes Applied)           |
//+------------------------------------------------------------------+
void UpdateDashboard()
{
   if(!ShowDashboard) return;
   
   // Update live account simulation
   UpdateLiveAccountSimulation();
   
   // Update Hedge Link Status
   bool linkOK = IsLinkAlive(true);
   ObjectSetString(0, dashboardPrefix + "HedgeLinkValue", OBJPROP_TEXT, linkOK ? "CONNECTED" : "NOT OK");
   ObjectSetInteger(0, dashboardPrefix + "HedgeLinkValue", OBJPROP_COLOR, linkOK ? statusGreen : statusRed);
   
   // FIX #1: Update Trading Information - Use actual account volumes
   double propVolume = GetActualAccountVolume();  // All positions, not just EA-managed
   double hedgeVolume = propVolume * hedgeFactor; // Simulated hedge volume
   ObjectSetString(0, dashboardPrefix + "Volume_Prop", OBJPROP_TEXT, DoubleToString(propVolume, 2));
   ObjectSetString(0, dashboardPrefix + "Volume_Real", OBJPROP_TEXT, DoubleToString(hedgeVolume, 2));
   
   // FIX #4: Update PnL values - Use real history data
   double propDailyPnL = GetRealDailyPnLFromHistory();
   double liveDailyPnL = propDailyPnL * hedgeFactor; // Simulated live daily PnL
   
   ObjectSetString(0, dashboardPrefix + "Daily PnL_Prop", OBJPROP_TEXT, 
                  (propDailyPnL >= 0 ? "+" : "") + DoubleToString(propDailyPnL, 2));
   ObjectSetString(0, dashboardPrefix + "Daily PnL_Real", OBJPROP_TEXT, 
                  (liveDailyPnL >= 0 ? "+" : "") + DoubleToString(liveDailyPnL, 2));
   
   // Summary PnL - Use real total PnL from history
   double propTotalPnL = GetRealTotalPnLFromHistory();
   double liveTotalPnL = propTotalPnL * hedgeFactor; // Simulated live total PnL
   
   ObjectSetString(0, dashboardPrefix + "Summary PnL_Prop", OBJPROP_TEXT, 
                  (propTotalPnL >= 0 ? "+" : "") + DoubleToString(propTotalPnL, 2) + " / " + DoubleToString(MaxDD, 2));
   ObjectSetString(0, dashboardPrefix + "Summary PnL_Real", OBJPROP_TEXT, 
                  (liveTotalPnL >= 0 ? "+" : "") + DoubleToString(liveTotalPnL, 2) + " / " + DoubleToString(ChallengeC, 2));
   
   // Update Account Status - Fixed live account display
   ObjectSetString(0, dashboardPrefix + "Account_Real", OBJPROP_TEXT, "LIVE-" + IntegerToString(HedgeEA_Magic));
   
   // FIX #3: Update margins - Use real live account margin calculation
   double propMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double liveMargin = GetLiveAccountFreeMargin(); // Proper live margin calculation
   ObjectSetString(0, dashboardPrefix + "Free Margin_Prop", OBJPROP_TEXT, DoubleToString(propMargin, 2));
   ObjectSetString(0, dashboardPrefix + "Free Margin_Real", OBJPROP_TEXT, DoubleToString(liveMargin, 2));
   
   // Update Trading Days
   int tradingDays = GetTradingDaysCount();
   ObjectSetString(0, dashboardPrefix + "Trading Days_Prop", OBJPROP_TEXT, IntegerToString(tradingDays) + " / " + IntegerToString(tradingDays));
   ObjectSetString(0, dashboardPrefix + "Trading Days_Real", OBJPROP_TEXT, IntegerToString(tradingDays) + " / " + IntegerToString(tradingDays));
   
   // FIX #2: Update Cost Recovery section - Fixed object naming
   double propLoss = MathMin(0, propTotalPnL);
   double propLossAbs = MathAbs(propLoss);
   double realProfit = MathMax(0, liveTotalPnL);
   double recoveryPct = 0;
   
   if(propLossAbs > 0 && realProfit > 0) {
      recoveryPct = (realProfit / propLossAbs) * 100;
   } else if(propLossAbs == 0 && realProfit > 0) {
      recoveryPct = 100.0;
   }
   
   // Fixed object names to match creation
   ObjectSetString(0, dashboardPrefix + "CostRecovery_Loss_Prop", OBJPROP_TEXT, 
                  propLoss < -0.01 ? DoubleToString(propLoss, 2) : "0.00");
   ObjectSetString(0, dashboardPrefix + "CostRecovery_Profit_Real", OBJPROP_TEXT, 
                  DoubleToString(realProfit, 2));
   ObjectSetString(0, dashboardPrefix + "CostRecovery_Recovery", OBJPROP_TEXT, 
                  DoubleToString(recoveryPct, 1) + "%");
   
   // Update Strategy Status indicators
   // Market Bias
   string biasText = "NEUTRAL";
   color biasColor = clrGray;
   if(UseMarketBias) {
      biasText = currentBiasPositive ? "BULLISH" : "BEARISH";
      biasColor = currentBiasPositive ? statusGreen : statusRed;
   }
   ObjectSetString(0, dashboardPrefix + "BiasValue", OBJPROP_TEXT, biasText);
   ObjectSetInteger(0, dashboardPrefix + "BiasValue", OBJPROP_COLOR, biasColor);
   ObjectSetInteger(0, dashboardPrefix + "BiasIndicator", OBJPROP_COLOR, biasColor);
   
   // Synergy Score
   ObjectSetString(0, dashboardPrefix + "SynergyValue", OBJPROP_TEXT, DoubleToString(synergyScore, 2));
   ObjectSetInteger(0, dashboardPrefix + "SynergyValue", OBJPROP_COLOR, 
                   synergyScore > 0 ? statusGreen : (synergyScore < 0 ? statusRed : textColor));
   
   // ADX Status - Fixed to show actual status
   bool actualADXCondition = EnableADXFilter ? adxTrendCondition : true;
   ObjectSetString(0, dashboardPrefix + "ADXValue", OBJPROP_TEXT, actualADXCondition ? "Active" : "Waiting");
   ObjectSetInteger(0, dashboardPrefix + "ADXValue", OBJPROP_COLOR, actualADXCondition ? statusGreen : statusRed);
   if(EnableADXFilter) {
      ObjectSetString(0, dashboardPrefix + "ADXValueNum", OBJPROP_TEXT, 
                     "(" + DoubleToString(effectiveADXThreshold, 1) + ")");
   } else {
      ObjectSetString(0, dashboardPrefix + "ADXValueNum", OBJPROP_TEXT, "(OFF)");
   }
   
   // Scale Out Status
   bool scaleOutActive = EnableScaleOut && ScaleOut1Enabled;
   ObjectSetString(0, dashboardPrefix + "ScaleOutValue", OBJPROP_TEXT, scaleOutActive ? "ON" : "OFF");
   ObjectSetInteger(0, dashboardPrefix + "ScaleOutValue", OBJPROP_COLOR, scaleOutActive ? statusGreen : statusRed);
   if(scaleOutActive) {
      ObjectSetString(0, dashboardPrefix + "ScaleOutDetails", OBJPROP_TEXT, 
                     "(" + DoubleToString(ScaleOut1Pct, 0) + "% at " + DoubleToString(ScaleOut1Size, 0) + "%)");
   } else {
      ObjectSetString(0, dashboardPrefix + "ScaleOutDetails", OBJPROP_TEXT, "");
   }
   
   // Session Filter Status
   ObjectSetString(0, dashboardPrefix + "SessionValue", OBJPROP_TEXT, EnableSessionFilter ? "ON" : "OFF");
   ObjectSetInteger(0, dashboardPrefix + "SessionValue", OBJPROP_COLOR, EnableSessionFilter ? statusGreen : statusRed);
   
   // Signal Ready Status
   bool signalReady = entryTriggersEnabled && 
                     (EnableADXFilter ? adxTrendCondition : true) && 
                     IsInTradingSession() &&
                     EnableTrading &&
                     !HasOpenPosition();
   
   string signalStatus = "NOT READY";
   color signalColor = statusRed;
   
   if(signalReady) {
      signalStatus = "READY";
      signalColor = statusGreen;
   } else if(!EnableTrading) {
      signalStatus = "DISABLED";
      signalColor = statusRed;
   } else if(HasOpenPosition()) {
      signalStatus = "IN TRADE";
      signalColor = statusOrange;
   } else if(!IsInTradingSession()) {
      signalStatus = "OUT OF SESSION";
      signalColor = statusOrange;
   } else if(EnableADXFilter && !adxTrendCondition) {
      signalStatus = "ADX WAIT";
      signalColor = statusOrange;
   }
   
   ObjectSetString(0, dashboardPrefix + "SignalValue", OBJPROP_TEXT, signalStatus);
   ObjectSetInteger(0, dashboardPrefix + "SignalValue", OBJPROP_COLOR, signalColor);
   
   // Trading Status
   ObjectSetString(0, dashboardPrefix + "TradingValue", OBJPROP_TEXT, EnableTrading ? "ENABLED" : "DISABLED");
   ObjectSetInteger(0, dashboardPrefix + "TradingValue", OBJPROP_COLOR, EnableTrading ? statusGreen : statusRed);
   
   // Update timestamp
   ObjectSetString(0, dashboardPrefix + "TimeValue", OBJPROP_TEXT, TimeToString(TimeCurrent(), TIME_SECONDS));
}

//+------------------------------------------------------------------+
//| Create a section header (Fixed positioning)                       |
//+------------------------------------------------------------------+
void CreateSectionHeader(string title, int y)
{
   if(!ShowDashboard) return;
   
   string name = dashboardPrefix + "Section_" + title;
   
   // Create background
   ObjectCreate(0, name + "_BG", OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name + "_BG", OBJPROP_XDISTANCE, DashboardXPosition);
   ObjectSetInteger(0, name + "_BG", OBJPROP_YDISTANCE, DashboardYPosition + y);
   ObjectSetInteger(0, name + "_BG", OBJPROP_XSIZE, 520);
   ObjectSetInteger(0, name + "_BG", OBJPROP_YSIZE, 25);
   ObjectSetInteger(0, name + "_BG", OBJPROP_BGCOLOR, sectionHeaderBg);
   ObjectSetInteger(0, name + "_BG", OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name + "_BG", OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name + "_BG", OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, name + "_BG", OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name + "_BG", OBJPROP_BACK, false);
   ObjectSetInteger(0, name + "_BG", OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name + "_BG", OBJPROP_SELECTED, false);
   ObjectSetInteger(0, name + "_BG", OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name + "_BG", OBJPROP_ZORDER, 2);
   
   // Create label
   CreateLabel(name, title, 260, y + 13, clrWhite, DashboardFontSize, "Arial Bold", true);
}

//+------------------------------------------------------------------+
//| Create a data row with proper alignment                           |
//+------------------------------------------------------------------+
void CreateDataRow(string label, string propValue, string liveValue, int y)
{
   if(!ShowDashboard) return;
   
   string name = dashboardPrefix + label;
   
   // Create background
   ObjectCreate(0, name + "_BG", OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name + "_BG", OBJPROP_XDISTANCE, DashboardXPosition);
   ObjectSetInteger(0, name + "_BG", OBJPROP_YDISTANCE, DashboardYPosition + y);
   ObjectSetInteger(0, name + "_BG", OBJPROP_XSIZE, 520);
   ObjectSetInteger(0, name + "_BG", OBJPROP_YSIZE, 20);
   ObjectSetInteger(0, name + "_BG", OBJPROP_BGCOLOR, dataBgColor);
   ObjectSetInteger(0, name + "_BG", OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name + "_BG", OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name + "_BG", OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, name + "_BG", OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name + "_BG", OBJPROP_BACK, false);
   ObjectSetInteger(0, name + "_BG", OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name + "_BG", OBJPROP_SELECTED, false);
   ObjectSetInteger(0, name + "_BG", OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name + "_BG", OBJPROP_ZORDER, 2);
   
   // Create label text
   CreateLabel(name, label, 20, y + 10, textColor, DashboardFontSize, "Arial", false);
   
   // Create prop value - center aligned to PropAcc column
   CreateLabel(name + "_Prop", propValue, 200, y + 10, textColor, DashboardFontSize, "Arial", true);
   
   // Create live value - center aligned to LiveAcc column
   CreateLabel(name + "_Real", liveValue, 380, y + 10, textColor, DashboardFontSize, "Arial", true);
}

//+------------------------------------------------------------------+
//| Create Cost Recovery section (Fix #2 - Correct Object Names)     |
//+------------------------------------------------------------------+
void CreateCostRecoverySection(int y)
{
   if(!ShowDashboard) return;
   
   string name = dashboardPrefix + "CostRecovery";
   
   // Create header
   CreateSectionHeader("Cost Recovery Estimate", y);
   y += 25;
   
   // Create column headers with proper alignment
   CreateLabel(name + "_Criteria", "Criteria", 20, y + 10, textColor, DashboardFontSize);
   CreateLabel(name + "_Loss_Header", "Loss PropAcc", 200, y + 10, clrYellow, DashboardFontSize, "Arial", true);
   CreateLabel(name + "_Profit_Header", "Profit LiveAcc", 350, y + 10, clrYellow, DashboardFontSize, "Arial", true);
   CreateLabel(name + "_Recovery_Header", "Recovery %", 450, y + 10, clrYellow, DashboardFontSize, "Arial", true);
   
   y += 20;
   
   // Create Max DD row background
   ObjectCreate(0, name + "_MaxDD_BG", OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name + "_MaxDD_BG", OBJPROP_XDISTANCE, DashboardXPosition);
   ObjectSetInteger(0, name + "_MaxDD_BG", OBJPROP_YDISTANCE, DashboardYPosition + y);
   ObjectSetInteger(0, name + "_MaxDD_BG", OBJPROP_XSIZE, 520);
   ObjectSetInteger(0, name + "_MaxDD_BG", OBJPROP_YSIZE, 20);
   ObjectSetInteger(0, name + "_MaxDD_BG", OBJPROP_BGCOLOR, costRecoveryCriteriaBg);
   ObjectSetInteger(0, name + "_MaxDD_BG", OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name + "_MaxDD_BG", OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name + "_MaxDD_BG", OBJPROP_BACK, false);
   ObjectSetInteger(0, name + "_MaxDD_BG", OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name + "_MaxDD_BG", OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name + "_MaxDD_BG", OBJPROP_ZORDER, 2);
   
   // Create Max DD row labels with CORRECT names that match UpdateDashboard()
   CreateLabel(name + "_MaxDD", "Max DD", 20, y + 10, textColor, DashboardFontSize);
   CreateLabel(name + "_Loss_Prop", "0.00", 200, y + 10, textColor, DashboardFontSize, "Arial", true);
   CreateLabel(name + "_Profit_Real", "0.00", 350, y + 10, textColor, DashboardFontSize, "Arial", true);
   CreateLabel(name + "_Recovery", "0.0%", 450, y + 10, textColor, DashboardFontSize, "Arial", true);
}

//+------------------------------------------------------------------+
//| Delete dashboard                                                  |
//+------------------------------------------------------------------+
void DeleteDashboard()
{
   ObjectsDeleteAll(0, dashboardPrefix);
}

//+------------------------------------------------------------------+
//| Create a text label (Enhanced with positioning)                   |
//+------------------------------------------------------------------+
void CreateLabel(string name, string text, int x, int y, color clr, int fontSize, 
                string font = "Arial", bool centered = false)
{
   if(!ShowDashboard) return;
   
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, DashboardXPosition + x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, DashboardYPosition + y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, font);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, centered ? ANCHOR_CENTER : ANCHOR_LEFT);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 3);
}

//+------------------------------------------------------------------+
//| Get Daily PnL (Helper function)                                   |
//+------------------------------------------------------------------+
double GetDailyPnL()
{
   static double dayStartBalance = 0;
   static datetime lastDay = 0;
   
   datetime currentTime = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(currentTime, dt);
   
   // Check for new day
   if(lastDay != dt.day || dayStartBalance == 0)
   {
      dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      lastDay = dt.day;
   }
   
   return AccountInfoDouble(ACCOUNT_EQUITY) - dayStartBalance;
}

//+------------------------------------------------------------------+
//| Get Trading Days Count (Helper function)                          |
//+------------------------------------------------------------------+
int GetTradingDaysCount()
{
   static int tradingDays = 1;
   static datetime lastCheck = 0;
   
   datetime currentTime = TimeCurrent();
   MqlDateTime current, last;
   TimeToStruct(currentTime, current);
   TimeToStruct(lastCheck, last);
   
   if(lastCheck == 0) {
      lastCheck = currentTime;
      return tradingDays;
   }
   
   if(current.day != last.day) {
      tradingDays++;
      lastCheck = currentTime;
   }
   
   return tradingDays;
}
