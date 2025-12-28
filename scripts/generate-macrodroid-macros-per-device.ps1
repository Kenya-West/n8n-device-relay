#!/usr/bin/env pwsh

[CmdletBinding()]
param(
	[Parameter(Mandatory = $false)]
	[string] $DeviceListPath,

	[Parameter(Mandatory = $false)]
	[string] $AssetsRoot = (Join-Path -Path $PSScriptRoot -ChildPath '..\assets\macrodroid'),

	[Parameter(Mandatory = $false)]
	[string] $OutputRoot = (Join-Path -Path $PSScriptRoot -ChildPath 'devices'),

	[Parameter(Mandatory = $false)]
	[string[]] $Languages = @('ru', 'en')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Normalize paths early to avoid issues with '..' segments when computing relative paths.
$AssetsRoot = [System.IO.Path]::GetFullPath($AssetsRoot)
$OutputRoot = [System.IO.Path]::GetFullPath($OutputRoot)

function Normalize-Text {
	param([AllowNull()][string] $Value)
	if ($null -eq $Value) { return '' }
	return $Value.Trim().ToLowerInvariant()
}

function Test-HasProperty {
	param(
		[Parameter(Mandatory = $true)] $Object,
		[Parameter(Mandatory = $true)][string] $Name
	)
	if ($null -eq $Object) { return $false }
	return ($Object.PSObject.Properties.Match($Name).Count -gt 0)
}

function Get-OptionalPropertyValue {
	param(
		[Parameter(Mandatory = $true)] $Object,
		[Parameter(Mandatory = $true)][string] $Name
	)
	if (Test-HasProperty -Object $Object -Name $Name) {
		return $Object.$Name
	}
	return $null
}

function Set-PropertyIfExists {
	param(
		[Parameter(Mandatory = $true)] $Object,
		[Parameter(Mandatory = $true)][string] $Name,
		[Parameter(Mandatory = $true)] $Value
	)
	if (Test-HasProperty -Object $Object -Name $Name) {
		$Object.$Name = $Value
		return $true
	}
	return $false
}

function New-NegativeSeed {
	param(
		[Parameter(Mandatory = $true)][long] $MinInclusive,
		[Parameter(Mandatory = $true)][long] $MaxInclusive
	)

	if ($MinInclusive -gt $MaxInclusive) {
		throw "Invalid range: MinInclusive must be <= MaxInclusive. Got $MinInclusive..$MaxInclusive"
	}

	# Get-Random supports Int32 by default; use NextInt64 in .NET for safe 64-bit range.
	$rng = [System.Random]::new()
	$span = [decimal]($MaxInclusive - $MinInclusive + 1)
	if ($span -le 0) {
		# Overflow or invalid span.
		throw "Invalid range span for 64-bit seed generation. Got span=$span"
	}

	# Sample a double in [0,1) then map into the range.
	$offset = [long][math]::Floor($rng.NextDouble() * [double]$span)
	return ($MinInclusive + $offset)
}

function Sanitize-PathSegment {
	param([Parameter(Mandatory = $true)][string] $Value)
	$segment = $Value.Trim()
	if ([string]::IsNullOrWhiteSpace($segment)) { $segment = 'device' }
	# Replace characters illegal on Windows file systems.
	$segment = [regex]::Replace($segment, '[\\/:*?"<>|]', '_')
	$segment = $segment.TrimEnd('.')
	if ([string]::IsNullOrWhiteSpace($segment)) { $segment = 'device' }
	return $segment
}

function Resolve-DeviceListPath {
	param([AllowNull()][string] $Path)

	if (-not [string]::IsNullOrWhiteSpace($Path)) {
		$resolved = Resolve-Path -LiteralPath $Path -ErrorAction Stop
		return $resolved.Path
	}

	$candidates = @(
		(Join-Path -Path $PSScriptRoot -ChildPath 'device-list.json')
	)

	foreach ($candidate in $candidates) {
		if (Test-Path -LiteralPath $candidate) {
			return (Resolve-Path -LiteralPath $candidate).Path
		}
	}

	throw "Device list JSON not found. Provide -DeviceListPath, or add one of: device-list.json, device-list.example.json, device-list-minimal.example.json in $PSScriptRoot"
}

function Read-JsonFile {
	param([Parameter(Mandatory = $true)][string] $Path)
	try {
		$raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
		return $raw | ConvertFrom-Json -Depth 100
	} catch {
		throw "Failed to read/parse JSON from '$Path': $($_.Exception.Message)"
	}
}

function Try-EnsureDirectory {
	param([Parameter(Mandatory = $true)][string] $Path)
	try {
		if (-not (Test-Path -LiteralPath $Path)) {
			New-Item -ItemType Directory -Path $Path -Force | Out-Null
		}
		return $true
	} catch {
		Write-Warning "Cannot create directory '$Path': $($_.Exception.Message)"
		return $false
	}
}

function Update-MacroObject {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $true)] $MacroObj,
		[Parameter(Mandatory = $true)][string] $DeviceIdentifier,
		[Parameter(Mandatory = $true)][string] $DeviceToken,
		[Parameter(Mandatory = $true)][string] $DeviceEndpoint,
		[Parameter(Mandatory = $true)][ref] $GuidSeed,
		[Parameter(Mandatory = $true)][ref] $SiGuidSeed,
		[Parameter(Mandatory = $true)][string] $MacroRelativePath
	)

	$macro = Get-OptionalPropertyValue -Object $MacroObj -Name 'macro'
	if ($null -eq $macro) {
		Write-Warning "[$MacroRelativePath] Missing 'macro' root property; skipping updates"
		return $MacroObj
	}

	# m_GUID: one per macro file
	if (Set-PropertyIfExists -Object $macro -Name 'm_GUID' -Value ([string]$GuidSeed.Value)) {
		$GuidSeed.Value = $GuidSeed.Value - 1
	}
	else {
		Write-Warning "[$MacroRelativePath] 'macro.m_GUID' not found; not replaced"
	}

	$foundHeaderToken = $false
	$foundEndpoint = $false
	$foundSiGuid = 0
	$foundDeviceIdInSerializedJson = 0

	$innerDeviceIdPattern = '(?s)("device"\s*:\s*\{.*?"id"\s*:\s*")(.*?)(")'
	$safeIdentifierForInnerJson = ($DeviceIdentifier -replace '\\', '\\\\' -replace '"', '\\"')

	function Replace-InnerDeviceId {
		param([Parameter(Mandatory = $true)][string] $Text)
		if ($Text -notmatch $innerDeviceIdPattern) { return $null }
		return [regex]::Replace(
			$Text,
			$innerDeviceIdPattern,
			{
				param($m)
				return $m.Groups[1].Value + $safeIdentifierForInnerJson + $m.Groups[3].Value
			},
			[System.Text.RegularExpressions.RegexOptions]::Singleline
		)
	}

	$actions = Get-OptionalPropertyValue -Object $macro -Name 'm_actionList'
	if ($null -eq $actions) {
		Write-Warning "[$MacroRelativePath] 'macro.m_actionList' not found; no action updates applied"
		return $MacroObj
	}

	foreach ($action in $actions) {
		# m_SIGUID: decrement by 1 for each action item met
		if (Set-PropertyIfExists -Object $action -Name 'm_SIGUID' -Value ([string]$SiGuidSeed.Value)) {
			$SiGuidSeed.Value = $SiGuidSeed.Value - 1
			$foundSiGuid++
		} else {
			$classType = Get-OptionalPropertyValue -Object $action -Name 'm_classType'
			Write-Warning "[$MacroRelativePath] Action item missing 'm_SIGUID' (classType=$classType)"
		}

		# requestConfig replacements
		$requestConfig = Get-OptionalPropertyValue -Object $action -Name 'requestConfig'
		if ($null -ne $requestConfig) {
			$contentBodyText = Get-OptionalPropertyValue -Object $requestConfig -Name 'contentBodyText'
			if ($contentBodyText -is [string] -and -not [string]::IsNullOrWhiteSpace([string]$contentBodyText)) {
				$replacedBody = Replace-InnerDeviceId -Text ([string]$contentBodyText)
				if ($null -ne $replacedBody) {
					[void](Set-PropertyIfExists -Object $requestConfig -Name 'contentBodyText' -Value $replacedBody)
					$foundDeviceIdInSerializedJson++
				}
			}

			if (Set-PropertyIfExists -Object $requestConfig -Name 'urlToOpen' -Value $DeviceEndpoint) {
				$foundEndpoint = $true
			}

			$headerParams = Get-OptionalPropertyValue -Object $requestConfig -Name 'headerParams'
			if ($null -ne $headerParams) {
				foreach ($hp in $headerParams) {
					if ($null -eq $hp) { continue }
					$paramName = Get-OptionalPropertyValue -Object $hp -Name 'paramName'
					if ((Normalize-Text ([string]$paramName)) -eq 'x-n8n-device-relay') {
						if (Set-PropertyIfExists -Object $hp -Name 'paramValue' -Value $DeviceToken) {
							$foundHeaderToken = $true
						} else {
							Write-Warning "[$MacroRelativePath] headerParams entry with paramName='x-n8n-device-relay' has no 'paramValue' to update"
						}
					}
				}
			}
		}

		# Embedded serialized JSON string replacement in m_newStringValue
		$mNewStringValue = Get-OptionalPropertyValue -Object $action -Name 'm_newStringValue'
		if ($null -ne $mNewStringValue -and ($mNewStringValue -is [string]) -and -not [string]::IsNullOrWhiteSpace([string]$mNewStringValue)) {
			$replacedNewString = Replace-InnerDeviceId -Text ([string]$mNewStringValue)
			if ($null -ne $replacedNewString) {
				[void](Set-PropertyIfExists -Object $action -Name 'm_newStringValue' -Value $replacedNewString)
				$foundDeviceIdInSerializedJson++
			}
		}
	}

    $triggers = Get-OptionalPropertyValue -Object $macro -Name 'm_triggerList'
	if ($null -eq $triggers) {
		Write-Warning "[$MacroRelativePath] 'macro.m_triggerList' not found; no trigger updates applied"
		return $MacroObj
	}

    foreach ($trigger in $triggers) {
		# m_SIGUID: decrement by 1 for each trigger item met
		if (Set-PropertyIfExists -Object $trigger -Name 'm_SIGUID' -Value ([string]$SiGuidSeed.Value)) {
			$SiGuidSeed.Value = $SiGuidSeed.Value - 1
			$foundSiGuid++
		} else {
			$classType = Get-OptionalPropertyValue -Object $trigger -Name 'm_classType'
			Write-Warning "[$MacroRelativePath] Trigger item missing 'm_SIGUID' (classType=$classType)"
		}
	}

	if (-not $foundHeaderToken) {
		Write-Warning "[$MacroRelativePath] Header token not replaced (no requestConfig.headerParams with paramName='x-n8n-device-relay' found)"
	}
	if (-not $foundEndpoint) {
		Write-Warning "[$MacroRelativePath] Endpoint not replaced (no requestConfig.urlToOpen found)"
	}
	if ($foundSiGuid -eq 0) {
		Write-Warning "[$MacroRelativePath] No m_SIGUID values found under macro.m_actionList"
	}
	if ($foundDeviceIdInSerializedJson -eq 0) {
		Write-Warning "[$MacroRelativePath] Device identifier not replaced in any m_newStringValue (no serialized device.id match found)"
	}

	return $MacroObj
}

