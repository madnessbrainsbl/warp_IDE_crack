# Продвинутое исправление ошибок Warp Terminal для Windows
# Требует запуска от имени администратора

#Requires -RunAsAdministrator

param(
    [switch]$Force,
    [switch]$SkipBackup,
    [string]$LogFile = "$env:TEMP\warp-fix-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
)

# Настройка вывода
$Host.UI.RawUI.WindowTitle = "Warp Terminal Fix - PowerShell Edition"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Функция логирования
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    Write-Host $logEntry -ForegroundColor $(switch($Level) {
        "ERROR" { "Red" }
        "WARN" { "Yellow" }
        "SUCCESS" { "Green" }
        default { "White" }
    })
    Add-Content -Path $LogFile -Value $logEntry
}

# Функция создания бэкапа
function Backup-WarpSettings {
    if ($SkipBackup) { return }
    
    Write-Log "Создание резервной копии настроек Warp..."
    $backupPath = "$env:TEMP\warp-backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    New-Item -ItemType Directory -Path $backupPath -Force | Out-Null
    
    $warpPaths = @(
        "$env:APPDATA\Warp",
        "$env:LOCALAPPDATA\Warp",
        "$env:USERPROFILE\.warp"
    )
    
    foreach ($path in $warpPaths) {
        if (Test-Path $path) {
            $destination = Join-Path $backupPath (Split-Path $path -Leaf)
            Copy-Item $path $destination -Recurse -Force -ErrorAction SilentlyContinue
            Write-Log "Создан бэкап: $destination" "SUCCESS"
        }
    }
    
    Write-Log "Бэкап сохранен в: $backupPath" "SUCCESS"
}

# Функция остановки процессов
function Stop-WarpProcesses {
    Write-Log "Остановка всех процессов Warp..."
    
    $processNames = @("Warp", "warp", "WarpTerminal", "warp-terminal")
    $stopped = 0
    
    foreach ($name in $processNames) {
        $processes = Get-Process -Name $name -ErrorAction SilentlyContinue
        if ($processes) {
            $processes | Stop-Process -Force -ErrorAction SilentlyContinue
            $stopped += $processes.Count
            Write-Log "Остановлено процессов '$name': $($processes.Count)" "SUCCESS"
        }
    }
    
    if ($stopped -eq 0) {
        Write-Log "Активные процессы Warp не найдены"
    } else {
        Start-Sleep -Seconds 2
        Write-Log "Всего остановлено процессов: $stopped" "SUCCESS"
    }
}

# Функция очистки кэша
function Clear-WarpCache {
    Write-Log "Очистка кэша и временных файлов Warp..."
    
    $cachePaths = @(
        "$env:APPDATA\Warp",
        "$env:LOCALAPPDATA\Warp",
        "$env:LOCALAPPDATA\Programs\Warp",
        "$env:USERPROFILE\.warp",
        "$env:TEMP\Warp*"
    )
    
    $cleared = 0
    foreach ($path in $cachePaths) {
        if (Test-Path $path) {
            try {
                if ($path -like "*\Warp*") {
                    Remove-Item $path -Recurse -Force -ErrorAction Stop
                } else {
                    Get-ChildItem $path -ErrorAction Stop | Remove-Item -Recurse -Force
                }
                Write-Log "Очищен: $path" "SUCCESS"
                $cleared++
            } catch {
                Write-Log "Ошибка при очистке $path : $($_.Exception.Message)" "ERROR"
            }
        }
    }
    
    Write-Log "Очищено путей: $cleared" "SUCCESS"
}

# Функция сброса сетевых настроек
function Reset-NetworkSettings {
    Write-Log "Сброс сетевых настроек Windows..."
    
    $commands = @{
        "Winsock" = "netsh winsock reset"
        "TCP/IP" = "netsh int ip reset"
        "IPv4" = "netsh interface ipv4 reset"
        "IPv6" = "netsh interface ipv6 reset"
        "DNS Cache" = "ipconfig /flushdns"
        "ARP Table" = "arp -d *"
    }
    
    foreach ($desc in $commands.Keys) {
        try {
            Invoke-Expression $commands[$desc] | Out-Null
            Write-Log "Сброшено: $desc" "SUCCESS"
        } catch {
            Write-Log "Ошибка сброса $desc : $($_.Exception.Message)" "WARN"
        }
    }
}

