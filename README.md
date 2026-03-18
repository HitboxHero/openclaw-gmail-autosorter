OpenClaw Gmail Auto-Sorter (Windows)
====================================

I was very much on top of my email for years and spent hour organinzing them into archived labeled "folders" but it's become harder than ever for me even after most sites streamlined the "unsubscribe" process. I started this project with over 5000 emails in my inbox, now I have three. I run this and all important to hold onto emails are divided up eveb though I dont need to look at them everyday.

This is a Windows PowerShell script that sorts your inbox by applying Gmail labels (your “folders”) and removing the INBOX label (which is how Gmail actually “moves” stuff out of your inbox).


What this does
--------------

1) Brain: OpenClaw
- OpenClaw looks at a small summary of each Gmail thread (from/subject/labels).
- It decides which label the thread should go to.

2) Hands: gog.exe
- gog.exe talks to Gmail using the Gmail API (OAuth).
- It adds the label OpenClaw chose.
- It removes the INBOX label, which archives the thread out of your inbox.

What it can do
--------------
- Move most inbox emails into labels like:
  Gaming, Receipts, Church, Trips, Personal life, School, Work, Action
- Keep STARRED emails in your inbox (so you always have a manual “do not move” flag)
- Use an Action label to keep “needs attention” emails from clogging your inbox:
  verification codes, security alerts, DocuSign, Drive share requests, buyer messages, domain alerts


What it does NOT do
-------------------
- It does not delete emails (but probably could be edited to do so in futute versions).
- It does not unsubscribe you.
- It does not reply to emails.
- It does not run in the cloud. This all runs locally on your PC.


Before anything else (seriously)
--------------------------------
There are several important tokens that can be used locally but should be never posted online. They live in the openclaw.json and client_secret_*.json from Google Cloud. Never divulge them online.


Quick Start (copy/paste)
------------------------
1) Start OpenClaw gateway (leave it running):
  openclaw gateway --port 18789

2) Confirm gog can talk to Gmail:
  & "$env:USERPROFILE\bin\gog.exe" gmail labels list

3) Dry run (shows decisions, moves nothing):
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\gmail-openclaw-sort.ps1 -Max 200

4) Apply (actually moves emails):
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\gmail-openclaw-sort.ps1 -Max 200 -Apply


Full setup (do this in order)
=============================

Step 1) Install OpenClaw
------------------------
Open PowerShell and run:
  iwr -useb https://openclaw.ai/install.ps1 | iex

Verify:
  openclaw --version
  openclaw doctor

Start the gateway (leave this window open):
  openclaw gateway --port 18789

Verify in a second PowerShell window:
  openclaw status

Expected: “Gateway reachable” and a dashboard URL like:
  http://127.0.0.1:18789/

If it says ECONNREFUSED:
- the gateway isn’t running, or port 18789 is taken.

Find and kill whatever is using the port:
  netstat -ano | findstr :18789
  taskkill /PID <PID> /F
  openclaw gateway --port 18789


Step 2) Install gog.exe (Gmail tool)
------------------------------------
gog.exe is the tool that actually talks to Gmail.

Install Go + Git:
  winget install -e --id GoLang.Go
  winget install -e --id Git.Git

Build gog.exe:
  mkdir "%USERPROFILE%\bin"
  cd "%USERPROFILE%"
  git clone https://github.com/steipete/gogcli.git
  cd gogcli
  go build -o "%USERPROFILE%\bin\gog.exe" .\cmd\gog

Verify:
  powershell -NoProfile -Command "& `"$env:USERPROFILE\bin\gog.exe`" version"

Expected: a version like 0.12.x (dev is fine)


Step 3) Enable Gmail API + create OAuth Desktop credentials
-----------------------------------------------------------
This part is in Google Cloud Console.

1) Create/select a Google Cloud project
2) Enable Gmail API
3) Configure OAuth consent screen
   - Publishing status: Testing
   - Add your email under Test users
4) Create OAuth client:
   - Type: Desktop app
   - Download the JSON file (client_secret_*.json)

Do NOT upload client_secret_*.json anywhere. It’s a secret.


Step 4) Authenticate gog to Gmail (IMPORTANT: Gmail scopes)
----------------------------------------------------------
This is the #1 place people get stuck.

4A) Load the OAuth client JSON into gog

Get the exact filename:
  dir "$env:USERPROFILE\Downloads\client_secret*.json" | Select-Object -Expand FullName

Copy the full path it prints, then run:
  & "$env:USERPROFILE\bin\gog.exe" auth credentials "PASTE_FULL_PATH_HERE"

4B) Authorize Gmail access WITH Gmail scopes

Run (replace email):
  & "$env:USERPROFILE\bin\gog.exe" auth add yourgmail@gmail.com --services "gmail" --force-consent --verbose

This opens a browser page. Approve it.

If Gmail scopes are missing, Gmail commands fail with:
  Google API error (403 insufficientPermissions): insufficient authentication scopes

4C) Verify Gmail works:
  & "$env:USERPROFILE\bin\gog.exe" gmail labels list
  & "$env:USERPROFILE\bin\gog.exe" --json gmail search "in:inbox" --max 5

If those work, everything else works.

If it still complains about scopes, use a new token bucket name:
  & "$env:USERPROFILE\bin\gog.exe" auth add yourgmail@gmail.com --client "gmailfix" --services "gmail" --force-consent


Step 5) Create the Gmail labels
-------------------------------
Create labels in Gmail web:
Settings (gear) -> See all settings -> Labels -> Create new label

Default labels this script expects:
- Gaming
- Receipts
- Church
- Trips
- Personal life
- School
- Work
- Action

If different names are preferred, edit the script’s $allowed list to match exactly.


Step 6) Run the script
----------------------
Put gmail-openclaw-sort.ps1 in a folder like Downloads/Desktop.

IMPORTANT:
Running from C:\Windows\System32 will cause “file not found”.
Either cd into the folder, or use a full path.

Dry run (no changes):
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\gmail-openclaw-sort.ps1 -Max 200

Apply (moves email out of inbox):
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\gmail-openclaw-sort.ps1 -Max 200 -Apply

Expected output:
- A Decisions table (threadId / decision / reason)
- “Moving <threadId> -> <Label>” lines



Troubleshooting (common issues)
===============================

“The file does not exist”
-------------------------
The script is being run from the wrong folder.
Fix: cd into the script folder or use a full path.

Example:
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\Downloads\gmail-openclaw-sort.ps1" -Max 200 -Apply


Gmail error: invalid_grant
--------------------------
OAuth token is stale or system time is off.
Fix: re-auth:
  & "$env:USERPROFILE\bin\gog.exe" auth add yourgmail@gmail.com --services "gmail" --force-consent


Gmail error: 403 insufficientPermissions (scopes)
-------------------------------------------------
Gmail scopes weren’t granted.
Fix:
  & "$env:USERPROFILE\bin\gog.exe" auth add yourgmail@gmail.com --services "gmail" --force-consent --verbose


OpenClaw gateway unreachable (ECONNREFUSED)
-------------------------------------------
Start it:
  openclaw gateway --port 18789

If port is taken:
  netstat -ano | findstr :18789
  taskkill /PID <PID> /F
  openclaw gateway --port 18789