try {
	$deviceListResolved = Resolve-DeviceListPath -Path $DeviceListPath
	Write-Verbose "Using device list: $deviceListResolved"
	$deviceList = Read-JsonFile -Path $deviceListResolved

	if ($null -eq $deviceList.devices -or -not ($deviceList.devices -is [System.Collections.IEnumerable])) {
		throw "Device list JSON must have a top-level 'devices' array"
	}

	$devicesAll = @($deviceList.devices)
	$devices = @(
		foreach ($d in $devicesAll) {
			if ($null -eq $d) { continue }
			$typeNorm = Normalize-Text $d.type
			$appNorm = Normalize-Text $d.app
			if ($typeNorm -eq 'android' -and $appNorm -eq 'macrodroid') { $d }
		}
	)

	if ($devices.Count -eq 0) {
		Write-Warning "No devices matched filter: type='android' and app='macrodroid'"
		return
	}

	if (-not (Try-EnsureDirectory -Path $OutputRoot)) {
		throw "Cannot access output root: $OutputRoot"
	}

	foreach ($device in $devices) {
		$identifier = [string](Get-OptionalPropertyValue -Object $device -Name 'identifier')
		$token = [string](Get-OptionalPropertyValue -Object $device -Name 'token')
		$endpoint = [string](Get-OptionalPropertyValue -Object $device -Name 'endpoint')

		if ([string]::IsNullOrWhiteSpace($identifier)) {
			Write-Warning "Skipping device with missing 'identifier'"
			continue
		}
		if ([string]::IsNullOrWhiteSpace($token)) {
			Write-Warning "Skipping device '$identifier' with missing 'token'"
			continue
		}
		if ([string]::IsNullOrWhiteSpace($endpoint)) {
			Write-Warning "Skipping device '$identifier' with missing 'endpoint'"
			continue
		}

		$nameValue = Get-OptionalPropertyValue -Object $device -Name 'name'
		$deviceNameRaw = if (-not [string]::IsNullOrWhiteSpace([string]$nameValue)) { [string]$nameValue } else { $identifier }
		$deviceFolderName = Sanitize-PathSegment -Value $deviceNameRaw
		$deviceOutRoot = Join-Path -Path $OutputRoot -ChildPath $deviceFolderName

		if (-not (Try-EnsureDirectory -Path $deviceOutRoot)) {
			Write-Warning "Skipping device '$identifier' because output directory is not writable: $deviceOutRoot"
			continue
		}

		$guidSeed = 0L
		$siGuidSeed = 0L
		$seedMin = -2000000000000000000L
		$seedMax = -1000000000000000000L

		try {
			$seedGuidValue = Get-OptionalPropertyValue -Object $device -Name 'seedGuid'
			if ($null -ne $seedGuidValue -and -not [string]::IsNullOrWhiteSpace([string]$seedGuidValue)) {
				$guidSeed = [long]$seedGuidValue
			} else {
				$guidSeed = New-NegativeSeed -MinInclusive $seedMin -MaxInclusive $seedMax
			}

			$seedSiGuidValue = Get-OptionalPropertyValue -Object $device -Name 'seedSiGuid'
			if ($null -ne $seedSiGuidValue -and -not [string]::IsNullOrWhiteSpace([string]$seedSiGuidValue)) {
				$siGuidSeed = [long]$seedSiGuidValue
			} else {
				$siGuidSeed = New-NegativeSeed -MinInclusive $seedMin -MaxInclusive $seedMax
			}
		} catch {
			Write-Warning "Skipping device '$identifier' due to invalid seedGuid/seedSiGuid: $($_.Exception.Message)"
			continue
		}

		foreach ($lang in $Languages) {
			$langNorm = Normalize-Text $lang
			if ([string]::IsNullOrWhiteSpace($langNorm)) { continue }

			$langAssetsRoot = Join-Path -Path $AssetsRoot -ChildPath $langNorm
			if (-not (Test-Path -LiteralPath $langAssetsRoot)) {
				Write-Warning "Assets language folder not found, skipping: $langAssetsRoot"
				continue
			}

			$langAssetsRootFull = $langAssetsRoot
			try {
				$langAssetsRootFull = (Resolve-Path -LiteralPath $langAssetsRoot -ErrorAction Stop).Path
			} catch {
				# If Resolve-Path fails (permissions/IO), keep full path but still try Get-ChildItem.
				$langAssetsRootFull = [System.IO.Path]::GetFullPath($langAssetsRoot)
			}

			$langOutRoot = Join-Path -Path $deviceOutRoot -ChildPath $langNorm
			if (-not (Try-EnsureDirectory -Path $langOutRoot)) {
				Write-Warning "Skipping language '$langNorm' for device '$identifier' (cannot create output folder: $langOutRoot)"
				continue
			}

			$macroFiles = @()
			try {
				$macroFiles = Get-ChildItem -LiteralPath $langAssetsRoot -Recurse -File -Filter '*.macro' -ErrorAction Stop
			} catch {
				Write-Warning "Cannot read macros from '$langAssetsRoot' (skipping): $($_.Exception.Message)"
				continue
			}

			foreach ($macroFile in $macroFiles) {
				$relative = $null
				try {
					$relative = [System.IO.Path]::GetRelativePath($langAssetsRootFull, $macroFile.FullName)
				} catch {
					# Fallback: last resort if GetRelativePath fails.
					$relative = Split-Path -Path $macroFile.FullName -Leaf
					Write-Warning "Unable to compute relative path for '$($macroFile.FullName)' from '$langAssetsRootFull'; writing flat file name only"
				}
				$macroRelativePath = Join-Path -Path $langNorm -ChildPath $relative
				$outPath = Join-Path -Path $langOutRoot -ChildPath $relative
				$outDir = Split-Path -Path $outPath -Parent

				if (-not (Try-EnsureDirectory -Path $outDir)) {
					Write-Warning "[$macroRelativePath] Skipping because output directory cannot be created: $outDir"
					continue
				}

				$macroObj = $null
				try {
					$macroObj = Read-JsonFile -Path $macroFile.FullName
				} catch {
					Write-Warning "[$macroRelativePath] Skipping; cannot parse macro JSON: $($_.Exception.Message)"
					continue
				}

				$updated = $null
				try {
					$updated = Update-MacroObject -MacroObj $macroObj -DeviceIdentifier $identifier -DeviceToken $token -DeviceEndpoint $endpoint -GuidSeed ([ref]$guidSeed) -SiGuidSeed ([ref]$siGuidSeed) -MacroRelativePath $macroRelativePath
				} catch {
					Write-Warning "[$macroRelativePath] Update failed: $($_.Exception.Message)"
					continue
				}

				try {
					$jsonOut = $updated | ConvertTo-Json -Depth 100
					# Keep MacroDroid-friendly encoding.
					Set-Content -LiteralPath $outPath -Value $jsonOut -Encoding UTF8
				} catch {
					Write-Warning "[$macroRelativePath] Failed to write output '$outPath': $($_.Exception.Message)"
					continue
				}
			}
		}
	}
} catch {
	Write-Error $_.Exception.Message
	exit 1
}

