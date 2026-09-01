# Live UI Sweep And Implementation Plan

Date: 2026-05-06
Reviewed site: `https://<web-app-name>.azurewebsites.net/`
Reviewed run: `20260507053821` (`canadacentral -> eastus`, completed, 28 records)

## Purpose

This note aligns the current hosted web experience with the implementation goals already captured in [docs/Implementation/Spec.md](<repo-root>/docs/Implementation/Spec.md):

1. make canonical identity authoritative in comparison row construction and storage,
2. generate reusable fallback curation artifacts from comparison output,
3. add hosted app workflows that isolate fallback rows and identity sources,
4. keep the hosted UI aligned with the comparison and migration-planning surface.

The live sweep covered the Overview, Results, and Runs views, including:

- the latest completed run from Runs,
- the Results filters and fallback-only focus,
- a fallback detail panel,
- a VM family breakdown detail panel,
- result pagination.

## What Is Working

- The hosted shell loads and auth is functioning well enough to review the application.
- Runs can open an older comparison without mutating the Overview form.
- Results exposes the data model the repo has been building toward: canonical identity coverage, fallback counts, service families, detailed comparison rows, and richer breakdowns for VM families and managed disks.
- Fallback-only focus is useful and materially supports the curation workflow.
- Pagination works on the result set, which is necessary now that the comparison surface is broad enough to exceed a single page.

## Gaps Observed In The Live App

### P0: Runs view has a status duplication defect

The live Runs cards render duplicate status strings such as `completed completed` and `failed failed`.

Impact:

- It reduces trust in the run summary even when the underlying run data is correct.
- It makes the app feel less production-ready than the underlying comparison engine actually is.

Owning surface:

