# Requires PowerShell 7+
[CmdletBinding()]
param(
    [string[]] $Paths = @(
        ".\ru\tasker",
        ".\en\tasker"
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

        # Replace chat_id:<digits> anywhere (including multiline Str values).
        $newText = [regex]::Replace($text, '(?m)chat_id:\s*\d+', 'chat_id:<YOUR_TELEGRAM_CHAT_ID>')
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