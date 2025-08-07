# Восстановление системы после Warp Terminal Fix
# Требует запуска от имени администратора

#Requires -RunAsAdministrator

param(
    [switch]$ResetNetwork,
    [switch]$RestoreFromBackup,
    [string]$BackupPath = "",
    [string]$LogFile = "$env:TEMP\warp-restore-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
)

# Настройка вывода
$Host.UI.RawUI.WindowTitle = "Warp Terminal Restore - Восстановление системы"
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
        "RESTORE" { "Cyan" }
        default { "White" }
    })
    Add-Content -Path $LogFile -Value $logEntry -ErrorAction SilentlyContinue
}

# Функция поиска бэкапов
function Find-WarpBackups {
    Write-Log "Поиск резервных копий Warp..." "RESTORE"
    
    $backupFolders = Get-ChildItem -Path $env:TEMP -Directory -Filter "warp-backup-*" -ErrorAction SilentlyContinue | 
                     Sort-Object CreationTime -Descending
    
    if ($backupFolders) {
        Write-Log "Найдено резервных копий: $($backupFolders.Count)" "SUCCESS"
        foreach ($folder in $backupFolders) {
            Write-Log "  📁 $($folder.Name) - $($folder.CreationTime)" "INFO"
        }
        return $backupFolders
    } else {
        Write-Log "❌ Резервные копии не найдены в $env:TEMP" "WARN"
        return $null
    }
}

# Функция восстановления из бэкапа
function Restore-WarpFromBackup {
    param([string]$SelectedBackupPath)
    
    if (-not $SelectedBackupPath) {
        $backups = Find-WarpBackups
        if (-not $backups) { return $false }
        $SelectedBackupPath = $backups[0].FullName
        Write-Log "Используется последний бэкап: $SelectedBackupPath" "RESTORE"
    }
    
    if (-not (Test-Path $SelectedBackupPath)) {
        Write-Log "❌ Путь к бэкапу не найден: $SelectedBackupPath" "ERROR"
        return $false
    }
    
    Write-Log "Восстановление настроек Warp из бэкапа..." "RESTORE"
    
    # Остановка процессов Warp перед восстановлением
    Get-Process -Name "warp*" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    
    $restored = 0
    $backupContents = Get-ChildItem -Path $SelectedBackupPath -Directory
    
    foreach ($folder in $backupContents) {
        $targetPath = switch ($folder.Name) {
            "Warp" { 
                if (Test-Path "$env:APPDATA\Warp") { "$env:APPDATA\Warp" }
                elseif (Test-Path "$env:LOCALAPPDATA\Warp") { "$env:LOCALAPPDATA\Warp" }
                else { "$env:APPDATA\Warp" }
            }
            ".warp" { "$env:USERPROFILE\.warp" }
            default { $null }
        }
        
        if ($targetPath) {
            try {
                # Удаление текущих настроек
                if (Test-Path $targetPath) {
                    Remove-Item $targetPath -Recurse -Force -ErrorAction Stop
                }
                
                # Восстановление из бэкапа
                Copy-Item $folder.FullName $targetPath -Recurse -Force -ErrorAction Stop
                Write-Log "✅ Восстановлено: $targetPath" "SUCCESS"
                $restored++
            } catch {
                Write-Log "❌ Ошибка восстановления $targetPath : $($_.Exception.Message)" "ERROR"
            }
        }
    }
    
    Write-Log "Восстановлено папок настроек: $restored" "SUCCESS"
    return $restored -gt 0
}

# Функция удаления правил брандмауэра
function Remove-WarpFirewallRules {
    Write-Log "Удаление правил брандмауэра Warp..." "RESTORE"
    
    $ruleNames = @(
        "Warp Terminal Out",
        "Warp Terminal In", 
        "Warp HTTPS",
        "Warp HTTP"
    )
    
    $removed = 0
    foreach ($ruleName in $ruleNames) {
        try {
            $rule = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
            if ($rule) {
                Remove-NetFirewallRule -DisplayName $ruleName -ErrorAction Stop
                Write-Log "✅ Удалено правило: $ruleName" "SUCCESS"
                $removed++
            } else {
                Write-Log "ℹ️ Правило не найдено: $ruleName" "INFO"
            }
        } catch {
            Write-Log "❌ Ошибка удаления правила $ruleName : $($_.Exception.Message)" "ERROR"
        }
    }
    
    Write-Log "Удалено правил брандмауэра: $removed" "SUCCESS"
}

