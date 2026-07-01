
$path = "c:\Users\fg8n8x\Desktop\eta\eta_1_15\eta_master\RGAAK2000.WAT"
if (Test-Path $path) {
    $line6 = (Get-Content $path -TotalCount 6 | Select-Object -Last 1)
    $line8 = (Get-Content $path -TotalCount 8 | Select-Object -Last 1)
    $line7 = (Get-Content $path -TotalCount 7 | Select-Object -Last 1)

    $idx = $line6.IndexOf("CAPDENSITY")
    Write-Host "In Line 6 (Header), 'CAPDENSITY' starts at index: $idx"
    Write-Host "In Line 7 (Units), char at index $idx is: '$($line7[$idx])'"
    Write-Host "In Line 8 (Data), char at index $idx is: '$($line8[$idx])'"
    
    Write-Host "`nNeighbors in Line 8:"
    Write-Host "Index $($idx-1): '$($line8[$idx-1])'"
    Write-Host "Index $idx: '$($line8[$idx])'"
    Write-Host "Index $($idx+1): '$($line8[$idx+1])'"
    
    Write-Host "`nFirst 15 chars from index $idx in Line 8: '$($line8.Substring($idx, 15))'"
}
