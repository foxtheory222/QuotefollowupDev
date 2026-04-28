create-southern-alberta-pilot-flow-solution.ps1:376:$definition.triggers.Shared_Mailbox_New_Email.runtimeConfiguration = [ordered]@{
create-southern-alberta-pilot-flow-solution.ps1:378:runs = 1
create-southern-alberta-pilot-flow-solution.ps1:385:$budgetActions.Get_Budget_Goal_From_Archives.inputs.parameters.'$filter' = "qfu_branchcode eq '@{parameters('qfu_QFU_BranchCode')}' and qfu_month eq @{int(formatDateTime(convertTimeZone(utcNow(), 'UTC', 'Mountain Standard Time'), 'MM'))} and qfu_fiscalyear eq '@{parameters('qfu_QFU_ActiveFiscalYear')}'"
create-southern-alberta-pilot-flow-solution.ps1:387:$budgetActions.Get_Active_Budget.inputs.parameters.'$filter' = "qfu_isactive eq false and qfu_branchcode eq '@{parameters('qfu_QFU_BranchCode')}' and qfu_sourcefamily eq 'SA1300'"
create-southern-alberta-pilot-flow-solution.ps1:390:$budgetActions.Get_Current_Month_Budget_Record.inputs.parameters.'$filter' = "qfu_branchcode eq '@{parameters('qfu_QFU_BranchCode')}' and qfu_sourcefamily eq 'SA1300' and qfu_sourceid eq '@{concat(parameters('qfu_QFU_BranchCode'), '|SA1300|', formatDateTime(convertTimeZone(utcNow(), 'UTC', 'Mountain Standard Time'), 'yyyy-MM'))}'"
create-southern-alberta-pilot-flow-solution.ps1:401:Set-FieldValue -Map $parameters -Name "item/qfu_sourceid" -Value "@concat(parameters('qfu_QFU_BranchCode'), '|SA1300|', formatDateTime(convertTimeZone(utcNow(), 'UTC', 'Mountain Standard Time'), 'yyyy-MM'))"
create-southern-alberta-pilot-flow-solution.ps1:411:Set-FieldValue -Map $itemMap -Name "qfu_isactive" -Value $false
create-southern-alberta-pilot-flow-solution.ps1:412:Set-FieldValue -Map $itemMap -Name "qfu_fiscalyear" -Value "@parameters('qfu_QFU_ActiveFiscalYear')"
create-southern-alberta-pilot-flow-solution.ps1:429:Set-FieldValue -Map $updateCurrent -Name "qfu_sourceid" -Value "@concat(parameters('qfu_QFU_BranchCode'), '|SA1300|', formatDateTime(convertTimeZone(utcNow(), 'UTC', 'Mountain Standard Time'), 'yyyy-MM'))"
create-southern-alberta-pilot-flow-solution.ps1:430:Set-FieldValue -Map $updateCurrent -Name "qfu_isactive" -Value $false
create-southern-alberta-pilot-flow-solution.ps1:431:Set-FieldValue -Map $updateCurrent -Name "qfu_fiscalyear" -Value "@parameters('qfu_QFU_ActiveFiscalYear')"
create-southern-alberta-pilot-flow-solution.ps1:437:Set-FieldValue -Map $archiveRecord -Name "item/qfu_sourceid" -Value "@concat(parameters('qfu_QFU_BranchCode'), '|budgetarchive|', outputs('Get_Active_Budget')?['body/value']?[0]?['qfu_fiscalyear'], '|', formatNumber(outputs('Get_Active_Budget')?['body/value']?[0]?['qfu_month'], '00'))"
create-southern-alberta-pilot-flow-solution.ps1:442:Set-FieldValue -Map $archiveRecord -Name "item/qfu_fiscalyear" -Value "@outputs('Get_Active_Budget')?['body/value']?[0]?['qfu_fiscalyear']"
create-southern-alberta-pilot-flow-solution.ps1:452:$getExistingArchive.inputs.parameters.entityName = "qfu_budgetarchives"
create-southern-alberta-pilot-flow-solution.ps1:453:$getExistingArchive.inputs.parameters.'$select' = "qfu_budgetarchiveid,qfu_sourceid,qfu_branchcode,qfu_month,qfu_year,qfu_fiscalyear"
create-southern-alberta-pilot-flow-solution.ps1:454:$getExistingArchive.inputs.parameters.'$filter' = "qfu_branchcode eq '@{parameters('qfu_QFU_BranchCode')}' and qfu_month eq @{outputs('Get_Active_Budget')?['body/value']?[0]?['qfu_month']} and qfu_fiscalyear eq '@{outputs('Get_Active_Budget')?['body/value']?[0]?['qfu_fiscalyear']}'"
create-southern-alberta-pilot-flow-solution.ps1:461:$archiveUpdateAction.inputs.parameters.entityName = "qfu_budgetarchives"
create-southern-alberta-pilot-flow-solution.ps1:462:$archiveUpdateAction.inputs.parameters.recordId = "@outputs('Get_Existing_Archive_Budget')?['body/value']?[0]?['qfu_budgetarchiveid']"
create-southern-alberta-pilot-flow-solution.ps1:465:qfu_sourceid = "@concat(parameters('qfu_QFU_BranchCode'), '|budgetarchive|', outputs('Get_Active_Budget')?['body/value']?[0]?['qfu_fiscalyear'], '|', formatNumber(outputs('Get_Active_Budget')?['body/value']?[0]?['qfu_month'], '00'))"
create-southern-alberta-pilot-flow-solution.ps1:470:qfu_fiscalyear = "@outputs('Get_Active_Budget')?['body/value']?[0]?['qfu_fiscalyear']"
create-southern-alberta-pilot-flow-solution.ps1:488:"@length(outputs('Get_Existing_Archive_Budget')?['body/value'])",
create-southern-alberta-pilot-flow-solution.ps1:495:Update_Existing_Archive_Budget = $archiveUpdateAction
create-southern-alberta-pilot-flow-solution.ps1:503:Get_Existing_Archive_Budget = @("Succeeded")
create-southern-alberta-pilot-flow-solution.ps1:511:Condition_Archive_Budget_Exists = @("Succeeded")
create-southern-alberta-pilot-flow-solution.ps1:514:Get_Existing_Archive_Budget = $getExistingArchive
create-southern-alberta-pilot-flow-solution.ps1:515:Condition_Archive_Budget_Exists = $archiveExistsCondition
create-southern-alberta-pilot-flow-solution.ps1:520:Add-Note -Notes $Notes -Text "Budget flow now enforces trigger concurrency = 1, treats qfu_isactive false as active, resolves current-month rows by qfu_sourceid, and checks branch+month+fiscal year before creating qfu_budgetarchive."
Budget flow / generator hardening evidence hits for the authoritative current generator source.

Confirmed by source search:

- trigger concurrency control added (`runs = 1`)
- active budget lookup now uses `qfu_isactive eq false`
- current-month budget resolution uses deterministic `qfu_sourceid`
- current-month writes force `qfu_isactive = false`
- archive writer now uses canonical `budgetarchive` sourceid in the current generator
- archive duplicate prevention path now performs logical archive lookup before create
