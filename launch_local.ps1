# launch_local.ps1 — arranca o TradingView Desktop com CDP (porta 9222) para o MCP tradingview.
#
# Porquê uma cópia local: lançado a partir de C:\Program Files\WindowsApps a flag
# --remote-debugging-port é ignorada (ou dá "Access is denied"). A mesma app corrida
# a partir de uma pasta normal abre a porta e mantém o login e os layouts.
# Convenção igual à do tv_launch do upstream (src/core/health.js, _copyMsixPackageLocal):
# uma cópia por versão em %LOCALAPPDATA%\tradingview-mcp\<pasta do pacote>, e as
# versões antigas são apagadas quando a Store atualiza a app.
#
# Uso (na raiz do repositório):  powershell -ExecutionPolicy Bypass -File .\launch_local.ps1

param([int]$Porta = 9222)

$ErrorActionPreference = 'Stop'

# 1. Encontrar o pacote MSIX (nome atual e o nome antigo da Store).
$pkg = Get-AppxPackage -Name 'TradingView.Desktop' -ErrorAction SilentlyContinue
if (-not $pkg) { $pkg = Get-AppxPackage -Name '31178TradingViewInc.TradingView' -ErrorAction SilentlyContinue }
if (-not $pkg) { throw 'TradingView Desktop não encontrado (Get-AppxPackage não devolveu nenhum pacote).' }
$pkg = $pkg | Sort-Object Version -Descending | Select-Object -First 1
$origem = $pkg.InstallLocation
$nomePasta = Split-Path $origem -Leaf

# 2. Garantir a cópia local desta versão; apagar cópias de versões antigas.
$raiz = Join-Path $env:LOCALAPPDATA 'tradingview-mcp'
$destino = Join-Path $raiz $nomePasta
$exe = Join-Path $destino 'TradingView.exe'
if (-not (Test-Path $exe)) {
    New-Item -ItemType Directory -Force $raiz | Out-Null
    Get-ChildItem $raiz -Directory | Where-Object { $_.Name -ne $nomePasta -and $_.Name -match '^TradingView' } |
        ForEach-Object { Write-Host "A apagar cópia antiga: $($_.Name)"; Remove-Item $_.FullName -Recurse -Force }
    Write-Host "A copiar $nomePasta para $raiz (só na 1.ª vez por versão, ~330 MB)..."
    Copy-Item $origem $destino -Recurse -Force
}

# 3. A app só aceita uma instância: fechar a que estiver aberta sem CDP.
$abertos = Get-Process -Name 'TradingView' -ErrorAction SilentlyContinue
if ($abertos) {
    Write-Host "A fechar o TradingView aberto ($($abertos.Count) processos)..."
    $abertos | Stop-Process -Force
    Start-Sleep -Seconds 2
}

# 4. Lançar com a porta de debug e esperar que ela abra (até 30 s).
Start-Process -FilePath $exe -ArgumentList "--remote-debugging-port=$Porta"
$limite = (Get-Date).AddSeconds(30)
do {
    Start-Sleep -Milliseconds 500
    $escuta = Get-NetTCPConnection -LocalPort $Porta -State Listen -ErrorAction SilentlyContinue
} until ($escuta -or (Get-Date) -gt $limite)

if (-not $escuta) { throw "A porta $Porta não abriu em 30 s." }
$enderecos = ($escuta | Select-Object -ExpandProperty LocalAddress -Unique) -join ', '
Write-Host "OK: TradingView $($pkg.Version) com CDP na porta $Porta (a escutar em: $enderecos)"
if ($escuta | Where-Object { $_.LocalAddress -notin '127.0.0.1', '::1' }) {
    Write-Warning "A porta $Porta está exposta para lá do localhost — rever antes de continuar."
}
