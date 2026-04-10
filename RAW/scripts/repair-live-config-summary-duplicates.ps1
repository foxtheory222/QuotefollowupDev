param(
  [string]$TargetEnvironmentUrl = "https://regionaloperationshub.crm.dynamics.com",
  [string]$Username = "smcfarlane@applied.com",
  [string[]]$BranchCodes = @("4171", "4172", "4173"),
  [switch]$Apply,
  [string]$OutputPath = "results\\live-config-summary-duplicate-repair.json"
)

$ErrorActionPreference = "Stop"

Import-Module Microsoft.Xrm.Data.Powershell

function Ensure-Directory {
  param([string]$Path)

  if ($Path -and -not (Test-Path -LiteralPath $Path)) {
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
  }
}

function Write-Utf8Json {
  param(
    [string]$Path,
    [object]$Object
  )

  $directory = Split-Path -Parent $Path
  if ($directory) {
    Ensure-Directory -Path $directory
  }

  [System.IO.File]::WriteAllText($Path, ($Object | ConvertTo-Json -Depth 20), [System.Text.UTF8Encoding]::new($false))
}

function Connect-Org {
  param([string]$Url)

  $connection = Connect-CrmOnline -ServerUrl $Url -ForceOAuth -Username $Username
  if (-not $connection -or -not $connection.IsReady) {
    throw "Dataverse connection failed for $Url : $($connection.LastCrmError)"
  }

  return $connection
}

function Get-PropertyValue {
  param(
    [object]$Record,
    [string]$Name
  )

  if ($null -eq $Record -or -not $Record.PSObject.Properties[$Name]) {
    return $null
  }

  return $Record.$Name
}

function Get-StringValue {
  param(
    [object]$Record,
    [string]$Name
  )

  $value = Get-PropertyValue -Record $Record -Name $Name
  if ($null -eq $value) {
    return ""
  }

  return ([string]$value).Trim()
}

function Get-DateValue {
  param(
    [object]$Record,
    [string[]]$Names
  )

  foreach ($name in @($Names)) {
    $value = Get-PropertyValue -Record $Record -Name $name
    if ($value) {
      return [datetime]$value
    }
  }

  return [datetime]::MinValue
}

function Get-CompletenessScore {
  param(
    [object]$Record,
    [string[]]$FieldNames
  )

  $score = 0
  foreach ($fieldName in @($FieldNames)) {
    if (-not [string]::IsNullOrWhiteSpace((Get-StringValue -Record $Record -Name $fieldName))) {
      $score += 1
    }
  }

  return $score
}

function Remove-RecordSafe {
  param(
    [Microsoft.Xrm.Tooling.Connector.CrmServiceClient]$Connection,
    [string]$EntityLogicalName,
    [Guid]$RecordId
  )

  try {
    $Connection.Delete($EntityLogicalName, $RecordId)
  } catch {
    if ($_.Exception.Message -like "*Does Not Exist*" -or $_.Exception.Message -like "*No object matched the query*") {
      return
    }
    throw
  }
}

function Get-DuplicateResolutionPlan {
  param(
    [object[]]$Rows,
    [string]$PrimaryIdAttribute,
    [scriptblock]$KeyScript,
    $SortScript
  )

  $groups = [ordered]@{}
  foreach ($row in @($Rows)) {
    $key = & $KeyScript $row
    if ([string]::IsNullOrWhiteSpace([string]$key)) {
      continue
    }

    if (-not $groups.Contains($key)) {
      $groups[$key] = @()
    }
    $groups[$key] += $row
  }

  $plans = @()
  foreach ($key in $groups.Keys) {
    $groupRows = @($groups[$key])
    if ($groupRows.Count -lt 2) {
      continue
    }

    $ordered = @($groupRows | Sort-Object -Property $SortScript)
    $winner = $ordered | Select-Object -First 1
    $duplicates = @($ordered | Select-Object -Skip 1)
    $plans += [pscustomobject]@{
      key = $key
      winner = $winner
      duplicates = $duplicates
      winner_id = [string](Get-PropertyValue -Record $winner -Name $PrimaryIdAttribute)
      duplicate_ids = @($duplicates | ForEach-Object { [string](Get-PropertyValue -Record $_ -Name $PrimaryIdAttribute) })
    }
  }

  return $plans
}

function Get-BranchRows {
  param([Microsoft.Xrm.Tooling.Connector.CrmServiceClient]$Connection)

  return @((Get-CrmRecords -conn $Connection -EntityLogicalName "qfu_branch" -FilterAttribute "qfu_regionslug" -FilterOperator eq -FilterValue "southern-alberta" -Fields @(
        "qfu_branchid",
        "qfu_sourceid",
        "qfu_branchcode",
        "qfu_branchname",
        "qfu_branchslug",
        "qfu_regionslug",
        "qfu_regionname",
        "qfu_mailboxaddress",
        "qfu_branchstate",
        "qfu_sortorder",
        "qfu_stalethresholdhours",
        "qfu_budgetpacewarningpct",
        "qfu_overduequotewarningcount",
        "qfu_overduebackorderwarningcount",
        "qfu_managernote",
        "createdon",
        "modifiedon"
      ) -TopCount 100).CrmRecords)
}

