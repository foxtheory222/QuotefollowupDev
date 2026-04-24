param(
  [string]$RepoRoot = "C:\Users\smcfarlane\Desktop\WorkBench\QuoteFollowUpRegion",
  [string]$TargetEnvironmentUrl = "https://regionaloperationshub.crm.dynamics.com",
  [string]$TargetEnvironmentName = "9f2e54c6-c349-e7e1-ac7c-010d3adf3c03",
  [string]$Username = "smcfarlane@applied.com",
  [string]$SolutionUniqueName = "qfu_safreightflows",
  [string]$SolutionDisplayName = "QFU Southern Alberta Freight Flows",
  [string]$SolutionVersion = "1.0.0.1",
  [string]$ImportToTarget = "true"
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "shared-mailbox-routing.ps1")

$solutionRoot = Join-Path $RepoRoot "results\safreightflows"
$sourceRoot = Join-Path $solutionRoot "src"
$otherRoot = Join-Path $sourceRoot "Other"
$workflowRoot = Join-Path $sourceRoot "Workflows"
$zipPath = Join-Path $RepoRoot "results\qfu-southern-alberta-freight-flows.zip"

$flowSpecs = @(
  [pscustomobject]@{
    Type = "ingress"
    BranchCode = "4171"
    BranchSlug = "4171-calgary"
    BranchName = "Calgary"
    SharedMailboxFolderId = (Get-SouthernAlbertaSharedMailboxFolderId -BranchCode "4171")
    FlowName = "4171-Freight-Inbox-Ingress"
    WorkflowId = "cf9dbe3d-e0a8-4257-9b97-e21f34a39119"
  },
  [pscustomobject]@{
    Type = "ingress"
    BranchCode = "4172"
    BranchSlug = "4172-lethbridge"
    BranchName = "Lethbridge"
    SharedMailboxFolderId = (Get-SouthernAlbertaSharedMailboxFolderId -BranchCode "4172")
    FlowName = "4172-Freight-Inbox-Ingress"
    WorkflowId = "f1a3e7b2-7a34-4bc7-8cfa-20e4d9350f56"
  },
  [pscustomobject]@{
    Type = "ingress"
    BranchCode = "4173"
    BranchSlug = "4173-medicine-hat"
    BranchName = "Medicine Hat"
    SharedMailboxFolderId = (Get-SouthernAlbertaSharedMailboxFolderId -BranchCode "4173")
    FlowName = "4173-Freight-Inbox-Ingress"
    WorkflowId = "b6cd0d55-c3d8-4d83-a2e0-53ef2dd19d24"
  },
  [pscustomobject]@{
    Type = "archive"
    BranchCode = ""
    BranchSlug = ""
    BranchName = ""
    FlowName = "QFU-Freight-Archive-Workitems"
    WorkflowId = "d0e9e2a5-5155-4d7b-bd8f-c3fd99ff181d"
  }
)

