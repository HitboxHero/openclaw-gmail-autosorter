OpenClaw Gmail Auto-Sorter
===========================================

What this is
------------
This is a Windows PowerShell script that helps you get your Gmail inbox under control.

It does two jobs:

1) "Brain" (OpenClaw)
   - OpenClaw reads a small summary of each email thread (from/subject/labels)
   - It decides the best label for each email based on rules you can edit

2) "Hands" (gog.exe)
   - gog.exe talks to Gmail (through the Gmail API + OAuth)
   - It applies the label OpenClaw chose
   - It removes the INBOX label, which archives the email (moves it out of your inbox)

Important idea: Gmail does not have real folders.
Labels are basically folders. Removing the INBOX label is how you "move it out of inbox."


What it can do
--------------
- Move most inbox emails into labels like:
  Gaming, Receipts, Church, Trips, Personal life, School, Work, Action
- Keep starred emails in the inbox (so you don’t lose stuff you intentionally flagged)
- Use an "Action" label to stop your inbox from getting clogged with:
  verification codes, security alerts, DocuSign, Drive share requests, buyer messages, domain alerts


What it does NOT do
-------------------
- It does not delete emails.
- It does not unsubscribe you.
- It does not reply to emails.
- It does not read full email bodies by default (it uses from/subject/labels and whatever gog includes).
- It does not run in the cloud. This is all local on your Windows PC.


You should NOT upload your .openclaw folder
-------------------------------------------
Do not put any of this on GitHub:
- C:\Users\YOURNAME\.openclaw\openclaw.json  (contains a gateway token)
- C:\Users\YOURNAME\.openclaw\credentials\   (OAuth/secret material)
- C:\Users\YOURNAME\.openclaw\agents\        (sessions/history)
- any client_secret_*.json from Google

The only safe thing to share is the script file:
- gmail-openclaw-sort.ps1


Requirements (what you need installed)
--------------------------------------
A) Windows
- Windows 10 or 11
- PowerShell (default is fine)

B) OpenClaw
- The AI brain and gateway

C) gog.exe (gogcli)
- A Gmail CLI tool that uses Gmail API + OAuth
- It can search mail, list labels, and modify labels

D) A Gmail account and Gmail API OAuth credentials


Step 1: Install OpenClaw
------------------------
Open PowerShell and run:

  iwr -useb https://openclaw.ai/install.ps1 | iex

Verify:

  openclaw --version
  openclaw doctor

Start the gateway (leave it running in this window):

  openclaw gateway --port 18789

In a second PowerShell window, verify reachability:

  openclaw status

If you see ECONNREFUSED or unreachable:
- Something else may be using port 18789
- Find PID:
    netstat -ano | findstr :18789
- Kill PID:
    taskkill /PID <PID> /F
- Start gateway again:
    openclaw gateway --port 18789


Step 2: Install gog.exe (gogcli)
--------------------------------
This is the Gmail “hands” tool.

One common Windows approach is building from source using Go.

Install prerequisites:

  winget install -e --id GoLang.Go
  winget install -e --id Git.Git

Build gog.exe:

  mkdir %USERPROFILE%\bin
  cd %USERPROFILE%
  git clone https://github.com/steipete/gogcli.git
  cd gogcli
  go build -o "%USERPROFILE%\bin\gog.exe" .\cmd\gog

Verify:

  & "$env:USERPROFILE\bin\gog.exe" version


Step 3: Enable Gmail API and create OAuth credentials
-----------------------------------------------------
You need a Google Cloud project and an OAuth Desktop App client.

High-level steps:
1) Google Cloud Console:
   - Create/select a project
   - Enable "Gmail API"
2) Create OAuth consent screen:
   - External is fine for personal use
   - Keep Publishing status as "Testing"
   - Add your Gmail address as a Test User
3) Create OAuth Client ID:
   - Application type: Desktop app
   - Download the JSON file (client_secret_*.json)

Important:
- Do NOT upload client_secret_*.json to GitHub.
- It is a secret file.