# Функция настройки DNS
function Set-OptimalDNS {
    Write-Log "Настройка оптимальных DNS серверов..."
    
    $dnsServers = @{
        "Google" = @("8.8.8.8", "8.8.4.4")
        "Cloudflare" = @("1.1.1.1", "1.0.0.1")
        "Quad9" = @("9.9.9.9", "149.112.112.112")
    }
    
    # Тестирование скорости DNS
    $bestDNS = $null
    $bestTime = [int]::MaxValue
    
    foreach ($provider in $dnsServers.Keys) {
        $dns = $dnsServers[$provider][0]
        try {
            $result = Test-NetConnection -ComputerName $dns -Port 53 -WarningAction SilentlyContinue
            if ($result.TcpTestSucceeded -and $result.PingReplyDetails.RoundtripTime -lt $bestTime) {
                $bestTime = $result.PingReplyDetails.RoundtripTime
                $bestDNS = $provider
            }
        } catch {
            Write-Log "DNS $provider недоступен" "WARN"
        }
    }
    
    if ($bestDNS) {
        Write-Log "Лучший DNS провайдер: $bestDNS (${bestTime}ms)" "SUCCESS"
        
        # Применение DNS ко всем активным адаптерам
        $adapters = Get-NetAdapter | Where-Object {$_.Status -eq "Up"}
        foreach ($adapter in $adapters) {
            try {
                Set-DnsClientServerAddress -InterfaceIndex $adapter.InterfaceIndex -ServerAddresses $dnsServers[$bestDNS]
                Write-Log "DNS настроен для адаптера: $($adapter.Name)" "SUCCESS"
            } catch {
                Write-Log "Ошибка настройки DNS для $($adapter.Name): $($_.Exception.Message)" "WARN"
            }
        }
    } else {
        Write-Log "Не удалось найти доступные DNS серверы" "ERROR"
    }
}

# Функция проверки подключения
function Test-WarpConnectivity {
    Write-Log "Проверка подключения к серверам Warp..."
    
    $servers = @(
        "warp.dev",
        "api.warp.dev", 
        "auth.warp.dev",
        "releases.warp.dev"
    )
    
    $results = @()
    foreach ($server in $servers) {
        try {
            $result = Test-NetConnection -ComputerName $server -Port 443 -WarningAction SilentlyContinue
            $status = if ($result.TcpTestSucceeded) { "✅ Доступен" } else { "❌ Недоступен" }
            $ping = if ($result.PingSucceeded) { "$($result.PingReplyDetails.RoundtripTime)ms" } else { "N/A" }
            
            Write-Log "$server - $status ($ping)"
            $results += [PSCustomObject]@{
                Server = $server
                Available = $result.TcpTestSucceeded
                Ping = $ping
            }
        } catch {
            Write-Log "$server - ❌ Ошибка: $($_.Exception.Message)" "ERROR"
        }
    }
    
    $available = ($results | Where-Object {$_.Available}).Count
    $total = $results.Count
    
    Write-Log "Результат подключения: $available/$total серверов доступны" $(if($available -eq 0){"ERROR"}elseif($available -lt $total){"WARN"}else{"SUCCESS"})
    
    return $available -gt 0
}

# Функция настройки брандмауэра
function Configure-Firewall {
    Write-Log "Настройка правил брандмауэра для Warp..."
    
    $rules = @(
        @{Name="Warp Terminal Out"; Direction="Outbound"; Program="warp.exe"},
        @{Name="Warp Terminal In"; Direction="Inbound"; Program="warp.exe"},
        @{Name="Warp HTTPS"; Direction="Outbound"; Protocol="TCP"; LocalPort="443"},
        @{Name="Warp HTTP"; Direction="Outbound"; Protocol="TCP"; LocalPort="80"}
    )
    
    foreach ($rule in $rules) {
        try {
            $existingRule = Get-NetFirewallRule -DisplayName $rule.Name -ErrorAction SilentlyContinue
            if ($existingRule) {
                Remove-NetFirewallRule -DisplayName $rule.Name -ErrorAction SilentlyContinue
            }
            
            $params = @{
                DisplayName = $rule.Name
                Direction = $rule.Direction
                Action = "Allow"
                Profile = "Any"
            }
            
            if ($rule.Program) { $params.Program = $rule.Program }
            if ($rule.Protocol) { $params.Protocol = $rule.Protocol }
            if ($rule.LocalPort) { $params.LocalPort = $rule.LocalPort }
            
            New-NetFirewallRule @params | Out-Null
            Write-Log "Создано правило: $($rule.Name)" "SUCCESS"
        } catch {
            Write-Log "Ошибка создания правила $($rule.Name): $($_.Exception.Message)" "WARN"
        }
    }
}

