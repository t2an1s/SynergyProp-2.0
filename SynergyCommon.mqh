#ifndef SYNERGY_COMMON_MQH
#define SYNERGY_COMMON_MQH

// Shared constants for communication timing and file handling
const int HEARTBEAT_SEC    = 5;  // how often we publish our pulse
const int LINK_TIMEOUT_SEC = 15; // grace window before status = NOT OK
const int FILE_WRITE_RETRY = 3;  // retries for file operations
const int FILE_CHECK_SECONDS = 5; // interval for heartbeat checks

// Lightweight string hash used for signal encoding
ulong StringHash(string text)
{
   ulong result = 0;
   for(int i = 0; i < StringLen(text); i++)
      result += (ulong)StringGetCharacter(text, i);
   return result;
}

#endif // SYNERGY_COMMON_MQH
