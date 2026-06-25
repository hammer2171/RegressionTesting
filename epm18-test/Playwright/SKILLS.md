# Playwright Skills

- Use TypeScript Playwright tests with Microsoft Edge by default.
- Store browser auth state under playwright\.auth; never commit or copy auth JSON files between pods or users.
- Use .env.epm18_test or an explicit ENV_FILE for pod-specific settings. Keep secrets out of shared templates.
- Use 
pm run auth:refresh to create or refresh storage state, then 
pm run test:e2e:evidence:full for headed evidence runs.
- Put reusable fixtures under 	ests\fixtures, helpers under 	ests\helpers, page objects under pages, and actual specs under 	ests\e2e.
- Keep generated artifacts in 	est-results, playwright-report, lob-report, or output; archive evidence with the existing scripts.
