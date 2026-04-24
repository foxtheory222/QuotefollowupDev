param(
  [string]$RepoRoot = "C:\Users\smcfarlane\Desktop\WorkBench\QuoteFollowUpRegion",
  [string]$TargetEnvironmentUrl = "https://regionaloperationshub.crm.dynamics.com",
  [string]$TargetEnvironmentName = "9f2e54c6-c349-e7e1-ac7c-010d3adf3c03",
  [string]$Username = "smcfarlane@applied.com",
  [string]$SolutionUniqueName = "qfu_sagl060flows",
  [string]$SolutionDisplayName = "QFU Southern Alberta GL060 Flows",
  [string]$SolutionVersion = "1.0.0.1",
  [switch]$ImportToTarget = $true
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "shared-mailbox-routing.ps1")

$solutionRoot = Join-Path $RepoRoot "results\sagl060flows"
$sourceRoot = Join-Path $solutionRoot "src"
$otherRoot = Join-Path $sourceRoot "Other"
$workflowRoot = Join-Path $sourceRoot "Workflows"
$zipPath = Join-Path $RepoRoot "results\qfu-southern-alberta-gl060-flows.zip"

$flowSpecs = @(
  [pscustomobject]@{
    BranchCode = "4171"
    BranchSlug = "4171-calgary"
    BranchName = "Calgary"
    SharedMailboxFolderId = (Get-SouthernAlbertaSharedMailboxFolderId -BranchCode "4171")
    FlowName = "4171-GL060-Inbox-Ingress"
    WorkflowId = "fd1ec8dc-56ca-4af7-ab8d-49465802b52a"
    TriggerMetadataId = "4c6de9cb-d07f-44e6-bfd1-f5b4e42c9c0f"
    FilterMetadataId = "47609468-ed1d-43d9-8c8d-a2a2489bb553"
    ComposeMetadataId = "65cbe8c5-6874-490d-a4f6-c794ca3a08f5"
    RawDocumentMetadataId = "9eee445a-1d5f-4d11-9daa-03679caa3df3"
    BatchMetadataId = "0f9d7294-9434-4a7d-b114-9e4e1a6b517f"
  },
  [pscustomobject]@{
    BranchCode = "4172"
    BranchSlug = "4172-lethbridge"
    BranchName = "Lethbridge"
    SharedMailboxFolderId = (Get-SouthernAlbertaSharedMailboxFolderId -BranchCode "4172")
    FlowName = "4172-GL060-Inbox-Ingress"
    WorkflowId = "7447f66d-93d0-44dd-9bf4-449e320190e7"
    TriggerMetadataId = "a7f242d7-2218-46a2-aa9f-30b4251a75f2"
    FilterMetadataId = "3eaafe42-2091-4761-a99e-e3dbe1481975"
    ComposeMetadataId = "b2c659ec-ca7f-438a-b94b-62246f87e356"
    RawDocumentMetadataId = "ef2376b1-3904-4642-8aa2-7a5ae02f7e5e"
    BatchMetadataId = "4764f5c2-ec7c-4f3c-bc88-e8a5a1ee3c91"
  },
  [pscustomobject]@{
    BranchCode = "4173"
    BranchSlug = "4173-medicine-hat"
    BranchName = "Medicine Hat"
    SharedMailboxFolderId = (Get-SouthernAlbertaSharedMailboxFolderId -BranchCode "4173")
    FlowName = "4173-GL060-Inbox-Ingress"
    WorkflowId = "cb327979-b304-4b7f-9a42-44c01c959666"
    TriggerMetadataId = "8ae266eb-b41a-4960-b9f9-a7a8fa9fcf07"
    FilterMetadataId = "75996cf1-285f-43aa-987d-b3cda22cba37"
    ComposeMetadataId = "a254a9e1-2d7b-4190-b90b-da532a70b5cb"
    RawDocumentMetadataId = "3fc46267-4fd1-4e22-94b9-4c82886dda5a"
    BatchMetadataId = "cd9594ae-b935-4c0b-ad7d-32879f826bb3"
  }
)

function Ensure-Directory {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
  }
}

function Connect-Org {
  param([string]$Url)

  Import-Module Microsoft.Xrm.Data.Powershell

  $conn = Connect-CrmOnline -ServerUrl $Url -ForceOAuth -Username $Username
  if (-not $conn -or -not $conn.IsReady) {
    throw "Dataverse connection failed for $Url : $($conn.LastCrmError)"
  }

  return $conn
}

