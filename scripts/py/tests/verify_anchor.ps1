
$path = "c:\Users\fg8n8x\Desktop\eta\eta_1_15\eta_master\RGAAK2000.WAT"
if (Test-Path $path) {
    $line = (Get-Content $path -TotalCount 8 | Select-Object -Last 1)
    $ruler1 = ""
    $ruler2 = ""
    for ($i=0; $i -lt 100; $i++) {
        $ruler1 += ($i % 10).ToString()
        if ($i % 10 -eq 0) {
            $ruler2 += ($i / 10).ToString()
        } else {
            $ruler2 += " "
        }
    }
    Write-Host "Visual Ruler:"
    Write-Host $ruler2
    Write-Host $ruler1
    Write-Host $line.Substring(0, [Math]::Min(100, $line.Length))
    
    $char28 = $line[27]
    $char29 = $line[28]
    Write-Host "`nAnalysis:"
    Write-Host "Index 27 (Character 28): '$char28'"
    Write-Host "Index 28 (Character 29): '$char29'"
} else {
    Write-Host "File not found: $path"
}