Step 4: Authenticate gog to your Gmail
--------------------------------------
Assuming your OAuth JSON downloaded to your Downloads folder:

  & "$env:USERPROFILE\bin\gog.exe" auth credentials "$env:USERPROFILE\Downloads\client_secret*.json"
  & "$env:USERPROFILE\bin\gog.exe" auth add yourgmail@gmail.com

Verify gog can see Gmail labels:

  & "$env:USERPROFILE\bin\gog.exe" gmail labels list

If you see labels like INBOX, IMPORTANT, etc, you’re good.


Step 5: Create the labels you want the bot to use
--------------------------------------------------
In Gmail (web):
- Settings (gear) -> See all settings -> Labels -> Create new label

Recommended labels (these match the default script):
- Gaming
- Receipts
- Church
- Trips
- Personal life
- School
- Work
- Action

If you want different names, you must edit the script’s $allowed list to match exactly.


Step 6: Put the script somewhere easy
-------------------------------------
Example locations:
- Desktop
- Documents
- Any folder you want

The script assumes:
- gog.exe is at: %USERPROFILE%\bin\gog.exe
If yours is different, edit this line in the script:
  $gog = "$env:USERPROFILE\bin\gog.exe"


How to run the script
---------------------
Dry run (no changes, prints decisions):

  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\gmail-openclaw-sort.ps1 -Max 200

Apply mode (actually moves email):

  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\gmail-openclaw-sort.ps1 -Max 200 -Apply

Meaning of flags:
- -Max 200        how many inbox threads to process per run
- -Apply          actually apply labels and remove INBOX
- -BrainBatch 30  how many threads to send to OpenClaw per prompt chunk
                 (Lower = more reliable on Windows; higher = faster but may hit length limits)


How “moving” works (important)
------------------------------
Gmail uses labels.
Inbox is also a label: INBOX.

To move something out of inbox:
- Add your label (Receipts, Work, etc)
- Remove INBOX

This script does exactly that:

  gog gmail labels modify <threadId> --add "<LABEL>" --remove INBOX


How the decisions work
----------------------
OpenClaw is told:

- Allowed decisions:
  Gaming, Receipts, Church, Trips, Personal life, School, Work, Action, KEEP_INBOX

- Starred emails stay in inbox:
  If a thread has STARRED in its labels, the script skips it.

- Action label is used for:
  verification codes, login/security alerts, DocuSign, Drive shares, buyer messages, domain alerts

- Receipts label is used for:
  bills, payments, invoices, shipping, deliveries, refunds, taxes, orders
  (Gaming purchases still go to Receipts)


Why BrainBatch exists (Windows limitation)
------------------------------------------
Windows has practical command-line length limits.
If you send too many threads to OpenClaw in one giant prompt, you can get errors like:
- "filename or extension is too long"

BrainBatch splits the work into chunks so it stays stable.


Troubleshooting
---------------
1) OpenClaw gateway unreachable (ECONNREFUSED)
- Start it:
    openclaw gateway --port 18789
- Check:
    openclaw status
- If port is busy, find/kill the PID:
    netstat -ano | findstr :18789
    taskkill /PID <PID> /F

2) gog works but OpenClaw fails with JSON parsing errors
- Lower BrainBatch:
    -BrainBatch 30
- The script includes marker extraction (BEGIN_JSON/END_JSON) and fallback parsing.

3) Script keeps everything in KEEP_INBOX
- Make sure the prompt does NOT treat IMPORTANT as “keep”
  (IMPORTANT is noisy; STARRED is intentional)
- If your inbox is full of IMPORTANT mail, you still want it to be classified and moved.

4) Labels don’t apply / gog errors
- Confirm the label name exists in Gmail exactly:
    & "$env:USERPROFILE\bin\gog.exe" gmail labels list
- Confirm your OAuth auth is still valid:
    & "$env:USERPROFILE\bin\gog.exe" auth status

5) Nothing happens / nothing to classify
- This can occur if everything left in inbox is STARRED (by design).
- Check:
    & "$env:USERPROFILE\bin\gog.exe" gmail search "in:inbox is:starred" --max 20


Safety notes
------------
- This script does not delete mail.
- It moves items out of inbox by removing INBOX.
- Start with dry run.
- Use small Max values until you trust it.
- Keep STARRED protected so you have a manual “do not move” button.