# Функция настройки Windows Defender
function Configure-WindowsDefender {
    Write-Log "Настройка исключений Windows Defender..."
    
    $exclusions = @(
        "warp.exe",
        "$env:LOCALAPPDATA\Programs\Warp",
        "$env:APPDATA\Warp"
    )
    
    foreach ($exclusion in $exclusions) {
        try {
            if ($exclusion -like "*.exe") {
                Add-MpPreference -ExclusionProcess $exclusion -ErrorAction Stop
            } else {
                Add-MpPreference -ExclusionPath $exclusion -ErrorAction Stop
            }
            Write-Log "Добавлено исключение: $exclusion" "SUCCESS"
        } catch {
            Write-Log "Ошибка добавления исключения $exclusion : $($_.Exception.Message)" "WARN"
        }
    }
}

# Функция проверки системы
function Test-SystemHealth {
    Write-Log "Проверка здоровья системы..."
    
    # Проверка доступного места на диске
    $systemDrive = Get-PSDrive C
    $freeSpaceGB = [math]::Round($systemDrive.Free / 1GB, 2)
    
    if ($freeSpaceGB -lt 1) {
        Write-Log "⚠️ Мало места на диске: ${freeSpaceGB}GB свободно" "WARN"
    } else {
        Write-Log "✅ Свободного места на диске: ${freeSpaceGB}GB" "SUCCESS"
    }
    
    # Проверка интернет-подключения
    try {
        $connection = Test-NetConnection -ComputerName "8.8.8.8" -Port 53 -WarningAction SilentlyContinue
        if ($connection.TcpTestSucceeded) {
            Write-Log "✅ Интернет-подключение активно" "SUCCESS"
        } else {
            Write-Log "❌ Проблемы с интернет-подключением" "ERROR"
        }
    } catch {
        Write-Log "❌ Ошибка проверки подключения" "ERROR"
    }
    
    # Проверка статуса Windows Update
    try {
        $updates = Get-WindowsUpdate -ErrorAction SilentlyContinue
        if ($updates) {
            Write-Log "⚠️ Доступны обновления Windows: $($updates.Count)" "WARN"
        }
    } catch {
        # Windows Update модуль не установлен - это нормально
    }
}

# Функция загрузки и установки Warp
function Install-WarpLatest {
    Write-Log "Загрузка и установка последней версии Warp..."
    
    try {
        # Получение информации о последнем релизе
        $releaseInfo = Invoke-RestMethod -Uri "https://api.github.com/repos/warpdotdev/warp/releases/latest" -ErrorAction Stop
        $downloadUrl = $releaseInfo.assets | Where-Object {$_.name -like "*windows*installer*.exe"} | Select-Object -First 1 -ExpandProperty browser_download_url
        
        if (-not $downloadUrl) {
            throw "Не найден установщик для Windows"
        }
        
        $installerPath = "$env:TEMP\warp-installer-latest.exe"
        
        Write-Log "Скачивание установщика..." "INFO"
        Invoke-WebRequest -Uri $downloadUrl -OutFile $installerPath -ErrorAction Stop
        
        Write-Log "Запуск установки..." "INFO"
        Start-Process -FilePath $installerPath -ArgumentList "/silent" -Wait -ErrorAction Stop
        
        Write-Log "✅ Warp успешно установлен/обновлен" "SUCCESS"
        Remove-Item $installerPath -Force -ErrorAction SilentlyContinue
        
    } catch {
        Write-Log "❌ Ошибка установки Warp: $($_.Exception.Message)" "ERROR"
        Write-Log "Скачайте установщик вручную с https://www.warp.dev/download" "INFO"
        Start-Process "https://www.warp.dev/download"
    }
}

# Функция проверки VPN
function Test-VPNConnection {
    Write-Log "Проверка VPN подключения..."
    
    try {
        # Получение внешнего IP
        $externalIP = (Invoke-RestMethod -Uri "https://api.ipify.org" -TimeoutSec 10).Trim()
        $locationInfo = Invoke-RestMethod -Uri "http://ip-api.com/json/$externalIP" -TimeoutSec 10
        
        Write-Log "Внешний IP: $externalIP" "INFO"
        Write-Log "Местоположение: $($locationInfo.city), $($locationInfo.country)" "INFO"
        
        # Проверка, подключен ли VPN
        $vpnAdapters = Get-NetAdapter | Where-Object {$_.InterfaceDescription -like "*VPN*" -or $_.InterfaceDescription -like "*TAP*"}
        if ($vpnAdapters) {
            Write-Log "✅ Обнаружены VPN адаптеры: $($vpnAdapters.Count)" "SUCCESS"
        } else {
            Write-Log "⚠️ VPN адаптеры не найдены" "WARN"
            Write-Log "Рекомендация: Попробуйте VPN с серверами в США или Европе" "INFO"
        }
        
    } catch {
        Write-Log "❌ Ошибка проверки VPN: $($_.Exception.Message)" "ERROR"
    }
}

