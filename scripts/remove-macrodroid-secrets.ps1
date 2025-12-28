# Requires PowerShell 7+

param(
    [string[]]$Paths = @(
        ".\assets\macrodroid\ru",
        ".\assets\macrodroid\en"
    )
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ---- Counters (Decimal for math, string for JSON) ----------------------------

[decimal]$MacroGuidCounter = -1700000000000000000
[decimal]$SiguidCounter    = -1600000000000000000

# ---- Helpers ----------------------------------------------------------------

function Get-JsonFiles {
    param([string]$Root)

    if (-not (Test-Path $Root)) {
        Write-Warning "Path not found: $Root"
        return @()
    }

    Get-ChildItem -Path $Root -Recurse -File -Filter "*.macro"
}

function Backup-File {
    param([string]$FilePath)

    $backupPath = "$FilePath.bak"
    if (-not (Test-Path $backupPath)) {
        Copy-Item -Path $FilePath -Destination $backupPath
    }
}

# ---- Processing -------------------------------------------------------------

foreach ($path in $Paths) {

    foreach ($file in Get-JsonFiles -Root $path) {

        Backup-File -FilePath $file.FullName

        $json = Get-Content $file.FullName -Raw | ConvertFrom-Json -Depth 100

        if (-not $json.macro) {
            Write-Warning "Skipping (no macro object): $($file.FullName)"
            continue
        }

        $macro = $json.macro

        # ---- macro.m_GUID (STRING) -------------------------------------------

        $macro.m_name = "Example $($macro.m_name)"

        # ---- macro.m_GUID (STRING) -------------------------------------------

        $macro.m_GUID = $MacroGuidCounter.ToString("0")
        $MacroGuidCounter--

        # ---- lastEditedTimestamp & localVariables ----------------------------

        # $macro.lastEditedTimestamp = 0
        $macro.localVariables = @()

        # ---- m_actionList ----------------------------------------------------

        if ($macro.m_actionList) {
            foreach ($action in $macro.m_actionList) {

                if ($action.PSObject.Properties.Name -contains 'm_SIGUID') {
                    $action.m_SIGUID = $SiguidCounter.ToString("0")
                    $SiguidCounter--
                }

                if ($action.PSObject.Properties.Name -contains 'requestConfig') {
                    $rc = $action.requestConfig

                    if ($rc.PSObject.Properties.Name -contains 'headerParams') {
                        foreach ($param in $rc.headerParams) {
                            if ($param.paramName -eq 'x-n8n-device-relay') {
                                $param.paramValue = '<YOUR_CUSTOM_TOKEN_FOR_DEVICE_HERE>'
                            }
                        }
                    }

                    if ($rc.PSObject.Properties.Name -contains 'queryParams') {
                        foreach ($param in $rc.queryParams) {
                            if ($param.paramName -eq 'chat_id') {
                                $param.paramValue = '<YOUR_TOKEN_HERE>'
                            }
                        }
                    }

                    if ($rc.PSObject.Properties.Name -contains 'urlToOpen') {
                        $rc.urlToOpen =
                            'https://YOUR-N8N-INSTANCE-DOMAIN.tld/webhook/device-relay'
                    }
                }

                if ($action.PSObject.Properties.Name -contains 'm_variable') {
                    # m_variable is an Object, not an array, and we need to to access m_stringValue inside it, if present
                    $var = $action.m_variable
                    if ($var.PSObject.Properties.Name -contains 'm_stringValue') {
                        $var.m_stringValue = ""
                    }
                }
            }
        }

        # ---- m_triggerList ---------------------------------------------------

        if ($macro.m_triggerList) {
            foreach ($trigger in $macro.m_triggerList) {
                if ($trigger.PSObject.Properties.Name -contains 'm_SIGUID') {
                    $trigger.m_SIGUID = $SiguidCounter.ToString("0")
                    $SiguidCounter--
                }
            }
        }

        # ---- Save ------------------------------------------------------------

        $json |
            ConvertTo-Json -Depth 100 |
            Set-Content -Path $file.FullName -Encoding UTF8
    }
}

Write-Host "Done."
