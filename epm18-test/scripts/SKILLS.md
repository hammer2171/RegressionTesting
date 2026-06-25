# Scripts Skills

- Write PowerShell 5.1 compatible scripts unless there is a clear reason to require newer PowerShell.
- Every executable script should be parameterized, set \Stop = "Stop", and create a timestamped run folder under C:\RegressionTesting\epm18-test\Runs by default.
- Log each run to a file and to the console. Include the endpoint, method, output paths, and failure details, but do not log passwords or full Authorization headers.
- Use CMS-decrypted credentials and Basic auth headers following the reference scripts in ..\reference.
- Keep scripts runnable from the server as snippets: powershell -NoProfile -ExecutionPolicy Bypass -File .\ScriptName.ps1 ....
