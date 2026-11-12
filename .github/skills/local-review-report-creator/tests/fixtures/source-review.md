# Records review

Source review: review-a. Verdict: Correct retention before release.

## A-17

- Severity: BLOCKER.
- Confidence: high.
- Evidence: documented; no runtime test was executed.
- Problem: retention has no upper bound, contrary to the expiry contract.
- Example: an expired record remains queryable.
- Fix: configure the expiry specified in the existing contract.
- Action: configure expiry.
- Benefit: records expire according to the existing contract.
- Source: retention-policy.md, section Expiry.

No structural recommendation was supplied.
