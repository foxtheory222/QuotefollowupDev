param(
    [string]$EnvironmentUrl = 'https://orga632edd5.crm3.dynamics.com',
    [string]$SolutionUniqueName = 'qfu_revenuefollowupworkbench',
    [string]$FlowName = 'QFU Queue Handoff - Workbench',
    [string]$OutputPath = 'results\phase5-final-fix-queue-handoff-flow.json'
)

$ErrorActionPreference = 'Stop'

function Get-AccessToken {
    $tokenObject = Get-AzAccessToken -ResourceUrl "$EnvironmentUrl/"
    $token = $tokenObject.Token
    if ($token -is [System.Security.SecureString]) {
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($token)
        try {
            $token = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
        }
        finally {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
    }
    return $token
}

$headers = @{
    Authorization      = "Bearer $(Get-AccessToken)"
    Accept             = 'application/json'
    'Content-Type'     = 'application/json; charset=utf-8'
    'OData-MaxVersion' = '4.0'
    'OData-Version'    = '4.0'
}
$readHeaders = $headers.Clone()
$readHeaders.Remove('Content-Type')

function Invoke-DvGet {
    param([string]$RelativeUrl)
    Invoke-RestMethod -Method Get -Uri "$EnvironmentUrl/api/data/v9.2/$RelativeUrl" -Headers $readHeaders
}

function Invoke-DvPost {
    param([string]$RelativeUrl, [object]$Body)
    Invoke-RestMethod -Method Post -Uri "$EnvironmentUrl/api/data/v9.2/$RelativeUrl" -Headers $headers -Body ($Body | ConvertTo-Json -Depth 100)
}

function Invoke-DvPatch {
    param([string]$RelativeUrl, [object]$Body)
    Invoke-RestMethod -Method Patch -Uri "$EnvironmentUrl/api/data/v9.2/$RelativeUrl" -Headers $headers -Body ($Body | ConvertTo-Json -Depth 100)
}

function Get-AllRows {
    param([string]$RelativeUrl)
    $rows = @()
    $url = "$EnvironmentUrl/api/data/v9.2/$RelativeUrl"
    do {
        $response = Invoke-RestMethod -Method Get -Uri $url -Headers $readHeaders
        $rows += @($response.value)
        $url = $response.'@odata.nextLink'
    } while ($url)
    return $rows
}

function Escape-ODataString {
    param([string]$Value)
    return $Value.Replace("'", "''")
}

$clientData = @{
    properties = @{
        connectionReferences = @{
            shared_commondataserviceforapps = @{
                runtimeSource = 'embedded'
                connection    = @{
                    connectionReferenceLogicalName = 'qfu_shared_commondataserviceforapps'
                }
                api           = @{
                    name = 'shared_commondataserviceforapps'
                }
            }
        }
        definition = @{
            '$schema'       = 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
            contentVersion = '1.0.0.0'
            parameters     = @{
                '$connections'    = @{
                    defaultValue = @{}
                    type         = 'Object'
                }
                '$authentication' = @{
                    defaultValue = @{}
                    type         = 'SecureObject'
                }
            }
            triggers       = @{
                'When_a_work_item_action_is_added_or_modified' = @{
                    type     = 'OpenApiConnectionWebhook'
                    metadata = @{
                        operationMetadataId = ([guid]::NewGuid()).ToString()
                    }
                    inputs   = @{
                        host           = @{
                            connectionName = 'shared_commondataserviceforapps'
                            operationId    = 'SubscribeWebhookTrigger'
                            apiId          = '/providers/Microsoft.PowerApps/apis/shared_commondataserviceforapps'
                        }
                        parameters     = @{
                            'subscriptionRequest/message'    = 4
                            'subscriptionRequest/entityname' = 'qfu_workitemaction'
                            'subscriptionRequest/scope'      = 4
                        }
                        authentication = "@parameters('$authentication')"
                    }
                }
            }
            actions        = @{
                'Condition_Is_Queue_Handoff' = @{
                    runAfter   = @{}
                    type       = 'If'
                    expression = @{
                        and = @(
                            @{
                                equals = @(
                                    "@triggerOutputs()?['body/qfu_actiontype']",
                                    985010012
                                )
                            },
                            @{
                                or = @(
                                    @{
                                        equals = @(
                                            "@toUpper(coalesce(triggerOutputs()?['body/qfu_outcome'], ''))",
                                            'TSR'
                                        )
                                    },
                                    @{
                                        equals = @(
                                            "@toUpper(coalesce(triggerOutputs()?['body/qfu_outcome'], ''))",
                                            'CSSR'
                                        )
                                    }
                                )
                            },
                            @{
                                not = @{
                                    equals = @(
                                        "@triggerOutputs()?['body/_qfu_workitem_value']",
                                        $null
                                    )
                                }
                            }
                        )
                    }
                    actions    = @{
                        'List_parent_work_item' = @{
                            type     = 'OpenApiConnection'
                            runAfter = @{}
                            metadata = @{
                                operationMetadataId = ([guid]::NewGuid()).ToString()
                            }
                            inputs   = @{
                                host           = @{
                                    connectionName = 'shared_commondataserviceforapps'
                                    operationId    = 'ListRecords'
                                    apiId          = '/providers/Microsoft.PowerApps/apis/shared_commondataserviceforapps'
                                }
                                parameters     = @{
                                    entityName = 'qfu_workitems'
                                    '$select'  = 'qfu_workitemid,qfu_workitemnumber,qfu_status,qfu_queuehandoffcount,_qfu_tsrstaff_value,_qfu_cssrstaff_value,qfu_completedattempts,qfu_lastfollowedupon'
                                    '$filter'  = "qfu_workitemid eq @{triggerOutputs()?['body/_qfu_workitem_value']}"
                                    '$top'     = 1
                                }
                                authentication = "@parameters('$authentication')"
                            }
                        }
                        'Compose_Target_Role' = @{
                            type     = 'Compose'
                            runAfter = @{
                                'List_parent_work_item' = @('Succeeded')
                            }
                            inputs   = "@toUpper(coalesce(triggerOutputs()?['body/qfu_outcome'], ''))"
                        }
                        'Compose_Target_Staff_Id' = @{
                            type     = 'Compose'
                            runAfter = @{
                                'Compose_Target_Role' = @('Succeeded')
                            }
                            inputs   = "@if(equals(outputs('Compose_Target_Role'), 'TSR'), first(outputs('List_parent_work_item')?['body/value'])?['_qfu_tsrstaff_value'], first(outputs('List_parent_work_item')?['body/value'])?['_qfu_cssrstaff_value'])"
                        }
                        'Condition_Target_Staff_Mapped' = @{
                            type       = 'If'
                            runAfter   = @{
                                'Compose_Target_Staff_Id' = @('Succeeded')
                            }
                            expression = @{
                                and = @(
                                    @{
                                        greater = @(
                                            "@length(outputs('List_parent_work_item')?['body/value'])",
                                            0
                                        )
                                    },
                                    @{
                                        not = @{
                                            equals = @(
                                                "@outputs('Compose_Target_Staff_Id')",
                                                $null
                                            )
                                        }
                                    },
                                    @{
                                        not = @{
                                            or = @(
                                                @{
                                                    equals = @(
                                                        "@first(outputs('List_parent_work_item')?['body/value'])?['qfu_status']",
                                                        985010008
                                                    )
                                                },
                                                @{
                                                    equals = @(
                                                        "@first(outputs('List_parent_work_item')?['body/value'])?['qfu_status']",
                                                        985010009
                                                    )
                                                },
                                                @{
                                                    equals = @(
                                                        "@first(outputs('List_parent_work_item')?['body/value'])?['qfu_status']",
                                                        985010010
                                                    )
                                                }
                                            )
                                        }
                                    }
                                )
                            }
                            actions    = @{
                                'List_target_staff' = @{
                                    type     = 'OpenApiConnection'
                                    runAfter = @{}
                                    metadata = @{
                                        operationMetadataId = ([guid]::NewGuid()).ToString()
                                    }
                                    inputs   = @{
                                        host           = @{
                                            connectionName = 'shared_commondataserviceforapps'
                                            operationId    = 'ListRecords'
                                            apiId          = '/providers/Microsoft.PowerApps/apis/shared_commondataserviceforapps'
                                        }
                                        parameters     = @{
                                            entityName = 'qfu_staffs'
                                            '$select'  = 'qfu_staffid,qfu_name,qfu_staffnumber'
                                            '$filter'  = "qfu_staffid eq @{outputs('Compose_Target_Staff_Id')}"
                                            '$top'     = 1
                                        }
                                        authentication = "@parameters('$authentication')"
                                    }
                                }
                                'Update_work_item_queue' = @{
                                    type     = 'OpenApiConnection'
                                    runAfter = @{
                                        'List_target_staff' = @('Succeeded')
                                    }
                                    metadata = @{
                                        operationMetadataId = ([guid]::NewGuid()).ToString()
                                    }
                                    inputs   = @{
                                        host           = @{
                                            connectionName = 'shared_commondataserviceforapps'
                                            operationId    = 'UpdateOnlyRecord'
                                            apiId          = '/providers/Microsoft.PowerApps/apis/shared_commondataserviceforapps'
                                        }
                                        parameters     = @{
                                            entityName                                  = 'qfu_workitems'
                                            recordId                                    = "@triggerOutputs()?['body/_qfu_workitem_value']"
                                            'item/qfu_CurrentQueueOwnerStaff@odata.bind' = "@{concat('/qfu_staffs(', outputs('Compose_Target_Staff_Id'), ')')}"
                                            'item/qfu_currentqueuerole'                 = "@if(equals(outputs('Compose_Target_Role'), 'TSR'), 985020000, 985020001)"
                                            'item/qfu_currentqueueroletext'             = "@outputs('Compose_Target_Role')"
                                            'item/qfu_currentqueueownerstaffkey'        = "@coalesce(first(outputs('List_target_staff')?['body/value'])?['qfu_staffnumber'], outputs('Compose_Target_Staff_Id'))"
                                            'item/qfu_currentqueueownername'            = "@first(outputs('List_target_staff')?['body/value'])?['qfu_name']"
                                            'item/qfu_queueassignedon'                  = "@utcNow()"
                                            'item/qfu_queuehandoffreason'               = "@coalesce(triggerOutputs()?['body/qfu_notes'], concat('Routed to ', outputs('Compose_Target_Role'), ' from Workbench'))"
                                            'item/qfu_queuehandoffcount'                = "@add(coalesce(first(outputs('List_parent_work_item')?['body/value'])?['qfu_queuehandoffcount'], 0), 1)"
                                        }
                                        authentication = "@parameters('$authentication')"
                                    }
                                }
                            }
                            else       = @{
                                actions = @{
                                    'Compose_Handoff_Skipped' = @{
                                        type   = 'Compose'
                                        inputs = 'Queue handoff skipped because target staff is missing or work item is terminal.'
                                    }
                                }
                            }
                        }
                    }
                    else       = @{
                        actions = @{
                            'Compose_Not_Handoff' = @{
                                type   = 'Compose'
                                inputs = 'Not a queue handoff action.'
                            }
                        }
                    }
                }
            }
            outputs        = @{}
        }
    }
    schemaVersion = '1.0.0.0'
}

$escapedName = Escape-ODataString $FlowName
$existing = Get-AllRows "workflows?`$select=workflowid,name,statecode,statuscode,clientdata&`$filter=category eq 5 and name eq '$escapedName'&`$top=1" | Select-Object -First 1
$clientDataJson = $clientData | ConvertTo-Json -Depth 100 -Compress
$mode = 'created'
$workflowId = $null

if ($existing) {
    $workflowId = $existing.workflowid
    if ([int]$existing.statecode -eq 1) {
        Invoke-DvPatch "workflows($workflowId)" @{ statecode = 0; statuscode = 1 } | Out-Null
        Start-Sleep -Seconds 4
    }
    Invoke-DvPatch "workflows($workflowId)" @{
        name          = $FlowName
        description   = 'Phase 5 Workbench queue handoff flow. Triggered by non-attempt Assignment/Reassignment action rows from the Workbench. Updates queue owner helper fields and true queue fields. Sends no alerts.'
        clientdata    = $clientDataJson
        category      = 5
        type          = 1
        primaryentity = 'none'
    } | Out-Null
    $mode = 'updated'
}
else {
    $response = Invoke-WebRequest -Method Post -Uri "$EnvironmentUrl/api/data/v9.2/workflows" -Headers $headers -Body (@{
        category      = 5
        name          = $FlowName
        type          = 1
        description   = 'Phase 5 Workbench queue handoff flow. Triggered by non-attempt Assignment/Reassignment action rows from the Workbench. Updates queue owner helper fields and true queue fields. Sends no alerts.'
        primaryentity = 'none'
        clientdata    = $clientDataJson
    } | ConvertTo-Json -Depth 100)
    $entityId = $response.Headers['OData-EntityId']
    if ($entityId -match '\(([^)]+)\)') {
        $workflowId = $Matches[1]
    }
    if (-not $workflowId) {
        $created = Get-AllRows "workflows?`$select=workflowid,name&`$filter=category eq 5 and name eq '$escapedName'&`$top=1" | Select-Object -First 1
        $workflowId = $created.workflowid
    }
}

if (-not $workflowId) {
    throw "Could not resolve workflow id for '$FlowName'."
}

$solutionAdded = $false
try {
    Invoke-DvPost 'AddSolutionComponent' @{
        ComponentType             = 29
        ComponentId               = $workflowId
        SolutionUniqueName        = $SolutionUniqueName
        AddRequiredComponents     = $true
        DoNotIncludeSubcomponents = $false
    } | Out-Null
    $solutionAdded = $true
}
catch {
    $solutionAdded = $false
}

Invoke-DvPatch "workflows($workflowId)" @{ statecode = 1; statuscode = 2 } | Out-Null
Start-Sleep -Seconds 8

$after = Invoke-DvGet "workflows($workflowId)?`$select=workflowid,name,statecode,statuscode,category,type,primaryentity,clientdata"

$result = [ordered]@{
    environmentUrl = $EnvironmentUrl
    timestamp = (Get-Date).ToString('o')
    flowName = $FlowName
    workflowId = $workflowId
    mode = $mode
    solutionUniqueName = $SolutionUniqueName
    addedToSolution = $solutionAdded
    statecode = $after.statecode
    statuscode = $after.statuscode
    trigger = 'Dataverse qfu_workitemaction create/update; action type Assignment/Reassignment with outcome TSR or CSSR'
    note = 'This uses a dedicated server-side flow triggered by the Workbench handoff action row. It avoids direct custom page patching of queue lookup/choice fields and sends no alerts.'
}

$directory = Split-Path -Parent $OutputPath
if ($directory) {
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
}
$result | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
$result | ConvertTo-Json -Depth 20
