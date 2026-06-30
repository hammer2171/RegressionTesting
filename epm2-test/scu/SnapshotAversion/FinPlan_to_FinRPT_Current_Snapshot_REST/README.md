# FinPlan_to_FinRPT_Current_Snapshot REST Package

This is the repeatable SnapshotAversion package for the Data Exchange Data Map:

`FinPlan_to_FinRPT_Current_Snapshot`

Purpose:

- Clear the target intersection before the push.
- Push both planned years in one repeatable package.

Clear-before-push behavior:

- `importmode=REPLACE`

Year span used by this package:

- `startperiod=Jan-&PlanYr`
- `endperiod=Dec-&PlanYr2`

Package contents:

- `requirement.csv`
- `run_datamap_input_FinPlan_to_FinRPT_Current_Snapshot.csv`

Mapping reference:

- `FINPLAN -> Fin_Rpt`
- `Scenario Forecast -> Scenario`
- `Version &CurrentSnapshot -> Version`
- `Years &PlanYr, &PlanYr2 -> Years`

This folder is meant to be copied into the SimCon/O: drop as a repeatable artifact.
