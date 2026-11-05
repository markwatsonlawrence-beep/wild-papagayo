# Wild Engine Core

Run the complete site build from the project root:

```powershell
.\wild-engine.ps1
```

The active modules are configured in `engine/config/modules.json`.
Each module runs in a separate PowerShell process so a script-level `exit`
does not terminate the Core unexpectedly.

Reports are written to `/reports/`:

- `build-report.html`
- `build-report.txt`
- `build-history.json`
- timestamped build logs

Optional flags:

```powershell
.\wild-engine.ps1 -SkipQuestions
.\wild-engine.ps1 -NoHtmlReport
```