function Activate-ImportedWorkflows {
  param(
    [string]$Url,
    [string[]]$WorkflowIds
  )

  $conn = Connect-Org -Url $Url
  foreach ($workflowId in @($WorkflowIds | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
    Set-CrmRecordState -conn $conn -EntityLogicalName workflow -Id $workflowId -StateCode Activated -StatusCode Activated | Out-Null
  }
}

function Enable-ImportedAdminFlows {
  param(
    [string]$EnvironmentName,
    [string[]]$WorkflowIds
  )

  Import-Module Microsoft.PowerApps.Administration.PowerShell
  Add-PowerAppsAccount -Endpoint prod -Username $Username | Out-Null

  $ids = @($WorkflowIds | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
  $adminFlows = @(Get-AdminFlow -EnvironmentName $EnvironmentName | Where-Object { $_.WorkflowEntityId -in $ids })
  foreach ($flow in $adminFlows) {
    if (-not $flow.Enabled) {
      Enable-AdminFlow -EnvironmentName $EnvironmentName -FlowName $flow.FlowName | Out-Null
    }
  }
}

function Remove-IfExists {
  param([string]$Path)
  if (Test-Path -LiteralPath $Path) {
    Remove-Item -LiteralPath $Path -Recurse -Force
  }
}

function Write-Utf8File {
  param(
    [string]$Path,
    [string]$Content
  )

  $parent = Split-Path -Parent $Path
  if ($parent) {
    Ensure-Directory $parent
  }

  [System.IO.File]::WriteAllText($Path, $Content, (New-Object System.Text.UTF8Encoding($false)))
}

function Get-UpperGuid {
  param([string]$Value)
  return $Value.ToUpperInvariant()
}

function New-WorkflowJson {
  param([object]$Flow)

  $sharedMailboxRoute = Get-SouthernAlbertaSharedMailboxRoute -BranchCode $Flow.BranchCode -MailboxAddress ("{0}@applied.com" -f $Flow.BranchCode)

  $jsonObject = [ordered]@{
    properties = [ordered]@{
      connectionReferences = [ordered]@{
        shared_office365 = [ordered]@{
          api = [ordered]@{ name = "shared_office365" }
          connection = [ordered]@{ connectionReferenceLogicalName = "qfu_shared_office365" }
          runtimeSource = "embedded"
        }
        'shared_commondataserviceforapps-1' = [ordered]@{
          api = [ordered]@{ name = "shared_commondataserviceforapps" }
          connection = [ordered]@{ connectionReferenceLogicalName = "qfu_shared_commondataserviceforapps" }
          runtimeSource = "embedded"
        }
      }
      definition = [ordered]@{
        '$schema' = "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#"
        contentVersion = "1.0.0.0"
        parameters = [ordered]@{
          '$authentication' = [ordered]@{
            defaultValue = [ordered]@{}
            type = "SecureObject"
          }
          '$connections' = [ordered]@{
            defaultValue = [ordered]@{}
            type = "Object"
          }
          qfu_QFU_BranchCode = [ordered]@{
            defaultValue = $Flow.BranchCode
            type = "String"
          }
          qfu_QFU_BranchSlug = [ordered]@{
            defaultValue = $Flow.BranchSlug
            type = "String"
          }
          qfu_QFU_BranchName = [ordered]@{
            defaultValue = $Flow.BranchName
            type = "String"
          }
          qfu_QFU_RegionSlug = [ordered]@{
            defaultValue = "southern-alberta"
            type = "String"
          }
          qfu_QFU_SharedMailboxAddress = [ordered]@{
            defaultValue = $sharedMailboxRoute.MailboxAddress
            type = "String"
          }
          qfu_QFU_SharedMailboxFolderId = [ordered]@{
            defaultValue = $sharedMailboxRoute.FolderId
            type = "String"
          }
        }
        triggers = [ordered]@{
          Shared_Mailbox_New_Email = [ordered]@{
            type = "OpenApiConnection"
            description = "Triggers when a GL060 PDF lands in the configured $($Flow.BranchCode) $($Flow.BranchName) shared mailbox folder."
            inputs = [ordered]@{
              parameters = [ordered]@{
                mailboxAddress = "@parameters('qfu_QFU_SharedMailboxAddress')"
                folderId = "@parameters('qfu_QFU_SharedMailboxFolderId')"
                hasAttachments = $true
                includeAttachments = $true
                importance = "Any"
                subjectFilter = "GL060 P&L report"
              }
              host = [ordered]@{
                apiId = "/providers/Microsoft.PowerApps/apis/shared_office365"
                operationId = "SharedMailboxOnNewEmailV2"
                connectionName = "shared_office365"
              }
            }
            recurrence = [ordered]@{
              interval = 1
              frequency = "Minute"
            }
            splitOn = "@triggerOutputs()?['body/value']"
            metadata = [ordered]@{
              operationMetadataId = $Flow.TriggerMetadataId
            }
          }
        }
        actions = [ordered]@{
          Filter_GL060_Attachments = [ordered]@{
            type = "Query"
            description = "Keep only GL060 PDF attachments. Do not rely on mailbox folder moves."
            inputs = [ordered]@{
              from = "@coalesce(triggerOutputs()?['body/attachments'], createArray())"
              where = "@and(endsWith(toLower(coalesce(item()?['name'], '')), '.pdf'), contains(replace(replace(replace(toLower(coalesce(item()?['name'], '')), ' ', ''), '-', ''), '_', ''), 'gl060reportprofitcenter'))"
            }
            runAfter = [ordered]@{}
            metadata = [ordered]@{
              operationMetadataId = $Flow.FilterMetadataId
            }
          }
          Apply_to_each_GL060_Attachment = [ordered]@{
            type = "Foreach"
            foreach = "@body('Filter_GL060_Attachments')"
            runAfter = [ordered]@{
              Filter_GL060_Attachments = @("Succeeded")
            }
            actions = [ordered]@{
              Compose_SourceId = [ordered]@{
                type = "Compose"
                inputs = "@concat(parameters('qfu_QFU_BranchCode'), '|raw|GL060|', guid())"
                runAfter = [ordered]@{}
                metadata = [ordered]@{
                  operationMetadataId = $Flow.ComposeMetadataId
                }
              }
              Create_Raw_Document = [ordered]@{
                type = "OpenApiConnection"
                inputs = [ordered]@{
                  parameters = [ordered]@{
                    entityName = "qfu_rawdocuments"
                    "item/qfu_name" = "@concat(parameters('qfu_QFU_BranchCode'), ' GL060 ', items('Apply_to_each_GL060_Attachment')?['name'])"
                    "item/qfu_sourceid" = "@outputs('Compose_SourceId')"
                    "item/qfu_branchcode" = "@parameters('qfu_QFU_BranchCode')"
                    "item/qfu_branchslug" = "@parameters('qfu_QFU_BranchSlug')"
                    "item/qfu_regionslug" = "@parameters('qfu_QFU_RegionSlug')"
                    "item/qfu_sourcefamily" = "GL060"
                    "item/qfu_sourcefile" = "@items('Apply_to_each_GL060_Attachment')?['name']"
                    "item/qfu_status" = "queued"
                    "item/qfu_receivedon" = "@coalesce(triggerOutputs()?['body/receivedDateTime'], utcNow())"
                    "item/qfu_rawcontentbase64" = "@base64(base64ToBinary(items('Apply_to_each_GL060_Attachment')?['contentBytes']))"
                    "item/qfu_processingnotes" = "@concat('Queued from the configured shared mailbox folder by GL060 ingress flow. Subject=', coalesce(triggerOutputs()?['body/subject'], ''), '; InternetMessageId=', coalesce(triggerOutputs()?['body/internetMessageId'], ''), '; ReceivedDateTime=', string(coalesce(triggerOutputs()?['body/receivedDateTime'], utcNow())))"
                  }
                  host = [ordered]@{
                    apiId = "/providers/Microsoft.PowerApps/apis/shared_commondataserviceforapps"
                    operationId = "CreateRecord"
                    connectionName = "shared_commondataserviceforapps-1"
                  }
                }
                runAfter = [ordered]@{
                  Compose_SourceId = @("Succeeded")
                }
                metadata = [ordered]@{
                  operationMetadataId = $Flow.RawDocumentMetadataId
                }
              }
              Create_Ingestion_Batch = [ordered]@{
                type = "OpenApiConnection"
                inputs = [ordered]@{
                  parameters = [ordered]@{
                    entityName = "qfu_ingestionbatchs"
                    "item/qfu_name" = "@concat(parameters('qfu_QFU_BranchCode'), ' GL060 Inbox Import')"
                    "item/qfu_sourceid" = "@outputs('Compose_SourceId')"
                    "item/qfu_branchcode" = "@parameters('qfu_QFU_BranchCode')"
                    "item/qfu_branchslug" = "@parameters('qfu_QFU_BranchSlug')"
                    "item/qfu_regionslug" = "@parameters('qfu_QFU_RegionSlug')"
                    "item/qfu_sourcefamily" = "GL060"
                    "item/qfu_sourcefilename" = "@items('Apply_to_each_GL060_Attachment')?['name']"
                    "item/qfu_status" = "queued"
                    "item/qfu_insertedcount" = 0
                    "item/qfu_updatedcount" = 0
                    "item/qfu_startedon" = "@coalesce(triggerOutputs()?['body/receivedDateTime'], utcNow())"
                    "item/qfu_triggerflow" = "$($Flow.FlowName)"
                    "item/qfu_notes" = "@concat('Queued from the configured shared mailbox folder. Subject=', coalesce(triggerOutputs()?['body/subject'], ''), '; InternetMessageId=', coalesce(triggerOutputs()?['body/internetMessageId'], ''), '; ReceivedDateTime=', string(coalesce(triggerOutputs()?['body/receivedDateTime'], utcNow())), '. Awaiting downstream GL060 processing.')"
                  }
                  host = [ordered]@{
                    apiId = "/providers/Microsoft.PowerApps/apis/shared_commondataserviceforapps"
                    operationId = "CreateRecord"
                    connectionName = "shared_commondataserviceforapps-1"
                  }
                }
                runAfter = [ordered]@{
                  Create_Raw_Document = @("Succeeded")
                }
                metadata = [ordered]@{
                  operationMetadataId = $Flow.BatchMetadataId
                }
              }
            }
          }
        }
        outputs = [ordered]@{}
      }
      templateName = $null
    }
    schemaVersion = "1.0.0.0"
  }

  return ($jsonObject | ConvertTo-Json -Depth 30)
}

function New-WorkflowDataXml {
  param([object]$Flow)

  $workflowIdUpper = Get-UpperGuid $Flow.WorkflowId
  return @"
<?xml version="1.0" encoding="utf-8"?>
<Workflow WorkflowId="{$workflowIdUpper}" Name="$($Flow.FlowName)" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <JsonFileName>/Workflows/$($Flow.FlowName)-$workflowIdUpper.json</JsonFileName>
  <Type>1</Type>
  <Subprocess>0</Subprocess>
  <Category>5</Category>
  <Mode>0</Mode>
  <Scope>4</Scope>
  <OnDemand>0</OnDemand>
  <TriggerOnCreate>0</TriggerOnCreate>
  <TriggerOnDelete>0</TriggerOnDelete>
  <AsyncAutodelete>0</AsyncAutodelete>
  <SyncWorkflowLogOnFailure>0</SyncWorkflowLogOnFailure>
  <StateCode>0</StateCode>
  <StatusCode>1</StatusCode>
  <RunAs>1</RunAs>
  <IsTransacted>1</IsTransacted>
  <IntroducedVersion>1.0</IntroducedVersion>
  <IsCustomizable>1</IsCustomizable>
  <RendererObjectTypeCode>0</RendererObjectTypeCode>
  <IsCustomProcessingStepAllowedForOtherPublishers>1</IsCustomProcessingStepAllowedForOtherPublishers>
  <ModernFlowType>0</ModernFlowType>
  <PrimaryEntity>none</PrimaryEntity>
  <LocalizedNames>
    <LocalizedName languagecode="1033" description="$($Flow.FlowName)" />
  </LocalizedNames>
</Workflow>
"@
}

Remove-IfExists $solutionRoot
Remove-IfExists $zipPath

Ensure-Directory $otherRoot
Ensure-Directory $workflowRoot

$solutionXml = @"
<?xml version="1.0" encoding="utf-8"?>
<ImportExportXml version="9.2.26033.148" SolutionPackageVersion="9.2" languagecode="1033" generatedBy="CrmLive" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" OrganizationVersion="9.2.26033.148" OrganizationSchemaType="Standard" CRMServerServiceabilityVersion="9.2.26033.00148">
  <SolutionManifest>
    <UniqueName>$SolutionUniqueName</UniqueName>
    <LocalizedNames>
      <LocalizedName description="$SolutionDisplayName" languagecode="1033" />
    </LocalizedNames>
    <Descriptions />
    <Version>$SolutionVersion</Version>
    <Managed>0</Managed>
    <Publisher>
      <UniqueName>qfu</UniqueName>
      <LocalizedNames>
        <LocalizedName description="qfu" languagecode="1033" />
      </LocalizedNames>
      <Descriptions />
      <EMailAddress xsi:nil="true"></EMailAddress>
      <SupportingWebsiteUrl xsi:nil="true"></SupportingWebsiteUrl>
      <CustomizationPrefix>qfu</CustomizationPrefix>
      <CustomizationOptionValuePrefix>98501</CustomizationOptionValuePrefix>
      <Addresses>
        <Address><AddressNumber>1</AddressNumber></Address>
        <Address><AddressNumber>2</AddressNumber></Address>
      </Addresses>
    </Publisher>
    <RootComponents>
$(
  ($flowSpecs | ForEach-Object { '      <RootComponent type="29" id="{' + $_.WorkflowId + '}" behavior="0" />' }) -join "`r`n"
)
    </RootComponents>
    <MissingDependencies />
  </SolutionManifest>
</ImportExportXml>
"@

$customizationsXml = @"
<?xml version="1.0" encoding="utf-8"?>
<ImportExportXml xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" OrganizationVersion="9.2.26033.148" OrganizationSchemaType="Standard" CRMServerServiceabilityVersion="9.2.26033.00148">
  <Entities />
  <Roles />
  <Workflows />
  <FieldSecurityProfiles />
  <Templates />
  <EntityMaps />
  <EntityRelationships />
  <OrganizationSettings />
  <optionsets />
  <CustomControls />
  <EntityDataProviders />
  <connectionreferences>
    <connectionreference connectionreferencelogicalname="qfu_shared_office365">
      <connectionreferencedisplayname>qfu_shared_office365</connectionreferencedisplayname>
      <connectorid>/providers/Microsoft.PowerApps/apis/shared_office365</connectorid>
      <iscustomizable>1</iscustomizable>
      <promptingbehavior>0</promptingbehavior>
      <statecode>0</statecode>
      <statuscode>1</statuscode>
    </connectionreference>
    <connectionreference connectionreferencelogicalname="qfu_shared_commondataserviceforapps">
      <connectionreferencedisplayname>qfu_shared_commondataserviceforapps</connectionreferencedisplayname>
      <connectorid>/providers/Microsoft.PowerApps/apis/shared_commondataserviceforapps</connectorid>
      <iscustomizable>1</iscustomizable>
      <promptingbehavior>0</promptingbehavior>
      <statecode>0</statecode>
      <statuscode>1</statuscode>
    </connectionreference>
  </connectionreferences>
  <Languages>
    <Language>1033</Language>
  </Languages>
</ImportExportXml>
"@

$relationshipsXml = @"
<?xml version="1.0" encoding="utf-8"?>
<EntityRelationships xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" />
"@

Write-Utf8File -Path (Join-Path $otherRoot "Solution.xml") -Content $solutionXml
Write-Utf8File -Path (Join-Path $otherRoot "Customizations.xml") -Content $customizationsXml
Write-Utf8File -Path (Join-Path $otherRoot "Relationships.xml") -Content $relationshipsXml

foreach ($flow in $flowSpecs) {
  $upperGuid = Get-UpperGuid $flow.WorkflowId
  $jsonName = "$($flow.FlowName)-$upperGuid.json"
  $dataXmlName = "$jsonName.data.xml"

  Write-Utf8File -Path (Join-Path $workflowRoot $jsonName) -Content (New-WorkflowJson -Flow $flow)
  Write-Utf8File -Path (Join-Path $workflowRoot $dataXmlName) -Content (New-WorkflowDataXml -Flow $flow)
}

& pac solution pack --folder $sourceRoot --zipfile $zipPath --packagetype Unmanaged
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $zipPath)) {
  throw "pac solution pack failed for $zipPath"
}

if ($ImportToTarget) {
  & pac solution import --environment $TargetEnvironmentUrl --path $zipPath --force-overwrite --publish-changes
  if ($LASTEXITCODE -ne 0) {
    throw "pac solution import failed for $zipPath"
  }

  $workflowIds = @($flowSpecs | ForEach-Object { [string]$_.WorkflowId })
  Activate-ImportedWorkflows -Url $TargetEnvironmentUrl -WorkflowIds $workflowIds
  Enable-ImportedAdminFlows -EnvironmentName $TargetEnvironmentName -WorkflowIds $workflowIds
}

Write-Host "SOLUTION_ROOT=$solutionRoot"
Write-Host "ZIP_PATH=$zipPath"
Write-Host "FLOWS=$($flowSpecs.FlowName -join ', ')"
