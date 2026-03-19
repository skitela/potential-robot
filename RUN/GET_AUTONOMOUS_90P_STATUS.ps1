Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$latestJson = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\autonomous_90p_latest.json"
if (-not (Test-Path -LiteralPath $latestJson)) {
    throw "Autonomous 90P status not found yet: $latestJson"
}

$status = Get-Content -LiteralPath $latestJson -Raw -Encoding UTF8 | ConvertFrom-Json

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("=== AUTONOMOUS 90P STATUS ===")
$lines.Add("")
$lines.Add(("- generated_at_local: {0}" -f $status.generated_at_local))
$lines.Add(("- cycle: {0}" -f $status.cycle))
$lines.Add("")
$lines.Add("Actions:")
foreach ($prop in $status.actions.PSObject.Properties) {
    $lines.Add(("- {0}: {1}" -f $prop.Name, $prop.Value))
}
$lines.Add("")
$lines.Add("Processes:")
foreach ($proc in @($status.processes)) {
    $lines.Add(("- {0} #{1}: priority={2}, ram_mb={3}" -f $proc.process, $proc.id, $proc.priority, $proc.ram_mb))
}
$lines.Add("")
$lines.Add("Top priority:")
foreach ($item in @($status.top_priority)) {
    $lines.Add(("- #{0} {1}: score={2}, trust={3}, cost={4}, action={5}" -f
        $item.rank,
        $item.symbol_alias,
        $item.priority_score,
        $item.trust_state,
        $item.cost_state,
        $item.recommended_action))
}
$lines -join "`r`n"
