#property copyright "t2an1s"
#property version   "1.00"
#property strict

//+------------------------------------------------------------------+
//| Input Parameters - Dashboard Settings                            |
//+------------------------------------------------------------------+
input group "Dashboard Settings"
input bool      ShowDashboard = true;                  // Show Dashboard
input int       DashboardFontSize = 9;                 // Dashboard Font Size
input int       DashboardTransparency = 80;            // Background Transparency (0-255)
input int       DashboardXPosition = 10;               // Dashboard X Position
input int       DashboardYPosition = 10;               // Dashboard Y Position

//+------------------------------------------------------------------+
//| Dashboard Variables                                              |
//+------------------------------------------------------------------+
string dashboardPrefix = "PropEA_Dashboard_";
color headerBgColor       = clrNavy;
color sectionHeaderBg     = clrDarkSlateGray;
color dataBgColor         = clrIndigo;
color textColor           = clrWhite;
color statusGreen         = clrLime;
color statusRed           = clrRed;
color statusOrange        = clrOrange;
color costRecoveryHeaderBg   = clrDarkSlateGray;
color costRecoveryCriteriaBg = clrGray;

// Live account simulation variables
double liveAccountBalance    = 0;
double liveAccountEquity     = 0;
double liveAccountMargin     = 0;
double liveDailyStartBalance = 0;
datetime lastDayCheck        = 0;

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
   MqlDateTime currentTime, lastTime;
   TimeToStruct(TimeCurrent(), currentTime);
   TimeToStruct(lastDayCheck, lastTime);
   if(currentTime.day != lastTime.day)
   {
      liveDailyStartBalance = liveAccountBalance;
      lastDayCheck = TimeCurrent();
   }
   double propPerformance = (AccountInfoDouble(ACCOUNT_BALANCE) - initialBalance) / initialBalance;
   liveAccountBalance = (initialBalance * hedgeFactor) * (1 + propPerformance);
   liveAccountEquity = liveAccountBalance + (AccountInfoDouble(ACCOUNT_EQUITY) - AccountInfoDouble(ACCOUNT_BALANCE)) * hedgeFactor;
   liveAccountMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE) * hedgeFactor;
}

input string PropDataFile = "PropDashData.txt";
input string HedgeDataFile = "HedgeData.txt";

string PROP_DATA_PATH;
string HEDGE_DATA_PATH;

// metrics from PropMain
double synergyScore = 0;
bool   currentBiasPositive = false;
bool   adxTrendCondition = false;
double effectiveADXThreshold = 0;
bool   entryTriggersEnabled = false;
double hedgeFactor = 0;
double initialBalance = 0;
double MaxDD = 0;
double ChallengeC = 0;
bool   EnableTrading = true;
bool   EnableSessionFilter = true;
bool   EnableADXFilter = true;
bool   EnableScaleOut = true;
bool   ScaleOut1Enabled = true;
double ScaleOut1Pct = 0;
double ScaleOut1Size = 0;
bool   ScaleOut1BE = false;
int     PivotLengthLeft = 0;
int     PivotLengthRight = 0;
int     PivotTPBars = 0;
int     HedgeEA_Magic = 0;

// hedge account metrics
double hedgeBalance = 0;
double hedgeEquity = 0;
double hedgeMargin = 0;

// heartbeat path for link check
string HEDGE_HEARTBEAT_FILE_PATH;
const int LINK_TIMEOUT_SEC = 15;
bool EnableHedgeCommunication = true;

bool ReadPropData()
{
   if(!FileIsExist(PROP_DATA_PATH, FILE_COMMON))
      return false;
   int h = FileOpen(PROP_DATA_PATH, FILE_READ|FILE_TXT|FILE_COMMON);
   if(h==INVALID_HANDLE)
      return false;
   string line = FileReadString(h);
   FileClose(h);
   string parts[];
   int n = StringSplit(line, ',', parts);
   if(n>=6)
   {
      synergyScore = StringToDouble(parts[0]);
      currentBiasPositive = (StringToInteger(parts[1])==1);
      adxTrendCondition = (StringToInteger(parts[2])==1);
      effectiveADXThreshold = StringToDouble(parts[3]);
      entryTriggersEnabled = (StringToInteger(parts[4])==1);
      hedgeFactor = StringToDouble(parts[5]);
      return true;
   }
   return false;
}

