Test: testShowDetailPassesAccessibilityAudit
Failure: “Severance” title reported as potentially clipped at larger text sizes.
Environment: fails on iPhone 16 / iOS 18.6; passes on iPhone 16 Pro / iOS 18.6.
Baseline: Claude reproduced it on ab78b37, before R02.
Disposition: open accessibility issue; investigate the layout before adding an audit exception.
During Rxx work: this exact failure in this environment does not block unrelated fixes. Report it as a known failure; investigate any different failure or changed symptom.
Follow-up: include it in our consolidated testing script.
