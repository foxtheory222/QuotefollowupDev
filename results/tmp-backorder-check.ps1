Import-Module Microsoft.Xrm.Data.Powershell
$conn = Connect-CrmOnline -ServerUrl 'https://orgad610d2c.crm3.dynamics.com/' -ForceOAuth -Username 'smcfarlane@applied.com'
if(-not $conn -or -not $conn.IsReady){ throw $conn.LastCrmError }
$rows = @( (Get-CrmRecords -conn $conn -EntityLogicalName 'qfu_backorder' -Fields @('qfu_backorderid','qfu_branchcode','qfu_sourceid','qfu_daysoverdue','qfu_ontimedate','qfu_totalvalue','qfu_quantity','qfu_qtynotondel','qfu_qtyondelnotpgid','qfu_active','qfu_inactiveon','createdon') -TopCount 5000).CrmRecords )
$today = Get-Date '2026-04-14'
function BoolVal($v){ if($null -eq $v){return $null}; if($v -is [bool]){return [bool]$v}; $t=([string]$v).Trim().ToLowerInvariant(); if($t -in @('true','1','yes')){return $true}; if($t -in @('false','0','no')){return $false}; return $null }
function DateVal($v){ if($null -eq $v){return $null}; try{ return [datetime]$v } catch { return $null } }
function DecVal($v){ if($null -eq $v -or [string]::IsNullOrWhiteSpace([string]$v)){ return [decimal]0}; try{return [decimal]$v}catch{return [decimal]0} }
function IsActive($r){ $inactive=DateVal $r.qfu_inactiveon; if($inactive){ return $false }; $active=BoolVal $r.qfu_active; if($null -ne $active){ return $active }; return $true }
function HasSplit($r){ return ($null -ne $r.qfu_qtynotondel -and -not [string]::IsNullOrWhiteSpace([string]$r.qfu_qtynotondel)) -or ($null -ne $r.qfu_qtyondelnotpgid -and -not [string]::IsNullOrWhiteSpace([string]$r.qfu_qtyondelnotpgid)) }
function QtyNotOnDel($r){ if(-not (HasSplit $r)){ return DecVal $r.qfu_quantity }; return DecVal $r.qfu_qtynotondel }
function QtyOnDel($r){ if(-not (HasSplit $r)){ return [decimal]0 }; return DecVal $r.qfu_qtyondelnotpgid }
function DaysBetween($later,$earlier){ return [math]::Max(0,[int][math]::Floor(($later.Date - $earlier.Date).TotalDays)) }
function OverdueDays($r){ if($null -ne $r.qfu_daysoverdue -and -not [string]::IsNullOrWhiteSpace([string]$r.qfu_daysoverdue)){ return [math]::Max(0,[int]$r.qfu_daysoverdue) }; $d=DateVal $r.qfu_ontimedate; if($d -and $d.Date -lt $today.Date){ return DaysBetween $today $d }; return 0 }
$result = foreach($branch in '4171','4172','4173'){
  $branchRows = @($rows | Where-Object { [string]$_.qfu_branchcode -eq $branch })
  $activeRows = @($branchRows | Where-Object { IsActive $_ })
  $actionable = @($activeRows | Where-Object { (QtyNotOnDel $_) -gt 0 -or (QtyOnDel $_) -gt 0 })
  $overdue = @($actionable | Where-Object { (OverdueDays $_) -gt 0 })
  [pscustomobject]@{ branch = $branch; total = @($branchRows).Count; active = @($activeRows).Count; actionable = @($actionable).Count; overdue = @($overdue).Count }
}
[System.IO.File]::WriteAllText('C:\Dev\QuoteFollowUpComplete\results\tmp-backorder-check.json', ($result | ConvertTo-Json -Depth 4), [System.Text.UTF8Encoding]::new($false))