function Get-RegionRows {
  param([Microsoft.Xrm.Tooling.Connector.CrmServiceClient]$Connection)

  return @((Get-CrmRecords -conn $Connection -EntityLogicalName "qfu_region" -Fields @(
        "qfu_regionid",
        "qfu_regionslug",
        "qfu_regionname",
        "qfu_status",
        "qfu_sortorder",
        "qfu_stalethresholdhours",
        "qfu_budgetpacewarningpct",
        "qfu_overduequotewarningcount",
        "qfu_overduebackorderwarningcount",
        "qfu_managernote",
        "createdon",
        "modifiedon"
      ) -TopCount 50).CrmRecords)
}

function Get-BranchSummaryRows {
  param(
    [Microsoft.Xrm.Tooling.Connector.CrmServiceClient]$Connection,
    [string[]]$Codes
  )

  $rows = @()
  foreach ($branchCode in @($Codes)) {
    $rows += @((Get-CrmRecords -conn $Connection -EntityLogicalName "qfu_branchdailysummary" -FilterAttribute "qfu_branchcode" -FilterOperator eq -FilterValue $branchCode -Fields @(
          "qfu_branchdailysummaryid",
          "qfu_sourceid",
          "qfu_branchcode",
          "qfu_branchslug",
          "qfu_regionslug",
          "qfu_summarydate",
          "qfu_lastcalculatedon",
          "qfu_budgetactual",
          "qfu_budgettarget",
          "qfu_budgetpace",
          "createdon",
          "modifiedon"
        ) -TopCount 250).CrmRecords)
  }
  return $rows
}

function Get-BudgetArchiveRows {
  param(
    [Microsoft.Xrm.Tooling.Connector.CrmServiceClient]$Connection,
    [string[]]$Codes
  )

  $rows = @()
  foreach ($branchCode in @($Codes)) {
    $rows += @((Get-CrmRecords -conn $Connection -EntityLogicalName "qfu_budgetarchive" -FilterAttribute "qfu_branchcode" -FilterOperator eq -FilterValue $branchCode -Fields @(
          "qfu_budgetarchiveid",
          "qfu_sourceid",
          "qfu_branchcode",
          "qfu_branchslug",
          "qfu_regionslug",
          "qfu_month",
          "qfu_year",
          "qfu_fiscalyear",
          "qfu_budgetgoal",
          "qfu_actualsales",
          "qfu_lastupdated",
          "createdon",
          "modifiedon"
        ) -TopCount 250).CrmRecords)
  }
  return $rows
}

function Apply-ResolutionPlans {
  param(
    [Microsoft.Xrm.Tooling.Connector.CrmServiceClient]$Connection,
    [string]$EntityLogicalName,
    [string]$PrimaryIdAttribute,
    [object[]]$Plans
  )

  $deleted = 0
  foreach ($plan in @($Plans)) {
    foreach ($duplicate in @($plan.duplicates)) {
      $recordId = Get-PropertyValue -Record $duplicate -Name $PrimaryIdAttribute
      if (-not $recordId) {
        continue
      }
      Remove-RecordSafe -Connection $Connection -EntityLogicalName $EntityLogicalName -RecordId ([guid][string]$recordId)
      $deleted += 1
    }
  }
  return $deleted
}

$connection = Connect-Org -Url $TargetEnvironmentUrl

$branchPlans = Get-DuplicateResolutionPlan `
  -Rows (Get-BranchRows -Connection $connection) `
  -PrimaryIdAttribute "qfu_branchid" `
  -KeyScript { param($row) (Get-StringValue -Record $row -Name "qfu_sourceid"), (Get-StringValue -Record $row -Name "qfu_branchcode"), (Get-StringValue -Record $row -Name "qfu_branchslug") | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1 } `
  -SortScript @(
    @{ Expression = { Get-CompletenessScore -Record $_ -FieldNames @("qfu_sourceid", "qfu_branchcode", "qfu_branchslug", "qfu_branchname", "qfu_regionslug", "qfu_mailboxaddress", "qfu_branchstate") }; Descending = $true },
    @{ Expression = { [int](Get-PropertyValue -Record $_ -Name "qfu_sortorder") }; Descending = $false },
    @{ Expression = { Get-DateValue -Record $_ -Names @("modifiedon", "createdon") }; Descending = $true },
    @{ Expression = { [string](Get-PropertyValue -Record $_ -Name "qfu_branchid") } }
  )

$regionPlans = Get-DuplicateResolutionPlan `
  -Rows (Get-RegionRows -Connection $connection) `
  -PrimaryIdAttribute "qfu_regionid" `
  -KeyScript { param($row) Get-StringValue -Record $row -Name "qfu_regionslug" } `
  -SortScript @(
    @{ Expression = { Get-CompletenessScore -Record $_ -FieldNames @("qfu_regionslug", "qfu_regionname", "qfu_status", "qfu_managernote") }; Descending = $true },
    @{ Expression = { [int](Get-PropertyValue -Record $_ -Name "qfu_sortorder") }; Descending = $false },
    @{ Expression = { Get-DateValue -Record $_ -Names @("modifiedon", "createdon") }; Descending = $true },
    @{ Expression = { [string](Get-PropertyValue -Record $_ -Name "qfu_regionid") } }
  )

