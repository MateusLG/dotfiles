<#
.SYNOPSIS
  Instala a Nerd Font MesloLGS NF (recomendada pelo powerlevel10k) pro usuario atual no Windows.

.DESCRIPTION
  Baixa as 4 variantes (Regular, Bold, Italic, Bold Italic) do repo romkatv/powerlevel10k-media,
  copia pra %LOCALAPPDATA%\Microsoft\Windows\Fonts e registra em HKCU. Nao precisa de admin.
  Idempotente: pula arquivos ja instalados.

.NOTES
  Rodar no host Windows (nao dentro do WSL):
      powershell -ExecutionPolicy Bypass -File \\wsl$\archlinux\home\<user>\dotfiles\wsl\install-nerdfonts.ps1

  Apos instalar, configurar a fonte "MesloLGS NF" no terminal (Windows Terminal, VSCode, etc)
  e rodar 'p10k configure' dentro do WSL.
#>

$ErrorActionPreference = 'Stop'

$dest   = "$env:LOCALAPPDATA\Microsoft\Windows\Fonts"
$regKey = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'
$base   = 'https://github.com/romkatv/powerlevel10k-media/raw/master/'

$fonts = @{
    'MesloLGS NF Regular.ttf'     = 'MesloLGS NF (TrueType)'
    'MesloLGS NF Bold.ttf'        = 'MesloLGS NF Bold (TrueType)'
    'MesloLGS NF Italic.ttf'      = 'MesloLGS NF Italic (TrueType)'
    'MesloLGS NF Bold Italic.ttf' = 'MesloLGS NF Bold Italic (TrueType)'
}

New-Item -ItemType Directory -Force -Path $dest | Out-Null
if (-not (Test-Path $regKey)) { New-Item -Path $regKey -Force | Out-Null }

foreach ($file in $fonts.Keys) {
    $dst     = Join-Path $dest $file
    $regName = $fonts[$file]

    $existsFile = Test-Path $dst
    $existsReg  = (Get-ItemProperty -Path $regKey -Name $regName -ErrorAction SilentlyContinue) -ne $null

    if ($existsFile -and $existsReg) {
        Write-Host "[skip] $regName ja instalada"
        continue
    }

    if (-not $existsFile) {
        $url = $base + ($file -replace ' ', '%20')
        Write-Host "[download] $file"
        Invoke-WebRequest -Uri $url -OutFile $dst -UseBasicParsing
    }

    New-ItemProperty -Path $regKey -Name $regName -Value $dst -PropertyType String -Force | Out-Null
    Write-Host "[ok] $regName"
}

Write-Host ''
Write-Host 'Fontes prontas. Configure "MesloLGS NF" no perfil do seu terminal e reabra-o.'