# Функция удаления исключений Windows Defender
function Remove-WarpDefenderExclusions {
    Write-Log "Удаление исключений Windows Defender..." "RESTORE"
    
    $exclusions = @{
        "Process" = @("warp.exe")
        "Path" = @(
            "$env:LOCALAPPDATA\Programs\Warp",
            "$env:APPDATA\Warp"
        )
    }
    
    $removed = 0
    
    # Удаление исключений процессов
    foreach ($process in $exclusions.Process) {
        try {
            Remove-MpPreference -ExclusionProcess $process -ErrorAction Stop
            Write-Log "✅ Удалено исключение процесса: $process" "SUCCESS"
            $removed++
        } catch {
            Write-Log "ℹ️ Исключение процесса не найдено или ошибка: $process" "INFO"
        }
    }
    
    # Удаление исключений путей
    foreach ($path in $exclusions.Path) {
        try {
            Remove-MpPreference -ExclusionPath $path -ErrorAction Stop
            Write-Log "✅ Удалено исключение пути: $path" "SUCCESS"
            $removed++
        } catch {
            Write-Log "ℹ️ Исключение пути не найдено или ошибка: $path" "INFO"
        }
    }
    
    Write-Log "Удалено исключений Defender: $removed" "SUCCESS"
}

# Функция восстановления DNS
function Restore-DNSSettings {
    Write-Log "Восстановление DNS настроек..." "RESTORE"
    
    $adapters = Get-NetAdapter | Where-Object {$_.Status -eq "Up"}
    $restored = 0
    
    foreach ($adapter in $adapters) {
        try {
            # Сброс на автоматические DNS
            Set-DnsClientServerAddress -InterfaceIndex $adapter.InterfaceIndex -ResetServerAddresses -ErrorAction Stop
            Write-Log "✅ DNS сброшен для адаптера: $($adapter.Name)" "SUCCESS"
            $restored++
        } catch {
            Write-Log "❌ Ошибка сброса DNS для $($adapter.Name): $($_.Exception.Message)" "ERROR"
        }
    }
    
    # Очистка DNS кэша
    try {
        ipconfig /flushdns | Out-Null
        Write-Log "✅ DNS кэш очищен" "SUCCESS"
    } catch {
        Write-Log "❌ Ошибка очистки DNS кэша" "ERROR"
    }
    
    Write-Log "Восстановлено DNS для адаптеров: $restored" "SUCCESS"
}

# Функция сброса сетевых настроек
function Reset-NetworkStack {
    if (-not $ResetNetwork) {
        $reset = Read-Host "Выполнить полный сброс сетевых настроек? (может помочь при проблемах с сетью) [y/N]"
        if ($reset -ne 'y' -and $reset -ne 'Y') {
            Write-Log "Сброс сетевых настроек пропущен" "INFO"
            return
        }
    }
    
    Write-Log "Выполнение полного сброса сетевых настроек..." "RESTORE"
    
    $commands = @{
        "Winsock" = "netsh winsock reset"
        "TCP/IP v4" = "netsh interface ipv4 reset"
        "TCP/IP v6" = "netsh interface ipv6 reset"
    }
    
    foreach ($desc in $commands.Keys) {
        try {
            Invoke-Expression $commands[$desc] | Out-Null
            Write-Log "✅ Сброшено: $desc" "SUCCESS"
        } catch {
            Write-Log "❌ Ошибка сброса $desc : $($_.Exception.Message)" "ERROR"
        }
    }
    
    Write-Log "⚠️ ВНИМАНИЕ: Требуется перезагрузка для применения сетевых изменений" "WARN"
}

# Функция проверки системы после восстановления
function Test-SystemAfterRestore {
    Write-Log "Проверка состояния системы после восстановления..." "RESTORE"
    
    # Проверка интернет-подключения
    try {
        $connection = Test-NetConnection -ComputerName "8.8.8.8" -Port 53 -WarningAction SilentlyContinue -InformationLevel Quiet
        if ($connection) {
            Write-Log "✅ Интернет-подключение работает" "SUCCESS"
        } else {
            Write-Log "❌ Проблемы с интернет-подключением" "ERROR"
        }
    } catch {
        Write-Log "❌ Ошибка проверки подключения" "ERROR"
    }
    
    # Проверка DNS
    try {
        $dnsTest = Resolve-DnsName "google.com" -ErrorAction Stop
        Write-Log "✅ DNS работает корректно" "SUCCESS"
    } catch {
        Write-Log "❌ Проблемы с DNS разрешением" "ERROR"
    }
    
    # Проверка настроек Warp
    $warpPaths = @(
        "$env:APPDATA\Warp",
        "$env:LOCALAPPDATA\Warp", 
        "$env:USERPROFILE\.warp"
    )
    
    $foundWarp = 0
    foreach ($path in $warpPaths) {
        if (Test-Path $path) {
            Write-Log "✅ Найдены настройки Warp: $path" "SUCCESS"
            $foundWarp++
        }
    }
    
    if ($foundWarp -eq 0) {
        Write-Log "ℹ️ Настройки Warp не найдены (возможно, это нормально)" "INFO"
    }
}