# Главная функция
function Start-WarpFix {
    Write-Host @"
╔═══════════════════════════════════════════════════════════════════════════════╗
║                🔧 ПРОДВИНУТОЕ ИСПРАВЛЕНИЕ WARP TERMINAL 🔧                   ║
║                            PowerShell Edition                                 ║
╚═══════════════════════════════════════════════════════════════════════════════╝
"@ -ForegroundColor Cyan

    Write-Log "Запуск продвинутого исправления Warp Terminal..." "INFO"
    Write-Log "Лог-файл: $LogFile" "INFO"
    
    # Этап 1: Проверка системы
    Write-Host "`n[1/10] Проверка системы..." -ForegroundColor Yellow
    Test-SystemHealth
    
    # Этап 2: Создание бэкапа
    Write-Host "`n[2/10] Создание резервной копии..." -ForegroundColor Yellow
    Backup-WarpSettings
    
    # Этап 3: Остановка процессов
    Write-Host "`n[3/10] Остановка процессов Warp..." -ForegroundColor Yellow
    Stop-WarpProcesses
    
    # Этап 4: Очистка кэша
    Write-Host "`n[4/10] Очистка кэша..." -ForegroundColor Yellow
    Clear-WarpCache
    
    # Этап 5: Сброс сети
    Write-Host "`n[5/10] Сброс сетевых настроек..." -ForegroundColor Yellow
    Reset-NetworkSettings
    
    # Этап 6: Настройка DNS
    Write-Host "`n[6/10] Настройка оптимальных DNS..." -ForegroundColor Yellow
    Set-OptimalDNS
    
    # Этап 7: Настройка брандмауэра
    Write-Host "`n[7/10] Настройка брандмауэра..." -ForegroundColor Yellow
    Configure-Firewall
    
    # Этап 8: Настройка Windows Defender
    Write-Host "`n[8/10] Настройка Windows Defender..." -ForegroundColor Yellow
    Configure-WindowsDefender
    
    # Этап 9: Проверка подключения
    Write-Host "`n[9/10] Проверка подключения..." -ForegroundColor Yellow
    $connectionOK = Test-WarpConnectivity
    
    # Этап 10: Проверка VPN
    Write-Host "`n[10/10] Проверка VPN..." -ForegroundColor Yellow
    Test-VPNConnection
    
    # Результаты
    Write-Host "`n" + "="*79 -ForegroundColor Green
    Write-Host "                           🎉 ИСПРАВЛЕНИЕ ЗАВЕРШЕНО! 🎉" -ForegroundColor Green
    Write-Host "="*79 -ForegroundColor Green
    
    if ($connectionOK) {
        Write-Log "✅ Серверы Warp доступны. Попробуйте перезапустить Warp." "SUCCESS"
    } else {
        Write-Log "⚠️ Серверы Warp недоступны. Дополнительные действия:" "WARN"
        Write-Host @"

🔧 ДОПОЛНИТЕЛЬНЫЕ РЕКОМЕНДАЦИИ:
• Перезагрузите компьютер
• Попробуйте VPN с серверами в США/Европе  
• Временно отключите антивирус
• Проверьте настройки корпоративной сети
• Используйте мобильный интернет для теста

📞 ПОДДЕРЖКА:
• Email: appeals@warp.dev
• Документация: https://docs.warp.dev
• Альтернативы: GitHub Copilot CLI, Cursor, Shell-GPT

"@ -ForegroundColor Cyan
    }
    
    Write-Log "Лог сохранен: $LogFile" "INFO"
    
    if (-not $Force) {
        $reboot = Read-Host "`nПерезагрузить компьютер сейчас? (Y/N)"
        if ($reboot -eq 'Y' -or $reboot -eq 'y') {
            Write-Log "Перезагрузка системы..." "INFO"
            Restart-Computer -Force
        }
    }
}

# Запуск основной функции
try {
    Start-WarpFix
} catch {
    Write-Log "❌ Критическая ошибка: $($_.Exception.Message)" "ERROR"
    Write-Log "Полный стек ошибки: $($_.Exception.StackTrace)" "ERROR"
}

Write-Host "`nСкрипт завершен. Нажмите любую клавишу для выхода..." -ForegroundColor Gray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")