bool ReadHedgeData()
{
   if(!FileIsExist(HEDGE_DATA_PATH, FILE_COMMON))
      return false;
   int h = FileOpen(HEDGE_DATA_PATH, FILE_READ|FILE_TXT|FILE_COMMON);
   if(h==INVALID_HANDLE)
      return false;
   string line = FileReadString(h);
   FileClose(h);
   string parts[];
   int n = StringSplit(line, ',', parts);
   if(n>=3)
   {
      hedgeBalance = StringToDouble(parts[0]);
      hedgeEquity = StringToDouble(parts[1]);
      hedgeMargin = StringToDouble(parts[2]);
      return true;
   }
   return false;
}

bool IsLinkAlive(bool dummy)
{
   if(!EnableHedgeCommunication) return false;
   if(!FileIsExist(HEDGE_HEARTBEAT_FILE_PATH, FILE_COMMON))
      return false;
   int h = FileOpen(HEDGE_HEARTBEAT_FILE_PATH, FILE_READ|FILE_TXT|FILE_COMMON);
   if(h==INVALID_HANDLE) return false;
   string line = FileReadString(h);
   FileClose(h);
   string parts[];
   int n = StringSplit(line, ',', parts);
   if(n>=3)
   {
      datetime hb = (datetime)StringToInteger(parts[2]);
      return (TimeCurrent()-hb) <= LINK_TIMEOUT_SEC;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Create Dashboard (Fixed and Enhanced)                             |
//+------------------------------------------------------------------+
void CreateDashboard()
{
   if(!ShowDashboard) return;

   DeleteDashboard();
   InitializeLiveAccountSimulation();

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

   CreateLabel(dashboardPrefix + "Title", _Symbol + " Synergy + PropEA Hedge v1.02", 260, 20, clrWhite, DashboardFontSize + 3, "Arial Bold", true);

   int y = 50;
   CreateLabel(dashboardPrefix + "PhaseLabel", "Phase:", 20, y, textColor, DashboardFontSize);
   CreateLabel(dashboardPrefix + "PhaseValue", IntegerToString(CurrentPhase), 80, y, clrYellow, DashboardFontSize);
   CreateLabel(dashboardPrefix + "HedgeLinkLabel", "Hedge Link:", 300, y, textColor, DashboardFontSize);
   CreateLabel(dashboardPrefix + "HedgeLinkValue", "NOT OK", 380, y, statusRed, DashboardFontSize);

   y += 30;
   CreateSectionHeader("Trading Information", y);
   y += 25;
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

   CreateSectionHeader("Account Status", y);
   y += 25;
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

   CreateCostRecoverySection(y);
   y += 100;

   CreateSectionHeader("Strategy Status", y);
   y += 25;
   CreateLabel(dashboardPrefix + "BiasLabel", "Market Bias:", 20, y, textColor, DashboardFontSize);
   CreateLabel(dashboardPrefix + "BiasValue", "NEUTRAL", 120, y, clrGray, DashboardFontSize);
   CreateLabel(dashboardPrefix + "BiasIndicator", "●", 200, y, currentBiasPositive ? statusGreen : statusRed, DashboardFontSize + 3);
   y += 18;
   CreateLabel(dashboardPrefix + "SynergyLabel", "Synergy Score:", 20, y, textColor, DashboardFontSize);
   CreateLabel(dashboardPrefix + "SynergyValue", DoubleToString(synergyScore, 2), 120, y, textColor, DashboardFontSize);
   y += 18;
   CreateLabel(dashboardPrefix + "ADXLabel", "ADX Status:", 20, y, textColor, DashboardFontSize);
   CreateLabel(dashboardPrefix + "ADXValue", "Waiting", 120, y, statusRed, DashboardFontSize);
   CreateLabel(dashboardPrefix + "ADXValueNum", "(0.0)", 180, y, textColor, DashboardFontSize - 1);
   y += 18;
   CreateLabel(dashboardPrefix + "ScaleOutLabel", "Scale Out:", 20, y, textColor, DashboardFontSize);
   CreateLabel(dashboardPrefix + "ScaleOutValue", "OFF", 120, y, statusRed, DashboardFontSize);
   CreateLabel(dashboardPrefix + "ScaleOutDetails", "", 160, y, textColor, DashboardFontSize - 1);
   y += 18;
   CreateLabel(dashboardPrefix + "PivotLabel", "Pivot Settings:", 20, y, textColor, DashboardFontSize);
   CreateLabel(dashboardPrefix + "PivotValue", IntegerToString(PivotLengthLeft) + "/" + IntegerToString(PivotLengthRight), 120, y, textColor, DashboardFontSize);
   CreateLabel(dashboardPrefix + "PivotBars", "LB:" + IntegerToString(PivotTPBars), 170, y, textColor, DashboardFontSize - 1);
   y += 18;
   CreateLabel(dashboardPrefix + "SessionLabel", "Session Filter:", 20, y, textColor, DashboardFontSize);
   CreateLabel(dashboardPrefix + "SessionValue", EnableSessionFilter ? "ON" : "OFF", 120, y, EnableSessionFilter ? statusGreen : statusRed, DashboardFontSize);
   y += 18;
   CreateLabel(dashboardPrefix + "SignalLabel", "Signal Ready:", 20, y, textColor, DashboardFontSize);
   CreateLabel(dashboardPrefix + "SignalValue", "CHECKING", 120, y, statusOrange, DashboardFontSize);
   y += 18;
   CreateLabel(dashboardPrefix + "TradingLabel", "Trading:", 20, y, textColor, DashboardFontSize);
   CreateLabel(dashboardPrefix + "TradingValue", EnableTrading ? "ENABLED" : "DISABLED", 120, y, EnableTrading ? statusGreen : statusRed, DashboardFontSize);
   y += 18;
   CreateLabel(dashboardPrefix + "TimeLabel", "Last Updated:", 20, y, textColor, DashboardFontSize);
   CreateLabel(dashboardPrefix + "TimeValue", TimeToString(TimeCurrent(), TIME_SECONDS), 120, y, textColor, DashboardFontSize);
}

int OnInit()
{
   string common = TerminalInfoString(TERMINAL_COMMONDATA_PATH);
   if(StringLen(common)>0 && StringGetCharacter(common,StringLen(common)-1)!='\\')
      common += "\\";
   PROP_DATA_PATH = common + PropDataFile;
   HEDGE_DATA_PATH = common + HedgeDataFile;
   HEDGE_HEARTBEAT_FILE_PATH = common + "MT5com_hedge_heartbeat.txt";
   initialBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   ReadPropData();
   ReadHedgeData();
   CreateDashboard();
   return(INIT_SUCCEEDED);
}

void OnTick()
{
   ReadPropData();
   ReadHedgeData();
   UpdateDashboard();
}

void OnDeinit(const int reason)
{
   DeleteDashboard();
}

//+------------------------------------------------------------------+
//| Get Actual Account Volume                                         |
//+------------------------------------------------------------------+
double GetActualAccountVolume()
{
   double total=0;
   for(int i=0;i<PositionsTotal();i++)
   {
      if(PositionGetTicket(i)>0)
         total+=PositionGetDouble(POSITION_VOLUME);
   }
   return total;
}

//+------------------------------------------------------------------+
//| Get Live Account Free Margin                                      |
//+------------------------------------------------------------------+
double GetLiveAccountFreeMargin()
{
   return MathMax(0, hedgeMargin);
}

//+------------------------------------------------------------------+
//| Get Real Daily PnL from History                                   |
//+------------------------------------------------------------------+
double GetRealDailyPnLFromHistory()
{
   datetime startOfDay=0;
   datetime now=TimeCurrent();
   MqlDateTime dt; TimeToStruct(now,dt); dt.hour=0; dt.min=0; dt.sec=0;
   startOfDay=StructToTime(dt);
   if(!HistorySelect(startOfDay,now))
      return 0;
   double profit=0;
   int deals=HistoryDealsTotal();
   for(int i=0;i<deals;i++)
   {
      ulong ticket=HistoryDealGetTicket(i);
      if(ticket>0)
      {
         string sym=HistoryDealGetString(ticket,DEAL_SYMBOL);
         if(sym==_Symbol || sym=="")
         {
            profit+=HistoryDealGetDouble(ticket,DEAL_PROFIT)+HistoryDealGetDouble(ticket,DEAL_SWAP)+HistoryDealGetDouble(ticket,DEAL_COMMISSION);
         }
      }
   }
   return profit;
}

//+------------------------------------------------------------------+
//| Get Real Total PnL from History                                   |
//+------------------------------------------------------------------+
double GetRealTotalPnLFromHistory()
{
   double start=initialBalance;
   double bal=AccountInfoDouble(ACCOUNT_BALANCE);
   double eq=AccountInfoDouble(ACCOUNT_EQUITY);
   return (bal-start)+(eq-bal);
}

//+------------------------------------------------------------------+
//| Update Dashboard with latest values                               |
//+------------------------------------------------------------------+
void UpdateDashboard()
{
   if(!ShowDashboard) return;
   UpdateLiveAccountSimulation();

   bool linkOK=IsLinkAlive(true);
   ObjectSetString(0,dashboardPrefix+"HedgeLinkValue",OBJPROP_TEXT,linkOK?"CONNECTED":"NOT OK");
   ObjectSetInteger(0,dashboardPrefix+"HedgeLinkValue",OBJPROP_COLOR,linkOK?statusGreen:statusRed);

   double propVolume=GetActualAccountVolume();
   double hedgeVolume=propVolume*hedgeFactor;
   ObjectSetString(0,dashboardPrefix+"Volume_Prop",OBJPROP_TEXT,DoubleToString(propVolume,2));
   ObjectSetString(0,dashboardPrefix+"Volume_Real",OBJPROP_TEXT,DoubleToString(hedgeVolume,2));

   double propDailyPnL=GetRealDailyPnLFromHistory();
   double liveDailyPnL=propDailyPnL*hedgeFactor;
   ObjectSetString(0,dashboardPrefix+"Daily PnL_Prop",OBJPROP_TEXT,(propDailyPnL>=0?"+":"")+DoubleToString(propDailyPnL,2));
   ObjectSetString(0,dashboardPrefix+"Daily PnL_Real",OBJPROP_TEXT,(liveDailyPnL>=0?"+":"")+DoubleToString(liveDailyPnL,2));

   double propTotalPnL=GetRealTotalPnLFromHistory();
   double liveTotalPnL=propTotalPnL*hedgeFactor;
   ObjectSetString(0,dashboardPrefix+"Summary PnL_Prop",OBJPROP_TEXT,(propTotalPnL>=0?"+":"")+DoubleToString(propTotalPnL,2)+" / "+DoubleToString(MaxDD,2));
   ObjectSetString(0,dashboardPrefix+"Summary PnL_Real",OBJPROP_TEXT,(liveTotalPnL>=0?"+":"")+DoubleToString(liveTotalPnL,2)+" / "+DoubleToString(ChallengeC,2));

   ObjectSetString(0,dashboardPrefix+"Account_Real",OBJPROP_TEXT,"LIVE-"+IntegerToString(HedgeEA_Magic));

   double propMargin=AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double liveMargin=GetLiveAccountFreeMargin();
   ObjectSetString(0,dashboardPrefix+"Free Margin_Prop",OBJPROP_TEXT,DoubleToString(propMargin,2));
   ObjectSetString(0,dashboardPrefix+"Free Margin_Real",OBJPROP_TEXT,DoubleToString(liveMargin,2));

   int tradingDays=GetTradingDaysCount();
   ObjectSetString(0,dashboardPrefix+"Trading Days_Prop",OBJPROP_TEXT,IntegerToString(tradingDays)+" / "+IntegerToString(tradingDays));
   ObjectSetString(0,dashboardPrefix+"Trading Days_Real",OBJPROP_TEXT,IntegerToString(tradingDays)+" / "+IntegerToString(tradingDays));

   double propLoss=MathMin(0,propTotalPnL);
   double propLossAbs=MathAbs(propLoss);
   double realProfit=MathMax(0,liveTotalPnL);
   double recoveryPct=0;
   if(propLossAbs>0 && realProfit>0)
      recoveryPct=(realProfit/propLossAbs)*100;
   else if(propLossAbs==0 && realProfit>0)
      recoveryPct=100.0;
   ObjectSetString(0,dashboardPrefix+"CostRecovery_Loss_Prop",OBJPROP_TEXT,propLoss<-0.01?DoubleToString(propLoss,2):"0.00");
   ObjectSetString(0,dashboardPrefix+"CostRecovery_Profit_Real",OBJPROP_TEXT,DoubleToString(realProfit,2));
   ObjectSetString(0,dashboardPrefix+"CostRecovery_Recovery",OBJPROP_TEXT,DoubleToString(recoveryPct,1)+"%");

   string biasText="NEUTRAL";
   color biasColor=clrGray;
   if(UseMarketBias)
   {
      biasText=currentBiasPositive?"BULLISH":"BEARISH";
      biasColor=currentBiasPositive?statusGreen:statusRed;
   }
   ObjectSetString(0,dashboardPrefix+"BiasValue",OBJPROP_TEXT,biasText);
   ObjectSetInteger(0,dashboardPrefix+"BiasValue",OBJPROP_COLOR,biasColor);
   ObjectSetInteger(0,dashboardPrefix+"BiasIndicator",OBJPROP_COLOR,biasColor);

   ObjectSetString(0,dashboardPrefix+"SynergyValue",OBJPROP_TEXT,DoubleToString(synergyScore,2));
   ObjectSetInteger(0,dashboardPrefix+"SynergyValue",OBJPROP_COLOR,synergyScore>0?statusGreen:(synergyScore<0?statusRed:textColor));

   bool actualADXCondition=EnableADXFilter?adxTrendCondition:true;
   ObjectSetString(0,dashboardPrefix+"ADXValue",OBJPROP_TEXT,actualADXCondition?"Active":"Waiting");
   ObjectSetInteger(0,dashboardPrefix+"ADXValue",OBJPROP_COLOR,actualADXCondition?statusGreen:statusRed);
   if(EnableADXFilter)
      ObjectSetString(0,dashboardPrefix+"ADXValueNum",OBJPROP_TEXT,"("+DoubleToString(effectiveADXThreshold,1)+")");
   else
      ObjectSetString(0,dashboardPrefix+"ADXValueNum",OBJPROP_TEXT,"(OFF)");

   bool scaleOutActive=EnableScaleOut&&ScaleOut1Enabled;
   ObjectSetString(0,dashboardPrefix+"ScaleOutValue",OBJPROP_TEXT,scaleOutActive?"ON":"OFF");
   ObjectSetInteger(0,dashboardPrefix+"ScaleOutValue",OBJPROP_COLOR,scaleOutActive?statusGreen:statusRed);
   if(scaleOutActive)
      ObjectSetString(0,dashboardPrefix+"ScaleOutDetails",OBJPROP_TEXT,"("+DoubleToString(ScaleOut1Pct,0)+"% at "+DoubleToString(ScaleOut1Size,0)+"%)");
   else
      ObjectSetString(0,dashboardPrefix+"ScaleOutDetails",OBJPROP_TEXT,"");

   ObjectSetString(0,dashboardPrefix+"SessionValue",OBJPROP_TEXT,EnableSessionFilter?"ON":"OFF");
   ObjectSetInteger(0,dashboardPrefix+"SessionValue",OBJPROP_COLOR,EnableSessionFilter?statusGreen:statusRed);

   bool signalReady=entryTriggersEnabled && (EnableADXFilter?adxTrendCondition:true) && IsInTradingSession() && EnableTrading && !HasOpenPosition();
   string signalStatus="NOT READY";
   color signalColor=statusRed;
   if(signalReady){signalStatus="READY";signalColor=statusGreen;}
   else if(!EnableTrading){signalStatus="DISABLED";signalColor=statusRed;}
   else if(HasOpenPosition()){signalStatus="IN TRADE";signalColor=statusOrange;}
   else if(!IsInTradingSession()){signalStatus="OUT OF SESSION";signalColor=statusOrange;}
   else if(EnableADXFilter && !adxTrendCondition){signalStatus="ADX WAIT";signalColor=statusOrange;}
   ObjectSetString(0,dashboardPrefix+"SignalValue",OBJPROP_TEXT,signalStatus);
   ObjectSetInteger(0,dashboardPrefix+"SignalValue",OBJPROP_COLOR,signalColor);

   ObjectSetString(0,dashboardPrefix+"TradingValue",OBJPROP_TEXT,EnableTrading?"ENABLED":"DISABLED");
   ObjectSetInteger(0,dashboardPrefix+"TradingValue",OBJPROP_COLOR,EnableTrading?statusGreen:statusRed);

   ObjectSetString(0,dashboardPrefix+"TimeValue",OBJPROP_TEXT,TimeToString(TimeCurrent(),TIME_SECONDS));
}

//+------------------------------------------------------------------+
//| Create a section header                                           |
//+------------------------------------------------------------------+
void CreateSectionHeader(string title,int y)
{
   if(!ShowDashboard) return;
   string name=dashboardPrefix+"Section_"+title;
   ObjectCreate(0,name+"_BG",OBJ_RECTANGLE_LABEL,0,0,0);
   ObjectSetInteger(0,name+"_BG",OBJPROP_XDISTANCE,DashboardXPosition);
   ObjectSetInteger(0,name+"_BG",OBJPROP_YDISTANCE,DashboardYPosition+y);
   ObjectSetInteger(0,name+"_BG",OBJPROP_XSIZE,520);
   ObjectSetInteger(0,name+"_BG",OBJPROP_YSIZE,25);
   ObjectSetInteger(0,name+"_BG",OBJPROP_BGCOLOR,sectionHeaderBg);
   ObjectSetInteger(0,name+"_BG",OBJPROP_BORDER_TYPE,BORDER_FLAT);
   ObjectSetInteger(0,name+"_BG",OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,name+"_BG",OBJPROP_STYLE,STYLE_SOLID);
   ObjectSetInteger(0,name+"_BG",OBJPROP_WIDTH,1);
   ObjectSetInteger(0,name+"_BG",OBJPROP_BACK,false);
   ObjectSetInteger(0,name+"_BG",OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name+"_BG",OBJPROP_SELECTED,false);
   ObjectSetInteger(0,name+"_BG",OBJPROP_HIDDEN,true);
   ObjectSetInteger(0,name+"_BG",OBJPROP_ZORDER,2);
   CreateLabel(name,title,260,y+13,clrWhite,DashboardFontSize,"Arial Bold",true);
}

//+------------------------------------------------------------------+
//| Create a data row                                                 |
//+------------------------------------------------------------------+
void CreateDataRow(string label,string propValue,string liveValue,int y)
{
   if(!ShowDashboard) return;
   string name=dashboardPrefix+label;
   ObjectCreate(0,name+"_BG",OBJ_RECTANGLE_LABEL,0,0,0);
   ObjectSetInteger(0,name+"_BG",OBJPROP_XDISTANCE,DashboardXPosition);
   ObjectSetInteger(0,name+"_BG",OBJPROP_YDISTANCE,DashboardYPosition+y);
   ObjectSetInteger(0,name+"_BG",OBJPROP_XSIZE,520);
   ObjectSetInteger(0,name+"_BG",OBJPROP_YSIZE,20);
   ObjectSetInteger(0,name+"_BG",OBJPROP_BGCOLOR,dataBgColor);
   ObjectSetInteger(0,name+"_BG",OBJPROP_BORDER_TYPE,BORDER_FLAT);
   ObjectSetInteger(0,name+"_BG",OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,name+"_BG",OBJPROP_STYLE,STYLE_SOLID);
   ObjectSetInteger(0,name+"_BG",OBJPROP_WIDTH,1);
   ObjectSetInteger(0,name+"_BG",OBJPROP_BACK,false);
   ObjectSetInteger(0,name+"_BG",OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name+"_BG",OBJPROP_SELECTED,false);
   ObjectSetInteger(0,name+"_BG",OBJPROP_HIDDEN,true);
   ObjectSetInteger(0,name+"_BG",OBJPROP_ZORDER,2);
   CreateLabel(name,label,20,y+10,textColor,DashboardFontSize,"Arial",false);
   CreateLabel(name+"_Prop",propValue,200,y+10,textColor,DashboardFontSize,"Arial",true);
   CreateLabel(name+"_Real",liveValue,380,y+10,textColor,DashboardFontSize,"Arial",true);
}

//+------------------------------------------------------------------+
//| Create Cost Recovery section                                      |
//+------------------------------------------------------------------+
void CreateCostRecoverySection(int y)
{
   if(!ShowDashboard) return;
   string name=dashboardPrefix+"CostRecovery";
   CreateSectionHeader("Cost Recovery Estimate",y);
   y+=25;
   CreateLabel(name+"_Criteria","Criteria",20,y+10,textColor,DashboardFontSize);
   CreateLabel(name+"_Loss_Header","Loss PropAcc",200,y+10,clrYellow,DashboardFontSize,"Arial",true);
   CreateLabel(name+"_Profit_Header","Profit LiveAcc",350,y+10,clrYellow,DashboardFontSize,"Arial",true);
   CreateLabel(name+"_Recovery_Header","Recovery %",450,y+10,clrYellow,DashboardFontSize,"Arial",true);
   y+=20;
   ObjectCreate(0,name+"_MaxDD_BG",OBJ_RECTANGLE_LABEL,0,0,0);
   ObjectSetInteger(0,name+"_MaxDD_BG",OBJPROP_XDISTANCE,DashboardXPosition);
   ObjectSetInteger(0,name+"_MaxDD_BG",OBJPROP_YDISTANCE,DashboardYPosition+y);
   ObjectSetInteger(0,name+"_MaxDD_BG",OBJPROP_XSIZE,520);
   ObjectSetInteger(0,name+"_MaxDD_BG",OBJPROP_YSIZE,20);
   ObjectSetInteger(0,name+"_MaxDD_BG",OBJPROP_BGCOLOR,costRecoveryCriteriaBg);
   ObjectSetInteger(0,name+"_MaxDD_BG",OBJPROP_BORDER_TYPE,BORDER_FLAT);
   ObjectSetInteger(0,name+"_MaxDD_BG",OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,name+"_MaxDD_BG",OBJPROP_BACK,false);
   ObjectSetInteger(0,name+"_MaxDD_BG",OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name+"_MaxDD_BG",OBJPROP_HIDDEN,true);
   ObjectSetInteger(0,name+"_MaxDD_BG",OBJPROP_ZORDER,2);
   CreateLabel(name+"_MaxDD","Max DD",20,y+10,textColor,DashboardFontSize);
   CreateLabel(name+"_Loss_Prop","0.00",200,y+10,textColor,DashboardFontSize,"Arial",true);
   CreateLabel(name+"_Profit_Real","0.00",350,y+10,textColor,DashboardFontSize,"Arial",true);
   CreateLabel(name+"_Recovery","0.0%",450,y+10,textColor,DashboardFontSize,"Arial",true);
}

//+------------------------------------------------------------------+
//| Delete dashboard                                                  |
//+------------------------------------------------------------------+
void DeleteDashboard()
{
   ObjectsDeleteAll(0,dashboardPrefix);
}

//+------------------------------------------------------------------+
//| Create a text label                                               |
//+------------------------------------------------------------------+
void CreateLabel(string name,string text,int x,int y,color clr,int fontSize,string font="Arial",bool centered=false)
{
   if(!ShowDashboard) return;
   ObjectCreate(0,name,OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,DashboardXPosition+x);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,DashboardYPosition+y);
   ObjectSetString(0,name,OBJPROP_TEXT,text);
   ObjectSetString(0,name,OBJPROP_FONT,font);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,fontSize);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_ANCHOR,centered?ANCHOR_CENTER:ANCHOR_LEFT);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
   ObjectSetInteger(0,name,OBJPROP_ZORDER,3);
}

//+------------------------------------------------------------------+
//| Get Daily PnL                                                     |
//+------------------------------------------------------------------+
double GetDailyPnL()
{
   static double dayStart=0; static datetime lastDay=0;
   datetime now=TimeCurrent(); MqlDateTime dt; TimeToStruct(now,dt);
   if(lastDay!=dt.day || dayStart==0){dayStart=AccountInfoDouble(ACCOUNT_BALANCE); lastDay=dt.day;}
   return AccountInfoDouble(ACCOUNT_EQUITY)-dayStart;
}

//+------------------------------------------------------------------+
//| Get Trading Days Count                                            |
//+------------------------------------------------------------------+
int GetTradingDaysCount()
{
   static int tradingDays=1; static datetime lastCheck=0;
   datetime now=TimeCurrent(); MqlDateTime cur,last; TimeToStruct(now,cur); TimeToStruct(lastCheck,last);
   if(lastCheck==0){lastCheck=now; return tradingDays;}
   if(cur.day!=last.day){tradingDays++; lastCheck=now;}
   return tradingDays;
}

