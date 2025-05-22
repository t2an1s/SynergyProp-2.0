#property copyright "t2an1s"
#property version   "1.00"
#property strict

#include "PropMain_Dash.mq5"
#include "SynergyCommon.mqh"

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