# Функция очистки логов и временных файлов
function Clean-TempFiles {
    Write-Log "Очистка временных файлов..." "RESTORE"
    
    $patterns = @(
        "$env:TEMP\warp-installer-*.exe",
        "$env:TEMP\Warp*"
    )
    
    $cleaned = 0
    foreach ($pattern in $patterns) {
        $files = Get-ChildItem -Path $pattern -ErrorAction SilentlyContinue
        foreach ($file in $files) {
            try {
                Remove-Item $file.FullName -Force -Recurse -ErrorAction Stop
                Write-Log "✅ Удален: $($file.Name)" "SUCCESS"
                $cleaned++
            } catch {
                Write-Log "⚠️ Не удалось удалить: $($file.Name)" "WARN"
            }
        }
    }
    
    Write-Log "Очищено временных файлов: $cleaned" "SUCCESS"
}

# Главная функция восстановления
function Start-WarpRestore {
    Write-Host @"
╔═══════════════════════════════════════════════════════════════════════════════╗
║                🔄 ВОССТАНОВЛЕНИЕ СИСТЕМЫ ПОСЛЕ WARP FIX 🔄                  ║
║                            Откат изменений                                   ║
╚═══════════════════════════════════════════════════════════════════════════════╝
"@ -ForegroundColor Cyan

    Write-Log "Запуск восстановления системы..." "RESTORE"
    Write-Log "Лог-файл: $LogFile" "INFO"
    
    # Этап 1: Удаление правил брандмауэра
    Write-Host "`n[1/7] Удаление правил брандмауэра..." -ForegroundColor Yellow
    Remove-WarpFirewallRules
    
    # Этап 2: Удаление исключений Defender
    Write-Host "`n[2/7] Удаление исключений Windows Defender..." -ForegroundColor Yellow
    Remove-WarpDefenderExclusions
    
    # Этап 3: Восстановление DNS
    Write-Host "`n[3/7] Восстановление DNS настроек..." -ForegroundColor Yellow
    Restore-DNSSettings
    
    # Этап 4: Восстановление настроек Warp
    Write-Host "`n[4/7] Восстановление настроек Warp..." -ForegroundColor Yellow
    if ($RestoreFromBackup -or $BackupPath) {
        $restored = Restore-WarpFromBackup -SelectedBackupPath $BackupPath
        if (-not $restored) {
            Write-Log "⚠️ Восстановление из бэкапа не удалось" "WARN"
        }
    } else {
        Write-Log "Восстановление настроек Warp пропущено (используйте -RestoreFromBackup)" "INFO"
        Find-WarpBackups | Out-Null
    }
    
    # Этап 5: Сброс сетевых настроек (опционально)
    Write-Host "`n[5/7] Сброс сетевых настроек..." -ForegroundColor Yellow
    Reset-NetworkStack
    
    # Этап 6: Очистка временных файлов
    Write-Host "`n[6/7] Очистка временных файлов..." -ForegroundColor Yellow
    Clean-TempFiles
    
    # Этап 7: Проверка системы
    Write-Host "`n[7/7] Проверка состояния системы..." -ForegroundColor Yellow
    Test-SystemAfterRestore
    
    # Результаты
    Write-Host "`n" + "="*79 -ForegroundColor Green
    Write-Host "                        🎉 ВОССТАНОВЛЕНИЕ ЗАВЕРШЕНО! 🎉" -ForegroundColor Green
    Write-Host "="*79 -ForegroundColor Green
    
    Write-Host @"

✅ ВЫПОЛНЕНО:
• Удалены правила брандмауэра Warp
• Удалены исключения Windows Defender
• Восстановлены автоматические DNS настройки
• Очищены временные файлы

🔄 РЕКОМЕНДАЦИИ:
• Перезагрузите компьютер для полного применения изменений
• Проверьте работу интернета
• При необходимости переустановите Warp с официального сайта

📋 Лог сохранен: $LogFile

"@ -ForegroundColor Cyan

    # Предложение перезагрузки
    $reboot = Read-Host "Перезагрузить компьютер сейчас для применения всех изменений? (Y/N)"
    if ($reboot -eq 'Y' -or $reboot -eq 'y') {
        Write-Log "Перезагрузка системы..." "RESTORE"
        Restart-Computer -Force
    } else {
        Write-Host "⚠️ Не забудьте перезагрузить компьютер позже для полного восстановления" -ForegroundColor Yellow
    }
}

# Запуск основной функции
try {
    Start-WarpRestore
} catch {
    Write-Log "❌ Критическая ошибка восстановления: $($_.Exception.Message)" "ERROR"
    Write-Log "Полный стек ошибки: $($_.Exception.StackTrace)" "ERROR"
    Write-Host "❌ Произошла критическая ошибка. Проверьте лог: $LogFile" -ForegroundColor Red
}

Write-Host "`nСкрипт восстановления завершен. Нажмите любую клавишу для выхода..." -ForegroundColor Gray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