function Ensure-Directory {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
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

  [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
}

function Get-UpperGuid {
  param([string]$Value)
  return $Value.ToUpperInvariant()
}

function Convert-ToBooleanFlag {
  param(
    [AllowNull()]
    [object]$Value,
    [bool]$DefaultValue = $true
  )

  if ($null -eq $Value) {
    return $DefaultValue
  }

  if ($Value -is [bool]) {
    return [bool]$Value
  }

  $text = [string]$Value
  if ([string]::IsNullOrWhiteSpace($text)) {
    return $DefaultValue
  }

  switch ($text.Trim().ToLowerInvariant()) {
    "1" { return $true }
    "0" { return $false }
    "true" { return $true }
    "false" { return $false }
    "yes" { return $true }
    "no" { return $false }
    default { throw "ImportToTarget must be true/false/1/0/yes/no. Received '$Value'." }
  }
}

$shouldImportToTarget = Convert-ToBooleanFlag -Value $ImportToTarget -DefaultValue $true

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

function New-IngressWorkflowJson {
  param([object]$Flow)

  $sharedMailboxRoute = Get-SouthernAlbertaSharedMailboxRoute -BranchCode $Flow.BranchCode -MailboxAddress ("{0}@applied.com" -f $Flow.BranchCode)

  $filterMetadataId = [guid]::NewGuid().Guid
  $familyMetadataId = [guid]::NewGuid().Guid
  $sourceIdMetadataId = [guid]::NewGuid().Guid
  $rawMetadataId = [guid]::NewGuid().Guid
  $batchMetadataId = [guid]::NewGuid().Guid
  $hostedInvokeMetadataId = [guid]::NewGuid().Guid
  $rawProcessedMetadataId = [guid]::NewGuid().Guid
  $batchProcessedMetadataId = [guid]::NewGuid().Guid
  $rawErrorMetadataId = [guid]::NewGuid().Guid
  $batchErrorMetadataId = [guid]::NewGuid().Guid

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
          qfu_Freight_BranchCode = [ordered]@{
            defaultValue = $Flow.BranchCode
            type = "String"
          }
          qfu_Freight_BranchSlug = [ordered]@{
            defaultValue = $Flow.BranchSlug
            type = "String"
          }
          qfu_Freight_BranchName = [ordered]@{
            defaultValue = $Flow.BranchName
            type = "String"
          }
          qfu_Freight_RegionSlug = [ordered]@{
            defaultValue = "southern-alberta"
            type = "String"
          }
          qfu_Freight_SharedMailboxAddress = [ordered]@{
            defaultValue = $sharedMailboxRoute.MailboxAddress
            type = "String"
          }
          qfu_Freight_SharedMailboxFolderId = [ordered]@{
            defaultValue = $sharedMailboxRoute.FolderId
            type = "String"
          }
          qfu_Freight_HostedParserUrl = [ordered]@{
            defaultValue = "https://<set-freight-parser-host>/api/processfreightdocument"
            type = "String"
          }
          qfu_Freight_HostedParserKey = [ordered]@{
            defaultValue = "__SET_FREIGHT_HOSTED_PARSER_KEY__"
            type = "String"
          }
        }
        triggers = [ordered]@{
          Shared_Mailbox_New_Email = [ordered]@{
            type = "OpenApiConnection"
            description = "Queues weekly freight report attachments from the configured $($Flow.BranchCode) $($Flow.BranchName) shared mailbox folder, then calls the hosted freight parser for legacy .xls and .xlsx normalization."
            inputs = [ordered]@{
              parameters = [ordered]@{
                mailboxAddress = "@parameters('qfu_Freight_SharedMailboxAddress')"
                folderId = "@parameters('qfu_Freight_SharedMailboxFolderId')"
                includeAttachments = $true
                importance = "Any"
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
              operationMetadataId = [guid]::NewGuid().Guid
            }
          }
        }
        actions = [ordered]@{
          Filter_Freight_Attachments = [ordered]@{
            type = "Query"
            description = "Keep only freight invoice workbook attachments that match the configured carrier families."
            inputs = [ordered]@{
              from = "@coalesce(triggerOutputs()?['body/attachments'], createArray())"
              where = "@or(and(endsWith(toLower(coalesce(item()?['name'], '')), '.xlsx'), contains(toLower(coalesce(item()?['name'], '')), 'applied canada'), contains(toLower(coalesce(item()?['name'], '')), 'invoice report')), and(endsWith(toLower(coalesce(item()?['name'], '')), '.xls'), contains(toLower(coalesce(item()?['name'], '')), 'loomis invoices report')), and(endsWith(toLower(coalesce(item()?['name'], '')), '.xls'), contains(toLower(coalesce(item()?['name'], '')), 'purolator invoices report')), and(endsWith(toLower(coalesce(item()?['name'], '')), '.xls'), contains(toLower(coalesce(item()?['name'], '')), 'ups canada invoices previous week report')))"
            }
            runAfter = [ordered]@{}
            metadata = [ordered]@{
              operationMetadataId = $filterMetadataId
            }
          }
          Apply_to_each_Freight_Attachment = [ordered]@{
            type = "Foreach"
            foreach = "@body('Filter_Freight_Attachments')"
            runAfter = [ordered]@{
              Filter_Freight_Attachments = @("Succeeded")
            }
            actions = [ordered]@{
              Compose_Source_Family = [ordered]@{
                type = "Compose"
                inputs = "@if(and(endsWith(toLower(coalesce(items('Apply_to_each_Freight_Attachment')?['name'], '')), '.xlsx'), contains(toLower(coalesce(items('Apply_to_each_Freight_Attachment')?['name'], '')), 'applied canada')), 'FREIGHT_REDWOOD', if(contains(toLower(coalesce(items('Apply_to_each_Freight_Attachment')?['name'], '')), 'loomis invoices report'), 'FREIGHT_LOOMIS_F15', if(contains(toLower(coalesce(items('Apply_to_each_Freight_Attachment')?['name'], '')), 'purolator invoices report'), 'FREIGHT_PUROLATOR_F07', if(contains(toLower(coalesce(items('Apply_to_each_Freight_Attachment')?['name'], '')), 'ups canada invoices previous week report'), 'FREIGHT_UPS_F06', ''))))"
                runAfter = [ordered]@{}
                metadata = [ordered]@{
                  operationMetadataId = $familyMetadataId
                }
              }
              Compose_Source_Id = [ordered]@{
                type = "Compose"
                inputs = "@concat(parameters('qfu_Freight_BranchCode'), '|raw|', outputs('Compose_Source_Family'), '|', guid())"
                runAfter = [ordered]@{
                  Compose_Source_Family = @("Succeeded")
                }
                metadata = [ordered]@{
                  operationMetadataId = $sourceIdMetadataId
                }
              }
              Create_Raw_Document = [ordered]@{
                type = "OpenApiConnection"
                inputs = [ordered]@{
                  parameters = [ordered]@{
                    entityName = "qfu_rawdocuments"
                    "item/qfu_name" = "@concat(parameters('qfu_Freight_BranchCode'), ' Freight ', items('Apply_to_each_Freight_Attachment')?['name'])"
                    "item/qfu_sourceid" = "@outputs('Compose_Source_Id')"
                    "item/qfu_branchcode" = "@parameters('qfu_Freight_BranchCode')"
                    "item/qfu_branchslug" = "@parameters('qfu_Freight_BranchSlug')"
                    "item/qfu_regionslug" = "@parameters('qfu_Freight_RegionSlug')"
                    "item/qfu_sourcefamily" = "@outputs('Compose_Source_Family')"
                    "item/qfu_sourcefile" = "@items('Apply_to_each_Freight_Attachment')?['name']"
                    "item/qfu_status" = "queued"
                    "item/qfu_receivedon" = "@utcNow()"
                    "item/qfu_rawcontentbase64" = "@base64(base64ToBinary(items('Apply_to_each_Freight_Attachment')?['contentBytes']))"
                    "item/qfu_processingnotes" = "Queued from the configured shared mailbox folder by freight ingress flow. Hosted parser call is pending."
                  }
                  host = [ordered]@{
                    apiId = "/providers/Microsoft.PowerApps/apis/shared_commondataserviceforapps"
                    operationId = "CreateRecord"
                    connectionName = "shared_commondataserviceforapps-1"
                  }
                }
                runAfter = [ordered]@{
                  Compose_Source_Id = @("Succeeded")
                }
                metadata = [ordered]@{
                  operationMetadataId = $rawMetadataId
                }
              }
              Create_Ingestion_Batch = [ordered]@{
                type = "OpenApiConnection"
                inputs = [ordered]@{
                  parameters = [ordered]@{
                    entityName = "qfu_ingestionbatchs"
                    "item/qfu_name" = "@concat(parameters('qfu_Freight_BranchCode'), ' Freight Import ', items('Apply_to_each_Freight_Attachment')?['name'])"
                    "item/qfu_sourceid" = "@outputs('Compose_Source_Id')"
                    "item/qfu_branchcode" = "@parameters('qfu_Freight_BranchCode')"
                    "item/qfu_branchslug" = "@parameters('qfu_Freight_BranchSlug')"
                    "item/qfu_regionslug" = "@parameters('qfu_Freight_RegionSlug')"
                    "item/qfu_sourcefamily" = "@outputs('Compose_Source_Family')"
                    "item/qfu_sourcefilename" = "@items('Apply_to_each_Freight_Attachment')?['name']"
                    "item/qfu_status" = "queued"
                    "item/qfu_insertedcount" = 0
                    "item/qfu_updatedcount" = 0
                    "item/qfu_startedon" = "@utcNow()"
                    "item/qfu_triggerflow" = $Flow.FlowName
                    "item/qfu_notes" = "Queued from the configured shared mailbox folder. Hosted freight parser call is pending."
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
                  operationMetadataId = $batchMetadataId
                }
              }
              Invoke_Hosted_Freight_Processor = [ordered]@{
                type = "Http"
                inputs = [ordered]@{
                  method = "POST"
                  uri = "@parameters('qfu_Freight_HostedParserUrl')"
                  headers = [ordered]@{
                    "Content-Type" = "application/json"
                    "x-functions-key" = "@parameters('qfu_Freight_HostedParserKey')"
                  }
                  body = [ordered]@{
                    document = [ordered]@{
                      source_id = "@outputs('Compose_Source_Id')"
                      branch_code = "@parameters('qfu_Freight_BranchCode')"
                      branch_slug = "@parameters('qfu_Freight_BranchSlug')"
                      region_slug = "@parameters('qfu_Freight_RegionSlug')"
                      source_family = "@outputs('Compose_Source_Family')"
                      source_filename = "@items('Apply_to_each_Freight_Attachment')?['name']"
                      raw_content_base64 = "@base64(base64ToBinary(items('Apply_to_each_Freight_Attachment')?['contentBytes']))"
                    }
                  }
                }
                runAfter = [ordered]@{
                  Create_Ingestion_Batch = @("Succeeded")
                }
                metadata = [ordered]@{
                  operationMetadataId = $hostedInvokeMetadataId
                }
              }
              Update_Raw_Document_Processed = [ordered]@{
                type = "OpenApiConnection"
                inputs = [ordered]@{
                  parameters = [ordered]@{
                    entityName = "qfu_rawdocuments"
                    recordId = "@outputs('Create_Raw_Document')?['body/qfu_rawdocumentid']"
                    "item/qfu_status" = "@coalesce(body('Invoke_Hosted_Freight_Processor')?['status'], 'processed')"
                    "item/qfu_processingnotes" = "@coalesce(body('Invoke_Hosted_Freight_Processor')?['batch_note'], 'Hosted freight parser completed.')"
                    "item/qfu_processedon" = "@utcNow()"
                  }
                  host = [ordered]@{
                    apiId = "/providers/Microsoft.PowerApps/apis/shared_commondataserviceforapps"
                    operationId = "UpdateOnlyRecord"
                    connectionName = "shared_commondataserviceforapps-1"
                  }
                }
                runAfter = [ordered]@{
                  Invoke_Hosted_Freight_Processor = @("Succeeded")
                }
                metadata = [ordered]@{
                  operationMetadataId = $rawProcessedMetadataId
                }
              }
              Update_Ingestion_Batch_Processed = [ordered]@{
                type = "OpenApiConnection"
                inputs = [ordered]@{
                  parameters = [ordered]@{
                    entityName = "qfu_ingestionbatchs"
                    recordId = "@outputs('Create_Ingestion_Batch')?['body/qfu_ingestionbatchid']"
                    "item/qfu_status" = "@coalesce(body('Invoke_Hosted_Freight_Processor')?['status'], 'processed')"
                    "item/qfu_insertedcount" = "@int(coalesce(body('Invoke_Hosted_Freight_Processor')?['inserted'], 0))"
                    "item/qfu_updatedcount" = "@int(coalesce(body('Invoke_Hosted_Freight_Processor')?['updated'], 0))"
                    "item/qfu_completedon" = "@utcNow()"
                    "item/qfu_notes" = "@coalesce(body('Invoke_Hosted_Freight_Processor')?['batch_note'], 'Hosted freight parser completed.')"
                  }
                  host = [ordered]@{
                    apiId = "/providers/Microsoft.PowerApps/apis/shared_commondataserviceforapps"
                    operationId = "UpdateOnlyRecord"
                    connectionName = "shared_commondataserviceforapps-1"
                  }
                }
                runAfter = [ordered]@{
                  Invoke_Hosted_Freight_Processor = @("Succeeded")
                }
                metadata = [ordered]@{
                  operationMetadataId = $batchProcessedMetadataId
                }
              }
              Update_Raw_Document_Error = [ordered]@{
                type = "OpenApiConnection"
                inputs = [ordered]@{
                  parameters = [ordered]@{
                    entityName = "qfu_rawdocuments"
                    recordId = "@outputs('Create_Raw_Document')?['body/qfu_rawdocumentid']"
                    "item/qfu_status" = "error"
                    "item/qfu_processingnotes" = "@concat('Hosted freight parser invocation failed for ', items('Apply_to_each_Freight_Attachment')?['name'], '. Review the flow run and hosted parser logs.')"
                    "item/qfu_processedon" = "@utcNow()"
                  }
                  host = [ordered]@{
                    apiId = "/providers/Microsoft.PowerApps/apis/shared_commondataserviceforapps"
                    operationId = "UpdateOnlyRecord"
                    connectionName = "shared_commondataserviceforapps-1"
                  }
                }
                runAfter = [ordered]@{
                  Invoke_Hosted_Freight_Processor = @("Failed", "TimedOut")
                }
                metadata = [ordered]@{
                  operationMetadataId = $rawErrorMetadataId
                }
              }
              Update_Ingestion_Batch_Error = [ordered]@{
                type = "OpenApiConnection"
                inputs = [ordered]@{
                  parameters = [ordered]@{
                    entityName = "qfu_ingestionbatchs"
                    recordId = "@outputs('Create_Ingestion_Batch')?['body/qfu_ingestionbatchid']"
                    "item/qfu_status" = "error"
                    "item/qfu_insertedcount" = 0
                    "item/qfu_updatedcount" = 0
                    "item/qfu_completedon" = "@utcNow()"
                    "item/qfu_notes" = "@concat('Hosted freight parser invocation failed for ', items('Apply_to_each_Freight_Attachment')?['name'], '. Review the flow run and hosted parser logs.')"
                  }
                  host = [ordered]@{
                    apiId = "/providers/Microsoft.PowerApps/apis/shared_commondataserviceforapps"
                    operationId = "UpdateOnlyRecord"
                    connectionName = "shared_commondataserviceforapps-1"
                  }
                }
                runAfter = [ordered]@{
                  Invoke_Hosted_Freight_Processor = @("Failed", "TimedOut")
                }
                metadata = [ordered]@{
                  operationMetadataId = $batchErrorMetadataId
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

function New-ArchiveWorkflowJson {
  param([object]$Flow)

  $listMetadataId = [guid]::NewGuid().Guid
  $filterMetadataId = [guid]::NewGuid().Guid
  $updateMetadataId = [guid]::NewGuid().Guid

  $jsonObject = [ordered]@{
    properties = [ordered]@{
      connectionReferences = [ordered]@{
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
        }
        triggers = [ordered]@{
          Recurrence = [ordered]@{
            type = "Recurrence"
            recurrence = [ordered]@{
              interval = 1
              frequency = "Day"
              timeZone = "Mountain Standard Time"
              schedule = [ordered]@{
                hours = @(5)
                minutes = @(30)
              }
            }
          }
        }
        actions = [ordered]@{
          List_Freight_Work_Items = [ordered]@{
            type = "OpenApiConnection"
            inputs = [ordered]@{
              parameters = [ordered]@{
                entityName = "qfu_freightworkitems"
                '$select' = "qfu_freightworkitemid,qfu_status,qfu_lastactivityon,qfu_commentupdatedon,qfu_claimedon,qfu_lastseenon,qfu_isarchived,createdon,modifiedon"
                '$top' = 5000
              }
              host = [ordered]@{
                apiId = "/providers/Microsoft.PowerApps/apis/shared_commondataserviceforapps"
                operationId = "ListRecords"
                connectionName = "shared_commondataserviceforapps-1"
              }
            }
            runAfter = [ordered]@{}
            metadata = [ordered]@{
              operationMetadataId = $listMetadataId
            }
          }
          Filter_Archive_Candidates = [ordered]@{
            type = "Query"
            inputs = [ordered]@{
              from = "@body('List_Freight_Work_Items')?['value']"
              where = "@and(or(equals(toLower(coalesce(item()?['qfu_status'], '')), 'closed'), equals(toLower(coalesce(item()?['qfu_status'], '')), 'no action')), not(equals(coalesce(item()?['qfu_isarchived'], false), true)), lessOrEquals(ticks(coalesce(item()?['qfu_lastactivityon'], item()?['qfu_commentupdatedon'], item()?['qfu_claimedon'], item()?['qfu_lastseenon'], item()?['modifiedon'], item()?['createdon'])), ticks(addDays(utcNow(), -60))))"
            }
            runAfter = [ordered]@{
              List_Freight_Work_Items = @("Succeeded")
            }
            metadata = [ordered]@{
              operationMetadataId = $filterMetadataId
            }
          }
          Apply_to_each_Archive_Candidate = [ordered]@{
            type = "Foreach"
            foreach = "@body('Filter_Archive_Candidates')"
            runAfter = [ordered]@{
              Filter_Archive_Candidates = @("Succeeded")
            }
            actions = [ordered]@{
              Archive_Freight_Row = [ordered]@{
                type = "OpenApiConnection"
                inputs = [ordered]@{
                  parameters = [ordered]@{
                    entityName = "qfu_freightworkitems"
                    recordId = "@items('Apply_to_each_Archive_Candidate')?['qfu_freightworkitemid']"
                    "item/qfu_isarchived" = $true
                    "item/qfu_archivedon" = "@utcNow()"
                  }
                  host = [ordered]@{
                    apiId = "/providers/Microsoft.PowerApps/apis/shared_commondataserviceforapps"
                    operationId = "UpdateOnlyRecord"
                    connectionName = "shared_commondataserviceforapps-1"
                  }
                }
                runAfter = [ordered]@{}
                metadata = [ordered]@{
                  operationMetadataId = $updateMetadataId
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

function New-WorkflowJson {
  param([object]$Flow)

  if ($Flow.Type -eq "archive") {
    return New-ArchiveWorkflowJson -Flow $Flow
  }
  return New-IngressWorkflowJson -Flow $Flow
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

if ($shouldImportToTarget) {
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
