# CalcResponsbility Package Notes

Combined SCU package for epm2-test.

Operations:

1. Run Business Ruleset `Ruleset_Responsibility`
2. Run Data Map `FinPlan_to_FinRPT_Current_Snapshot`

Assumption used for the Data Rule input:

- `startperiod=Jan-&PlanYr`
- `endperiod=Dec-&PlanYr`
- `importmode=REPLACE`
- `exportmode=STORE_DATA`

The BRS input uses the corrected RTP names:

- `rtpsScenario`
- `rtpVersion`
- `rtpYear`
