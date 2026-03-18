param(
  [int]$Max = 200,
  [int]$SessionId = 9001,
  [switch]$Apply,
  [int]$BrainBatch = 60
)

$ErrorActionPreference = "Stop"

$gog = "$env:USERPROFILE\bin\gog.exe"
if (-not (Test-Path $gog)) { throw "gog.exe not found at $gog" }

# --- helper: gog JSON can be array or object wrapper
function Get-ThreadsFromGogJson($raw) {
  $parsed = $raw | ConvertFrom-Json
  if ($parsed -is [System.Array]) { return $parsed }
  if ($null -ne $parsed.threads) { return $parsed.threads }
  if ($null -ne $parsed.items) { return $parsed.items }
  throw "Unknown gog JSON shape"
}

Write-Host "Fetching inbox threads..." -ForegroundColor Cyan
$raw = & $gog --json gmail search "in:inbox" --max $Max 2>&1 | Out-String
try { $threadList = Get-ThreadsFromGogJson $raw } catch { throw "gog did not return usable JSON. Raw:`n$raw" }

if (-not $threadList -or $threadList.Count -eq 0) {
  Write-Host "No inbox threads found." -ForegroundColor Yellow
  exit 0
}

# Allowed label decisions (Action added)
$allowed = @("Gaming","Receipts","Church","Trips","Personal life","School","Work","Action","KEEP_INBOX")

# Build input lines (skip IMPORTANT/STARRED always)
$items = @()
foreach ($t in $threadList) {
  $labels = @()
  if ($t.labels) { $labels = $t.labels }

  if ($labels -contains "STARRED") { continue }

  $id = [string]$t.id
  if ([string]::IsNullOrWhiteSpace($id)) { continue }

  $from = ([string]$t.from) -replace '[\r\n"]',' '
  $subject = ([string]$t.subject) -replace '[\r\n"]',' '
  $lab = (($labels -join ",")) -replace '[\r\n"]',' '

  $items += "threadId=$id | from=$from | subject=$subject | labels=$lab"
}

if ($items.Count -eq 0) {
  Write-Host "Nothing to classify (everything was IMPORTANT/STARRED or empty)." -ForegroundColor Yellow
  exit 0
}

Write-Host ("Asking OpenClaw brain to classify {0} threads..." -f $items.Count) -ForegroundColor Cyan

# Prime the session so it doesn't do the intro chat
$null = & openclaw agent --session-id $SessionId --message "Classifier mode. No small talk. Output only what I request." 2>&1 | Out-String

function Classify-Chunk($chunkLines) {
  $prompt = @"
You are my Gmail triage brain. Output MUST be strictly between markers.

Allowed decisions (exact):
Gaming, Receipts, Church, Trips, Personal life, School, Work, Action, KEEP_INBOX

Hard bans:
- NEVER choose Notes

Goal:
- Get Inbox under 40.
- KEEP_INBOX only if it truly needs my eyes today.
- For anything that needs action but can be handled later, use Action.

Rules:
- IMPORTANT is noisy; DO NOT use it as a keep signal.
- If labels contain STARRED -> KEEP_INBOX

Route these to Action (NOT KEEP_INBOX):
- verification/login codes, new device sign-in, password resets
- account/security alerts (credit alert, dark web alert, suspicious login)
- DocuSign sign/complete/review packets
- Google Drive share/access requests
- buyer messages needing response
- domain pending delete/suspended/renew now

Other rules:
- Bills/money/invoice/statement/payment/subscription/order/shipping/delivery/refund/tax -> Receipts
- Gaming receipts/orders -> Receipts
- Gaming news/content -> Gaming
- PriceCharting -> Gaming (override)
- Church -> Church
- Travel -> Trips
- School -> School
- Work/job alerts/recruiting/career -> Work
- Family/personal/medical/kid -> Personal life
- If unsure -> Action

Input threads (one per line):
$($chunkLines -join "`n")

OUTPUT REQUIREMENTS:
Print exactly:
BEGIN_JSON
[{"threadId":"...","decision":"...","reason":"..."}]
END_JSON
No other text.
"@

  $resp = & openclaw agent --session-id $SessionId --message $prompt 2>&1 | Out-String
  # Try to extract JSON from markers first (use LAST occurrence if it duplicated)
  $begin = $resp.LastIndexOf("BEGIN_JSON")
  $end = $resp.LastIndexOf("END_JSON")

  $jsonText = ""
  if ($begin -ge 0 -and $end -ge 0 -and $end -gt $begin) {
    $jsonText = $resp.Substring($begin + "BEGIN_JSON".Length, $end - ($begin + "BEGIN_JSON".Length)).Trim()
  } else {
    # Fallback: try to pull the last JSON array anywhere in the output
    $jsonText = $resp
  }

  # Normalize weird line breaks inside JSON strings (PowerShell can handle them if they're actual \n,
  # but the CLI sometimes inserts literal newlines mid-string)
  $jsonText = ($jsonText -replace "\r", "")

  # Fallback extractor: grab the LAST [...] block (most likely the array we want)
  $m = [regex]::Matches($jsonText, "\[[\s\S]*\]")
  if ($m.Count -gt 0) {
    $jsonText = $m[$m.Count - 1].Value.Trim()
  }

  try {
    return ($jsonText | ConvertFrom-Json)
  } catch {
    Write-Host "JSON parse failed. Extracted JSON was:" -ForegroundColor Red
    Write-Host $jsonText
    throw
  }

}

# Chunk classification so Windows doesn't hit command length limits
$allDecisions = @()
for ($i = 0; $i -lt $items.Count; $i += $BrainBatch) {
  $chunk = $items[$i..([Math]::Min($i + $BrainBatch - 1, $items.Count - 1))]
  $allDecisions += Classify-Chunk $chunk
}

Write-Host ""
Write-Host "Decisions:" -ForegroundColor Green
$allDecisions | Format-Table threadId, decision, reason -AutoSize

if (-not $Apply) {
  Write-Host ""
  Write-Host "DRY RUN complete. To actually move mail, rerun with -Apply" -ForegroundColor Yellow
  exit 0
}

Write-Host ""
Write-Host "Applying changes (add label + remove INBOX)..." -ForegroundColor Cyan

foreach ($d in $allDecisions) {
  $threadId = [string]$d.threadId
  $decision = [string]$d.decision

  if ([string]::IsNullOrWhiteSpace($threadId)) { continue }

  if ($allowed -notcontains $decision) {
    Write-Host ("Skipping {0} - invalid decision '{1}'" -f $threadId, $decision) -ForegroundColor Yellow
    continue
  }

  if ($decision -eq "KEEP_INBOX") {
    Write-Host ("Keeping in inbox: {0}" -f $threadId) -ForegroundColor DarkGray
    continue
  }

  Write-Host ("Moving {0} -> {1}" -f $threadId, $decision) -ForegroundColor White
  & $gog gmail labels modify $threadId --add "$decision" --remove INBOX | Out-Null
}

Write-Host ""
Write-Host "Done." -ForegroundColor Green