$summaryPlans = Get-DuplicateResolutionPlan `
  -Rows (Get-BranchSummaryRows -Connection $connection -Codes $BranchCodes) `
  -PrimaryIdAttribute "qfu_branchdailysummaryid" `
  -KeyScript {
    param($row)
    $sourceId = Get-StringValue -Record $row -Name "qfu_sourceid"
    if (-not [string]::IsNullOrWhiteSpace($sourceId)) {
      return $sourceId
    }
    $branchCode = Get-StringValue -Record $row -Name "qfu_branchcode"
    $summaryDate = Get-StringValue -Record $row -Name "qfu_summarydate"
    if (-not [string]::IsNullOrWhiteSpace($branchCode) -and -not [string]::IsNullOrWhiteSpace($summaryDate)) {
      return "$branchCode|summarydate|$summaryDate"
    }
    return ""
  } `
  -SortScript @(
    @{ Expression = { Get-DateValue -Record $_ -Names @("qfu_lastcalculatedon", "modifiedon", "createdon") }; Descending = $true },
    @{ Expression = { Get-CompletenessScore -Record $_ -FieldNames @("qfu_sourceid", "qfu_branchcode", "qfu_branchslug", "qfu_summarydate", "qfu_budgetactual", "qfu_budgettarget", "qfu_budgetpace") }; Descending = $true },
    @{ Expression = { [string](Get-PropertyValue -Record $_ -Name "qfu_branchdailysummaryid") } }
  )

$budgetArchivePlans = Get-DuplicateResolutionPlan `
  -Rows (Get-BudgetArchiveRows -Connection $connection -Codes $BranchCodes) `
  -PrimaryIdAttribute "qfu_budgetarchiveid" `
  -KeyScript {
    param($row)
    $sourceId = Get-StringValue -Record $row -Name "qfu_sourceid"
    if (-not [string]::IsNullOrWhiteSpace($sourceId)) {
      return $sourceId
    }
    $branchCode = Get-StringValue -Record $row -Name "qfu_branchcode"
    $fiscalYear = Get-StringValue -Record $row -Name "qfu_fiscalyear"
    $month = Get-StringValue -Record $row -Name "qfu_month"
    if (-not [string]::IsNullOrWhiteSpace($branchCode) -and -not [string]::IsNullOrWhiteSpace($fiscalYear) -and -not [string]::IsNullOrWhiteSpace($month)) {
      return "$branchCode|archive|$fiscalYear|$month"
    }
    return ""
  } `
  -SortScript @(
    @{ Expression = { if ($null -ne (Get-PropertyValue -Record $_ -Name "qfu_budgetgoal")) { 1 } else { 0 } }; Descending = $true },
    @{ Expression = { Get-DateValue -Record $_ -Names @("qfu_lastupdated", "modifiedon", "createdon") }; Descending = $true },
    @{ Expression = { [string](Get-PropertyValue -Record $_ -Name "qfu_budgetarchiveid") } }
  )

$deletedCounts = [ordered]@{
  qfu_branch = 0
  qfu_region = 0
  qfu_branchdailysummary = 0
  qfu_budgetarchive = 0
}

if ($Apply) {
  $deletedCounts.qfu_branch = Apply-ResolutionPlans -Connection $connection -EntityLogicalName "qfu_branch" -PrimaryIdAttribute "qfu_branchid" -Plans $branchPlans
  $deletedCounts.qfu_region = Apply-ResolutionPlans -Connection $connection -EntityLogicalName "qfu_region" -PrimaryIdAttribute "qfu_regionid" -Plans $regionPlans
  $deletedCounts.qfu_branchdailysummary = Apply-ResolutionPlans -Connection $connection -EntityLogicalName "qfu_branchdailysummary" -PrimaryIdAttribute "qfu_branchdailysummaryid" -Plans $summaryPlans
  $deletedCounts.qfu_budgetarchive = Apply-ResolutionPlans -Connection $connection -EntityLogicalName "qfu_budgetarchive" -PrimaryIdAttribute "qfu_budgetarchiveid" -Plans $budgetArchivePlans
}

$report = [ordered]@{
  target_environment = $TargetEnvironmentUrl
  generated_at = (Get-Date).ToString("o")
  apply = [bool]$Apply
  branch_codes = $BranchCodes
  duplicate_groups = [ordered]@{
    qfu_branch = $branchPlans
    qfu_region = $regionPlans
    qfu_branchdailysummary = $summaryPlans
    qfu_budgetarchive = $budgetArchivePlans
  }
  deleted = $deletedCounts
}

Write-Utf8Json -Path $OutputPath -Object $report
Write-Host "OUTPUT_PATH=$OutputPath"
