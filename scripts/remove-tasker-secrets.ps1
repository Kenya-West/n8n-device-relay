# Requires PowerShell 7+
[CmdletBinding()]
param(
    [string[]] $Paths = @(
        ".\assets\tasker\ru",
        ".\assets\tasker\en"
    ),

    # Defaults to true because sr="profXX"/sr="taskYY" correlates with IDs.
    [bool] $RewriteSrAttributes = $true
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Counters
[int] $ProfileIdCounter = 99999   # decrease by 1 per processed file
[int] $TaskIdCounter    = 99899   # decrease by 1 per processed task

function Get-TaskerProfileFiles {
    param([Parameter(Mandatory)] [string] $Root)

    if (-not (Test-Path -LiteralPath $Root)) {
        Write-Warning "Path not found: $Root"
        return @()
    }

    Get-ChildItem -LiteralPath $Root -Recurse -File -Filter "*.prf"
}

function Backup-File {
    param([Parameter(Mandatory)] [string] $FilePath)

    $backupPath = "$FilePath.bak"
    if (-not (Test-Path -LiteralPath $backupPath)) {
        Copy-Item -LiteralPath $FilePath -Destination $backupPath
    }
}

function Ensure-ExamplePrefix {
    param([string] $Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return $Value }
    if ($Value -match '^\s*Example\b') { return $Value }
    return "Example $Value"
}

function Prefix-AllNameNodes {
    param([Parameter(Mandatory)] [System.Xml.XmlDocument] $Doc)

    $nameNodes = $Doc.SelectNodes("//nme")
    if (-not $nameNodes) { return }

    foreach ($nme in $nameNodes) {
        if ($nme -isnot [System.Xml.XmlElement]) { continue }
        $nme.InnerText = Ensure-ExamplePrefix $nme.InnerText
    }
}

function Get-ChildElementText {
    param(
        [Parameter(Mandatory)] [System.Xml.XmlElement] $Parent,
        [Parameter(Mandatory)] [string] $ChildName
    )
    $node = $Parent.SelectSingleNode("./$ChildName")
    if ($null -eq $node) { return $null }
    return $node.InnerText
}

function Set-ChildElementText {
    param(
        [Parameter(Mandatory)] [System.Xml.XmlElement] $Parent,
        [Parameter(Mandatory)] [string] $ChildName,
        [Parameter(Mandatory)] [string] $Value
    )
    $node = $Parent.SelectSingleNode("./$ChildName")
    if ($null -eq $node) { return }
    $node.InnerText = $Value
}

function Try-ParseJsonLoosely {
    param(
        [Parameter(Mandatory)] [string] $Text,
        [ref] $Parsed
    )

    # Tasker exports often embed JSON with placeholders like %BATT or %LOCSPD.
    # Those placeholders can appear unquoted (number-like fields) which breaks strict JSON parsing.
    # We sanitize *only for parsing*; we do not use the sanitized text for output.

    $candidate = $Text.Trim()
    if (-not ($candidate.StartsWith('{') -and $candidate.EndsWith('}'))) {
        return $false
    }

    $sanitized = $candidate
    # Replace any unquoted %VAR tokens with 0 so ConvertFrom-Json can parse.
    # We consider it "unquoted" if it's not immediately preceded by a double quote.
    $sanitized = [regex]::Replace($sanitized, '(?<!")%[A-Za-z_][A-Za-z0-9_]*', '0')

    try {
        $Parsed.Value = $sanitized | ConvertFrom-Json -AsHashtable -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

function Patch-DeviceIdInEmbeddedJson {
    param(
        [Parameter(Mandatory)] [string] $Text,
        [Parameter(Mandatory)] [string] $ReplacementDeviceId
    )

    $parsed = $null
    if (-not (Try-ParseJsonLoosely -Text $Text -Parsed ([ref] $parsed))) {
        return $Text
    }

    if ($parsed -isnot [hashtable]) {
        return $Text
    }

    if (-not $parsed.ContainsKey('device')) {
        return $Text
    }

    $device = $parsed['device']
    if ($device -isnot [hashtable] -or -not $device.ContainsKey('id')) {
        return $Text
    }

    # We only replace the device.id value in the original JSON string, preserving all Tasker placeholders.
    # Match inside the device object: "device": { ... "id": "..." ... }
    return [regex]::Replace(
        $Text,
        '(?s)("device"\s*:\s*\{.*?"id"\s*:\s*")[^"]*(")',
        ('$1' + [regex]::Escape($ReplacementDeviceId).Replace('\\','\\\\') + '$2')
    )
}

function Scrub-TelegramStrings {
    param([Parameter(Mandatory)] [System.Xml.XmlDocument] $Doc)

    $strNodes = $Doc.SelectNodes("//Str")
    if (-not $strNodes) { return }

    foreach ($str in $strNodes) {
        if ($str -isnot [System.Xml.XmlElement]) { continue }

        $text = $str.InnerText
        if ([string]::IsNullOrEmpty($text)) { continue }

        # Replace full URL strings that start with Telegram bot API base.
        if ($text -match '^https://api\.telegram\.org/bot' -or $text -match '^https://n8n') {
            $str.InnerText = "https://%YOUR_N8N_DOMAIN/webhook/device-relay"
            continue
        }

        # Replace x-n8n-device-relay:<token> anywhere.
        if ($text -match 'x-n8n-device-relay\:.+') {
            $str.InnerText = "x-n8n-device-relay:%YOUR_TOKEN_HERE"
            continue
        }

        # Replace chat_id:<digits> anywhere (including multiline Str values).
        $newText = [regex]::Replace($text, '(?m)chat_id:\s*\d+', 'chat_id:<YOUR_TELEGRAM_CHAT_ID>')

        # Replace Tasker JSON device.id value with a non-sensitive placeholder.
        # This is JSON-aware: it only applies when the Str looks like JSON and parses to an object with device.id.
        $newText = Patch-DeviceIdInEmbeddedJson -Text $newText -ReplacementDeviceId 'your-device-name'

        if ($newText -ne $text) {
            $str.InnerText = $newText
        }
    }
}

[int] $filesProcessed = 0
[int] $tasksProcessed = 0
[int] $profilesTouched = 0

foreach ($path in $Paths) {
    foreach ($file in Get-TaskerProfileFiles -Root $path) {
        Backup-File -FilePath $file.FullName

        $raw = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8

        $doc = [System.Xml.XmlDocument]::new()
        $doc.PreserveWhitespace = $true
        $doc.LoadXml($raw)

        # Note: <code> nodes in Tasker exports represent action/event type codes.
        # They are not unique IDs and should not be rewritten (rewriting them can break the profile).

        # Prefix *any* <nme> in the file (Profile/Task/etc.)
        Prefix-AllNameNodes -Doc $doc

        # Build task ID mapping old->new for this file
        $taskIdMap = @{}

        $taskNodes = $doc.SelectNodes("/TaskerData/Task")
        if ($taskNodes) {
            foreach ($task in $taskNodes) {
                if ($task -isnot [System.Xml.XmlElement]) { continue }

                $oldTaskIdText = Get-ChildElementText -Parent $task -ChildName "id"
                [int] $oldTaskId = 0
                if (-not [int]::TryParse($oldTaskIdText, [ref]$oldTaskId)) { continue }

                $newTaskId = $TaskIdCounter
                $TaskIdCounter--
                $tasksProcessed++

                $taskIdMap[$oldTaskId] = $newTaskId

                Set-ChildElementText -Parent $task -ChildName "id" -Value ($newTaskId.ToString())

                if ($RewriteSrAttributes) {
                    $task.SetAttribute("sr", "task$newTaskId")
                }
            }
        }

        # Profile ID is "per processed file" per your requirement
        $newProfileIdThisFile = $ProfileIdCounter
        $ProfileIdCounter--
        $filesProcessed++

        $profileNodes = $doc.SelectNodes("/TaskerData/Profile")
        if ($profileNodes) {
            foreach ($profile in $profileNodes) {
                if ($profile -isnot [System.Xml.XmlElement]) { continue }

                $profilesTouched++

                Set-ChildElementText -Parent $profile -ChildName "id" -Value ($newProfileIdThisFile.ToString())

                # Rewrite any midN elements to new task IDs (mid0, mid1, ...)
                foreach ($child in @($profile.ChildNodes)) {
                    if ($child -isnot [System.Xml.XmlElement]) { continue }
                    if ($child.Name -match '^mid\d+$') {
                        [int] $oldMidTaskId = 0
                        if ([int]::TryParse($child.InnerText, [ref]$oldMidTaskId)) {
                            if ($taskIdMap.ContainsKey($oldMidTaskId)) {
                                $child.InnerText = $taskIdMap[$oldMidTaskId].ToString()
                            }
                        }
                    }
                }

                if ($RewriteSrAttributes) {
                    $profile.SetAttribute("sr", "prof$newProfileIdThisFile")
                }
            }
        }

        # Scrub Telegram secrets in Str values (URL + chat_id).
        Scrub-TelegramStrings -Doc $doc

        # Save without XML declaration, UTF-8 (no BOM)
        $settings = [System.Xml.XmlWriterSettings]::new()
        $settings.OmitXmlDeclaration = $true
        $settings.Encoding = [System.Text.UTF8Encoding]::new($false)
        $settings.NewLineHandling = [System.Xml.NewLineHandling]::None

        $writer = [System.Xml.XmlWriter]::Create($file.FullName, $settings)
        try {
            $doc.Save($writer)
        } finally {
            $writer.Dispose()
        }
    }
}

Write-Host "Done."
Write-Host "Files processed:  $filesProcessed"
Write-Host "Profiles touched: $profilesTouched"
Write-Host "Tasks processed:  $tasksProcessed"