- [web_app/src/App.jsx](<repo-root>/web_app/src/App.jsx#L2909)

### P1: Results is still diagnostics-first instead of migration-planning-first

The Results page contains the right data, but the first screen a user sees is still dominated by dense service cards and diagnostics framing. The user has to infer what requires action rather than being guided to it.

Observed symptoms:

- long summary prose at the card level,
- no explicit priority buckets such as `move-ready`, `needs identity review`, `pricing gap`, or `region gap`,
- important action states are mixed with descriptive context rather than surfaced as the primary signal.

Impact:

- The app reads like an internal analysis console instead of a migration-planning workspace.
- The intended end goal from the repo plan, turning comparison output into a practical decision surface, is only partially realized.

Owning surface:

- [web_app/src/App.jsx](<repo-root>/web_app/src/App.jsx#L2948)

### P1: Fallback diagnostics are too raw for the main user path

The fallback workflow is valuable, but the current detail panels expose internal provenance and raw provider metadata too early. The Event Hub fallback row, for example, surfaces a long list of provider resource types and internal identity-diagnosis language directly in the primary detail flow.

Observed symptoms:

- raw provider resource-type lists are shown inline,
- provenance labels such as `Derived Pricing Fallback` and `Provider Service Name Fallback` are accurate but not user-friendly,
- the distinction between planner-facing guidance and operator-facing diagnostics is not strong enough.

Impact:

- The app leaks internal curation and data-pipeline detail into the main planning experience.
- The hosted workflow requested in the spec exists, but it is not yet shaped for the right audience.

Owning surface:

- [web_app/src/App.jsx](<repo-root>/web_app/src/App.jsx#L3076)

### P1: Result cards carry too much prose before expansion

The top-level result card summaries still contain large narrative blocks. The same card is trying to act as summary, explanation, and diagnostic excerpt all at once.

Observed symptoms:

- long contextual paragraphs in collapsed cards,
- dense VM summary text before the user chooses to expand,
- technical context competing with the decision signal.

Impact:

- Scanning for blockers and region gaps is slower than it should be.
- The list does not yet behave like a triage queue.

Owning surface:

- [web_app/src/App.jsx](<repo-root>/web_app/src/App.jsx#L3157)

### P2: Overview does not yet frame the downstream decision model strongly enough

Overview is cleaner than before, but it still describes the comparison in generic terms. It does not fully prepare the user for how the tool should be used after the run completes.

Missing framing:

- what constitutes a successful migration-ready result,
- what fallback identities mean in practical terms,
- what the user should do first in Results after a run completes.

Impact:

- The first-run experience is clearer than before, but still underspecifies the intended workflow.

Owning surface:

- [web_app/src/App.jsx](<repo-root>/web_app/src/App.jsx#L2777)

## Alignment To Repo End Goals

The live product is already close to the repo's intended technical direction. The remaining gap is not primarily missing data. It is presentation and workflow hierarchy.

The current implementation proves that the system can:

- attach canonical identity to comparison rows,
- surface fallback identity coverage,
- show detailed pricing and capability breakdowns,
- reopen historical runs.

The remaining product work is to turn those capabilities into a clearer operating model:

1. prioritize action-oriented summaries over internal diagnostics,
2. separate planner-facing guidance from advanced curation/operator detail,
3. make fallback review feel intentional instead of incidental,
4. express run health and run selection without UI noise or duplicated labels.

## Implementation Plan

### Slice 1: Correctness And UI Polish

Goal:

- Remove visible defects that undermine trust.

Work:

- Fix duplicate status rendering in Runs.
- Audit status-label composition between `formatRunMeta`, `renderStatusBadge`, and the run button summary.
- Verify the selected-run styling and labeling remain correct after the fix.

Primary surface:

- [web_app/src/App.jsx](<repo-root>/web_app/src/App.jsx#L2909)

### Slice 2: Reframe Results As A Triage Workspace

Goal:

- Make the first Results screen answer: what is blocked, what needs review, and what is ready.

Work:

- Add a top-level action summary row with buckets such as `region gaps`, `fallback identities`, `pricing gaps`, and `move-ready services`.
- Sort or spotlight action-needed rows before purely matched rows.
- Add one-click focus buttons for the main planning tasks, not only identity focus.

Primary surface:

- [web_app/src/App.jsx](<repo-root>/web_app/src/App.jsx#L2948)

### Slice 3: Move Advanced Diagnostics Behind Intentional Disclosure

Goal:

- Keep the fallback workflow useful without making the main detail view read like backend telemetry.

Work:

- Keep a simple fallback explanation visible in the main panel.
- Move long provider resource-type lists and lower-level provenance details into an `Advanced diagnostics` disclosure.
- Rewrite fallback labels in user-facing terms while preserving the underlying codes for deeper inspection.

Primary surface:

- [web_app/src/App.jsx](<repo-root>/web_app/src/App.jsx#L3157)

### Slice 4: Compress Result Card Summaries

Goal:

- Make the collapsed list scannable.

Work:

- Reduce each collapsed card to a short lead line and a small set of outcome chips.
- Reserve the longer contextual narrative for the expanded body.
- Keep pricing and availability summaries compact until expansion.

Primary surface:

- [web_app/src/App.jsx](<repo-root>/web_app/src/App.jsx#L3157)

### Slice 5: Tighten Overview To Results Handoff

Goal:

- Make the product's intended workflow explicit before the user runs a comparison.

Work:

- Update Overview copy to explain the next step after execution: review blockers first, then fallback identity rows, then pricing details.
- Add a concise explanation of what fallback identity means in practice.
- Show the latest successful run more clearly as a continuation point.

Primary surface:

- [web_app/src/App.jsx](<repo-root>/web_app/src/App.jsx#L2777)

## Recommended Next Implementation Order

1. Fix the Runs duplication defect.
2. Add a triage summary layer to Results.
3. Compress collapsed result-card copy.
4. Move advanced fallback diagnostics behind explicit disclosure.
5. Refresh Overview copy so it better frames the downstream workflow.

## Exit Criteria

This slice is complete when the hosted app behaves like a migration-planning tool first and a diagnostics console second.

Specifically:

- a user can identify blockers and next actions within the first screen of Results,
- fallback rows are easy to isolate without forcing raw diagnostics into the main path,
- run history reads cleanly and accurately,
- collapsed result cards are scannable across a full page of services,
- the UI communicates how comparison output maps to migration planning, not only how the backend data was derived.