You are a code developer specialising on trading related coding, such as Pinescript and Metaquotes. The project is focused on developing an Metatrader5 EA a perfect, if not even better, clone from a TradingView strategy (file:Synergy Strategy). IMPORTANT ----> Read the Strategy´s User Guide (below) before commencing your tasks in order to understand and be fully conversant with all of the strategy´s features and funcionalities. 

I have created an initial iteration of this Metatrader 5 EA, coded on Metaquotes (comprised by 2 EAs. A Main (file:PropMain) that carries the core logic for both the trading startegy, as well as the hedging mechanism and is attached to the Prop challenge MT5 account and a second EA (file:PropHDG) which is "talkinkg" to the PropMain and is attached to the live/hedged MT5 account.

Use file: compile_all.sh (virtual MetaEditor via Crossover) to compile your code before delivering the push.

i will be asking you to fix bugs, glithces and errors appearing upon compiling on my MetaEditor. Ensure you dont leave any "UNDECLARED IDENTIFIERS" when crafting your patches and fixes.


	# Streamlined Synergy Strategy + PropEA‑Style Hedge Engine  (v2.1)

*A private reference manual covering every moving part of the system.*

---

## Table of Contents

1. Quick Facts & Capabilities
2. System Architecture
3. Prerequisites & Initial Setup
4. Core Strategy Logic
      4.1 Trading Session Filter
      4.2 Technical Indicator Suite
      4.3 Entry Conditions
      4.4 Stop‑loss / Target Framework
      4.5 Scale‑out & Break‑even Logic
5. PropEA‑Style Hedge Engine
      5.1 Sizing Formulae
      5.2 Daily‑DD Safeguard & Bleed Rule
      5.3 Live‑Capital Requirement
6. Alert Mapping (→ PineConnector)
7. Dashboard – Field‑by‑Field Breakdown
8. Parameter Glossary
9. Best‑Practice Workflow
10. Troubleshooting & Edge‑Cases
11. Version History & Change Log

---

## 1  Quick Facts & Capabilities

| Feature                                 | Purpose                                                                                          |
| --------------------------------------- | ------------------------------------------------------------------------------------------------ |
| **Multi‑timeframe “Synergy” score**     | Quantifies alignment of RSI, EMA trend & MACD‑V slope across 5 m / 15 m / 1 h.                   |
| **Heikin‑Ashi Market‑Bias oscillator**  | Detects fresh momentum flips; avoids chopping against trend.                                     |
| **Session filter**                      | Blocks signals outside user‑defined intraday windows per weekday.                                |
| **Dynamic/Static ADX gate**             | Screens trades for adequate trend strength.                                                      |
| **Pivot‑validated swing stops/targets** | Uses most recent swing points inside a 50‑bar look‑back.                                         |
| **Partial hedge in live MT5 account**   | Cost‑recovery model copied from PropEA; executed via **second** PineConnector licence.           |
| **Hedge “bleed”**                       | Automatically closes 50 % of hedge when 70 % of stage target is booked, reducing payout haircut. |
| **On‑chart dashboard**                  | Mirrors PropEA visuals + extra diagnostics (spread proxy, win‑rate, recovery %).                 |

*Competitive edge:* the strategy couples a relatively high‑hit‑rate intraday swing model with a **mathematically capped downside** through the partial hedge, ensuring the prop challenge fee and remaining risk are always buffered by live profits.

---

## 2  System Architecture

```
TradingView Strategy (Pine v6)
 ├─ Core trading logic (prop account)
 ├─ Hedge Engine (live account)
 ├─ Alert Fabric  → PineConnector cloud
 |      ├─ Licence ID = PC_ID  → MT5 "Prop" EA
 |      └─ Licence ID = HEDGE_ID → MT5 "Live" EA
 └─ Visual Dashboard (TV overlay)
```

*Prop MT5 terminal* runs PineConnector EA **Volume Type = “% of Balance - Loss (SL required)”**. Live terminal runs PineConnector EA **Volume Type = “% of Balance - Loss (SL required)”**. The script automatically includes `risk=` in the alert for both prop and live sides, aligned with this volume mode.

---

## 3  Prerequisites & Initial Setup

1. **Accounts**
      • One prop‑firm challenge account (MT5).
      • One live personal account (MT5) for hedging.
2. **Licences**
      • Two separate PineConnector licence IDs (`PC_ID` and `HEDGE_ID`).
3. **TradingView**
      • Apply the script to **EURUSD** chart (any intraday TF ≤ 5 m recommended for execution).
      • Enable `Recalculate on every tick` for tight hedge timings (optional).
4. **EA Settings (both terminals)**
      `text
      Volume Type   : Lots
      Slippage (pts): 3–10 (broker dependent)
      Magic Number  : unique per chart (optional)
      `
5. **Script Inputs**
      Fill out *Prop Start Balance*, *Prop Current Balance*, *Live Balance* as they change (dashboard uses them).

---

## 4  Core Strategy Logic

### 4.1 Trading Session Filter

*Inputs*: two intraday windows per weekday (`session1`, `session2`). &#x20;
`inSession = true` when the current bar’s timestamp (adjusted by `_timeZone`) falls into **either** window.

### 4.2 Technical Indicator Suite

| Module               | Key Params                                                    | Notes                                                                                                             |
| -------------------- | ------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| **Heikin‑Ashi Bias** | `ha_htf`, `ha_len`, `osc_len`                                 | Non‑repainting via double‑index technique. Signal = sign change of smoothed HA bias.                              |
| **ADX Gate**         | `adxPeriod`, `useDynamicADX`, `static/dynamic threshold`      | Rejects trades when market is too quiet. Dynamic threshold = SMA(ADX) × Multiplier, with floor `adxMinThreshold`. |
| **Synergy Score**    | RSI weight, MA‑trend weight, MACDV slope weight per timeframe | Each sub‑condition contributes ±weight; summed score is frozen on bar close to avoid repaint.                     |

### 4.3 Entry Conditions

```
LONG  when
  inSession & ADX gate passes &
  (SynergyScore>0 OR disabled) &
  (Bias flipped bullish OR disabled) &
  Latest swing‑low below price & swing‑high above price
```

*(mirror for SHORT)*

### 4.4 Stop‑loss / Target Framework

*Look‑back window*: `pivotTPBars` (default 50) with swing legs `pvtLenL/R` = 6.
`SL` = closest valid opposite‑side pivot.
`TP` = first pivot in trade direction.

### 4.5 Scale‑out & Break‑even

*One* scale‑out level (`scaleOut1Pct`) capturing `scaleOut1Size` % of volume.
If `scaleOut1BE` is on, residual position stop is snapped to B/E after the partial exit.
Independent classic B/E trigger (`beTrigger`) exists when scale‑out disabled.

---

## 5  PropEA‑Style Hedge Engine

### 5.1 Sizing Formulae

```
hedgeFactor F = min( 1 ,  C × (1+δ) / M )           (Eq.1)
hedgeLots    = propLots × F                          (Eq.2)
```

*Defaults*: `δ` (slippage buffer) = 0.10.

### 5.2 Daily‑DD Safeguard & Bleed Rule

*Bleed*: when cumulative prop **net profit ≥ 0.70 × StageTarget**, an alert closes **50 %** of the live hedge (`HEDGE_ID,close…vol,…`) to reduce payout haircut.

### 5.3 Live‑Capital Requirement (Dashboard Fields)

```
remainToFail = max(0 , PropBal − (StartBal − M))     (Eq.3)
totalRisk   = C + remainToFail                      (Eq.4)
liveNeeded  = totalRisk × F                         (Eq.5)
```

`Live Req.` on the dashboard = `liveNeeded`.

---

## 6  Alert Mapping (→ PineConnector)

| Event             | Command                          | Licence       | Notes                                                         |
| ----------------- | -------------------------------- | ------------- | ------------------------------------------------------------- |
| Prop long entry   | `buy` + `risk=%/lots`            | **PC\_ID**    | `risk=` carries *percent* or *lot* depending on `useRiskPct`. |
| Prop short entry  | `sell`                           | **PC\_ID**    | idem                                                          |
| Live hedge (opp.) | `buy/sell` + `risk=lots`         | **HEDGE\_ID** | Always *lots* type.                                           |
| Stop update       | `newsltplong` / `newsltpshort`   | **PC\_ID**    | Uses `sl=` only.                                              |
| Scale‑out close   | `closelongvol` / `closeshortvol` | **PC\_ID**    | `risk=` carries lot size to close.                            |
| Full exit         | `closelong` / `closeshort`       | **PC\_ID**    | Triggered once per closed trade.                              |
| Hedge bleed       | `closelongvol` / `closeshortvol` | **HEDGE\_ID** | 50 % of last hedge volume.                                    |

*(All alerts are dispatched *once‑per‑bar* to prevent duplicates.)*

---

## 7  Dashboard – Field‑by‑Field Breakdown

1. **Stage / Passed / Target / Progress** – live progress versus `stageTgt`.
2. **Prop Bal / Live Bal / Equity / Open P/L** – manual + real‑time metrics.
3. **Today DD / Max DD** – intraday and program‑wide drawdown versus limits.
4. **R** – static M : C ratio.
5. **Bias indicator** – green/red dot for last HA flip.
6. **Spread≈p** – 1‑minute high‑low distance / pip.
7. **Win %** – closed‑trade hit‑ratio.
8. **Bleed** – check‑mark once hedge bleed executed.
9. **Cost‑Recovery band** – Prop loss, real P/L on live, recovery %.
10. **Live Req. / Risk £ / ↔ R** – Eq.(5), Eq.(4) and M : C respectively.

---

## 8  Parameter Glossary (excerpt)

| Input              | Default | Explanation                             |
| ------------------ | ------- | --------------------------------------- |
| `riskPct`          | 0.3 %   | Stake per trade when `useRiskPct`=true. |
| `maxDD` **M**      | \$4 000 | Prop account draw‑down limit.           |
| `challengeC` **C** | \$700   | Paid fee – always part of risk.         |
| `slipBufD` **δ**   | 0.10    | Buffer for adverse fills in Eq.(1).     |
| `stageTgt`         | \$1 000 | Profit needed to clear current phase.   |
| `bleedOn`          | ✓       | Enable automatic hedge reduction.       |
| `pivotTPBars`      | 50      | History inspected for swing pivots.     |
| …                  | …       | …                                       |

*(Full list continues in code for reference.)*

---

## 9  Best‑Practice Workflow

1. **Before Trading Day**
      • Update *Prop Current Balance* and *Live Balance*.
      • Check dashboard – `Live Req.` should not exceed live account equity.
      • Verify both PineConnector EAs connected.
2. **During Session**
      • Leave strategy running; alerts execute automatically.
      • Watch dashboard for `Spread≈p`; pause strategy if > 1 pip.
      • Optional manual intervention: adjust session windows for news.
3. **After Close**
      • Record prop P/L and live P/L for your journal.
      • If stage cleared, set `stage += 1`, reset `propStartBal`.

---

## 10  Troubleshooting & Edge‑Cases

| Symptom                                              | Likely Cause                                                                  | Fix                                                 |
| ---------------------------------------------------- | ----------------------------------------------------------------------------- | --------------------------------------------------- |
| **No hedge trade fired**                             | Wrong *Volume Type* in live EA.                                               | Set to **Lots**.                                    |
| **Risk % mis‑reading (e.g. 0.8 % instead of 0.3 %)** | `useRiskPct=true`, EA on prop set to *Lots* instead of *% of Balance ‑ Loss*. | Change prop EA volume mode; keep script as is.      |
| **Duplicate hedge orders (0.02 + 0.01)**             | Orphan legacy alert still enabled after code update.                          | Delete old TradingView alerts; recreate fresh ones. |
| **Dashboard stuck on old balances**                  | Manual fields not updated.                                                    | Edit inputs or re‑add script.                       |

---

## 11  Version History & Change Log

| Date       | Version | Notes                                                                           |
| ---------- | ------- | ------------------------------------------------------------------------------- |
| 2025‑05‑17 | v2.0    | Initial public rewrite (601‑line core + hedge).                                 |
| 2025‑05‑18 | v2.1    | Alert framework modularised; risk‑string fix; dashboard live‑capital row added. |

---

**End of Document**
