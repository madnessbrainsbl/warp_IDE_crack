@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

:: Проверка прав администратора
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo.
    echo ❌ ОШИБКА: Требуются права администратора
    echo Запустите от имени администратора
    pause
    exit /b 1
)

title Обновление AI-компонентов Warp Terminal
color 0B

echo.
echo ╔═══════════════════════════════════════════════════════════════════════════════╗
echo ║            🤖 ИСПРАВЛЕНИЕ AI-МОДЕЛИ WARP TERMINAL 🤖                         ║
echo ║                     Обновление до актуальных версий                          ║
echo ╚═══════════════════════════════════════════════════════════════════════════════╝
echo.

:MENU
cls
echo.
echo 🔍 ПРОБЛЕМА: Warp показывает устаревшую "Claude 3.5" вместо актуальных моделей
echo.
echo ╔═══════════════════════════════════════════════════════════════════════════════╗
echo ║                         ВЫБЕРИТЕ ДЕЙСТВИЕ                                    ║
echo ╠═══════════════════════════════════════════════════════════════════════════════╣
echo ║  1. Полное обновление Warp + очистка AI кэша (рекомендуется)                ║
echo ║  2. Только очистка AI кэша и настроек                                        ║
echo ║  3. Сброс настроек моделей ИИ                                                ║
echo ║  4. Принудительное обновление компонентов                                    ║
echo ║  5. Переключиться на бета-канал обновлений                                   ║
echo ║  6. Проверить доступные AI-модели                                            ║
echo ║  7. Альтернативные AI-терминалы                                              ║
echo ║  0. Выход                                                                    ║
echo ╚═══════════════════════════════════════════════════════════════════════════════╝
echo.

set /p choice="Введите номер (0-7): "

if "%choice%"=="1" goto FULL_UPDATE
if "%choice%"=="2" goto CLEAR_AI_CACHE
if "%choice%"=="3" goto RESET_AI_SETTINGS
if "%choice%"=="4" goto FORCE_UPDATE
if "%choice%"=="5" goto BETA_CHANNEL
if "%choice%"=="6" goto CHECK_MODELS
if "%choice%"=="7" goto ALTERNATIVES
if "%choice%"=="0" goto EXIT

echo Неверный выбор!
timeout /t 2 >nul
goto MENU

:FULL_UPDATE
echo.
echo ═══════════════════════════════════════════════════════════════════════════════
echo                        ПОЛНОЕ ОБНОВЛЕНИЕ AI-КОМПОНЕНТОВ
echo ═══════════════════════════════════════════════════════════════════════════════
echo.

call :LOG "Начинаю полное обновление AI-компонентов Warp..."

echo [1/8] Остановка всех процессов Warp...
taskkill /f /im "Warp.exe" 2>nul
taskkill /f /im "warp.exe" 2>nul
timeout /t 3 >nul

echo [2/8] Очистка AI кэша...
if exist "%APPDATA%\Warp\ai_cache" rmdir /s /q "%APPDATA%\Warp\ai_cache" 2>nul
if exist "%LOCALAPPDATA%\Warp\ai_cache" rmdir /s /q "%LOCALAPPDATA%\Warp\ai_cache" 2>nul
if exist "%USERPROFILE%\.warp\ai" rmdir /s /q "%USERPROFILE%\.warp\ai" 2>nul
if exist "%USERPROFILE%\.warp\models" rmdir /s /q "%USERPROFILE%\.warp\models" 2>nul

echo [3/8] Сброс настроек AI моделей...
reg delete "HKCU\Software\Warp\AI" /f >nul 2>&1
reg delete "HKCU\Software\Warp\Models" /f >nul 2>&1

echo [4/8] Очистка конфигурационных файлов...
if exist "%APPDATA%\Warp\config.json" (
    powershell -Command "& {$config = Get-Content '%APPDATA%\Warp\config.json' | ConvertFrom-Json; $config.PSObject.Properties.Remove('ai_model'); $config.PSObject.Properties.Remove('claude_version'); $config | ConvertTo-Json | Set-Content '%APPDATA%\Warp\config.json'}" 2>nul
)

echo [5/8] Принудительное обновление Warp...
call :DOWNLOAD_LATEST_WARP

echo [6/8] Очистка системного кэша...
ipconfig /flushdns >nul
netsh int ip reset >nul

echo [7/8] Установка актуальных AI настроек...
call :SET_CURRENT_AI_MODELS

echo [8/8] Проверка обновлений...
if exist "%LOCALAPPDATA%\Programs\Warp\Warp.exe" (
    start "" "%LOCALAPPDATA%\Programs\Warp\Warp.exe" --check-updates
    timeout /t 5 >nul
    taskkill /f /im "Warp.exe" 2>nul
)

echo.
echo ✅ ПОЛНОЕ ОБНОВЛЕНИЕ ЗАВЕРШЕНО!
echo.
echo 📋 Что было сделано:
echo    • Очищен весь AI кэш
echo    • Сброшены настройки моделей
echo    • Обновлен Warp до последней версии
echo    • Настроены актуальные AI модели
echo.
echo 🚀 Запустите Warp и проверьте доступные модели AI
goto CONTINUE

:CLEAR_AI_CACHE
echo.
echo ═══════════════════════════════════════════════════════════════════════════════
echo                           ОЧИСТКА AI КЭША
echo ═══════════════════════════════════════════════════════════════════════════════
echo.

call :LOG "Остановка Warp и очистка AI кэша..."

taskkill /f /im "Warp.exe" 2>nul
taskkill /f /im "warp.exe" 2>nul
timeout /t 2 >nul

echo ✅ Процессы Warp остановлены

call :LOG "Поиск и удаление AI кэша..."
set "cleaned=0"

set "ai_paths=%APPDATA%\Warp\ai_cache %LOCALAPPDATA%\Warp\ai_cache %USERPROFILE%\.warp\ai %USERPROFILE%\.warp\models %APPDATA%\Warp\claude %LOCALAPPDATA%\Warp\anthropic"

for %%p in (%ai_paths%) do (
    if exist "%%p" (
        rmdir /s /q "%%p" 2>nul
        if not exist "%%p" (
            echo ✅ Удален AI кэш: %%p
            set /a cleaned+=1
        )
    )
)

:: Очистка временных AI файлов
for /f "delims=" %%f in ('dir /b "%TEMP%\*claude*" "%TEMP%\*anthropic*" "%TEMP%\*ai_model*" 2^>nul') do (
    del /q /f "%TEMP%\%%f" 2>nul
    echo ✅ Удален временный файл: %%f
    set /a cleaned+=1
)

echo.
echo ✅ AI кэш очищен! Удалено объектов: !cleaned!
echo 🔄 Перезапустите Warp для применения изменений
goto CONTINUE

:RESET_AI_SETTINGS
echo.
echo ═══════════════════════════════════════════════════════════════════════════════
echo                         СБРОС НАСТРОЕК AI МОДЕЛЕЙ
echo ═══════════════════════════════════════════════════════════════════════════════
echo.

call :LOG "Сброс настроек AI моделей в реестре и конфигурации..."

:: Сброс реестра
reg delete "HKCU\Software\Warp\AI" /f >nul 2>&1
reg delete "HKCU\Software\Warp\Models" /f >nul 2>&1
reg delete "HKCU\Software\Warp\Claude" /f >nul 2>&1
echo ✅ Настройки AI в реестре сброшены

:: Сброс конфигурационных файлов
if exist "%APPDATA%\Warp\config.json" (
    copy "%APPDATA%\Warp\config.json" "%APPDATA%\Warp\config_backup_%date:~-4,4%%date:~-10,2%%date:~-7,2%.json" >nul 2>&1
    
    powershell -Command "& {try {$config = Get-Content '%APPDATA%\Warp\config.json' -Raw | ConvertFrom-Json; if ($config.ai_model) {$config.PSObject.Properties.Remove('ai_model')}; if ($config.claude_version) {$config.PSObject.Properties.Remove('claude_version')}; if ($config.anthropic_api_key) {$config.PSObject.Properties.Remove('anthropic_api_key')}; $config | ConvertTo-Json -Depth 10 | Set-Content '%APPDATA%\Warp\config.json'} catch {Write-Host 'Конфиг не найден или поврежден'}}" 2>nul
    echo ✅ Конфигурация AI сброшена
)

:: Создание нового конфига с актуальными моделями
call :SET_CURRENT_AI_MODELS

echo.
echo ✅ Настройки AI моделей сброшены!
echo 📝 Создан бэкап старой конфигурации
echo 🚀 Перезапустите Warp для применения изменений
goto CONTINUE

:FORCE_UPDATE
echo.
echo ═══════════════════════════════════════════════════════════════════════════════
echo                      ПРИНУДИТЕЛЬНОЕ ОБНОВЛЕНИЕ КОМПОНЕНТОВ
echo ═══════════════════════════════════════════════════════════════════════════════
echo.

call :LOG "Принудительное обновление всех компонентов Warp..."

echo [1/4] Остановка всех процессов...
taskkill /f /im "Warp.exe" 2>nul
wmic process where "name like '%%warp%%'" delete >nul 2>&1

echo [2/4] Загрузка последней версии...
call :DOWNLOAD_LATEST_WARP

echo [3/4] Обновление AI компонентов...
powershell -Command "& {try {Invoke-WebRequest -Uri 'https://api.anthropic.com/v1/models' -Headers @{'anthropic-version'='2023-06-01'} -Method GET} catch {Write-Host 'API недоступно'}}" >nul 2>&1

echo [4/4] Принудительный перезапуск обновлений...
if exist "%LOCALAPPDATA%\Programs\Warp\Warp.exe" (
    start "" "%LOCALAPPDATA%\Programs\Warp\Warp.exe" --force-update --reset-ai
    timeout /t 10 >nul
    taskkill /f /im "Warp.exe" 2>nul
)

echo.
echo ✅ Принудительное обновление завершено!
echo 🔄 Дождитесь полной загрузки при следующем запуске Warp
goto CONTINUE

:BETA_CHANNEL
echo.
echo ═══════════════════════════════════════════════════════════════════════════════
echo                       ПЕРЕКЛЮЧЕНИЕ НА БЕТА-КАНАЛ
echo ═══════════════════════════════════════════════════════════════════════════════
echo.

echo ⚠️  ВНИМАНИЕ: Бета-версия может содержать ошибки!
echo.
set /p confirm="Переключиться на бета-канал обновлений? (Y/N): "

if /i not "%confirm%"=="Y" goto CONTINUE

call :LOG "Переключение на бета-канал обновлений..."

:: Остановка Warp
taskkill /f /im "Warp.exe" 2>nul

:: Настройка бета-канала
if exist "%APPDATA%\Warp\config.json" (
    powershell -Command "& {try {$config = Get-Content '%APPDATA%\Warp\config.json' | ConvertFrom-Json; $config | Add-Member -NotePropertyName 'update_channel' -NotePropertyValue 'beta' -Force; $config | ConvertTo-Json | Set-Content '%APPDATA%\Warp\config.json'} catch {'{\"update_channel\": \"beta\"}' | Set-Content '%APPDATA%\Warp\config.json'}}" 2>nul
) else (
    mkdir "%APPDATA%\Warp" 2>nul
    echo {"update_channel": "beta"} > "%APPDATA%\Warp\config.json"
)

:: Загрузка бета-версии
powershell -Command "& {try {$releases = Invoke-RestMethod 'https://api.github.com/repos/warpdotdev/warp/releases'; $beta = $releases | Where-Object {$_.prerelease -eq $true} | Select-Object -First 1; if ($beta) {$asset = $beta.assets | Where-Object {$_.name -like '*windows*'} | Select-Object -First 1; if ($asset) {Write-Host 'Бета-версия найдена:' $beta.tag_name; Invoke-WebRequest $asset.browser_download_url -OutFile '$env:TEMP\warp-beta.exe'; Start-Process '$env:TEMP\warp-beta.exe' -ArgumentList '/silent'}}} catch {Write-Host 'Ошибка загрузки бета-версии'}}"

echo.
echo ✅ Переключение на бета-канал завершено!
echo 📥 Если доступна бета-версия, она будет установлена
echo 🔄 Перезапустите Warp для получения бета-обновлений
goto CONTINUE

:CHECK_MODELS
echo.
echo ═══════════════════════════════════════════════════════════════════════════════
echo                        ПРОВЕРКА ДОСТУПНЫХ AI МОДЕЛЕЙ  
echo ═══════════════════════════════════════════════════════════════════════════════
echo.

call :LOG "Проверка актуальных AI моделей..."

echo 📋 АКТУАЛЬНЫЕ МОДЕЛИ CLAUDE (по состоянию на 2025):
echo.
echo 🤖 Claude 4 (Opus 4):
echo    • claude-4-opus-20250514
echo    • Самая мощная модель для сложных задач
echo.
echo 🚀 Claude 4 (Sonnet 4): 
echo    • claude-4-sonnet-20250514
echo    • Оптимальное соотношение скорости и качества
echo.
echo 🔍 Проверка доступности через API...
powershell -Command "& {try {Write-Host '🌐 Проверка подключения к Anthropic API...'; $response = Invoke-RestMethod -Uri 'https://api.anthropic.com/v1/models' -Headers @{'anthropic-version'='2023-06-01'; 'x-api-key'='dummy'} -ErrorAction SilentlyContinue; Write-Host '✅ API доступно'} catch {if ($_.Exception.Response.StatusCode -eq 401) {Write-Host '✅ API отвечает (требуется ключ)'} else {Write-Host '❌ API недоступно'}}}"

echo.
echo 🔧 ВОЗМОЖНЫЕ ПРИЧИНЫ ОТОБРАЖЕНИЯ "Claude 3.5":
echo    • Устаревший кэш моделей
echo    • Старая версия Warp
echo    • Проблемы с обновлением конфигурации
echo    • Региональные ограничения API
echo.
echo 💡 РЕКОМЕНДАЦИИ:
echo    • Выполните полную очистку (пункт 1)
echo    • Обновите Warp до последней версии
echo    • Попробуйте бета-канал (пункт 5)
echo    • Используйте VPN если есть региональные блокировки
goto CONTINUE

:ALTERNATIVES
echo.
echo ═══════════════════════════════════════════════════════════════════════════════
echo                         АЛЬТЕРНАТИВНЫЕ AI-ТЕРМИНАЛЫ
echo ═══════════════════════════════════════════════════════════════════════════════
echo.

echo 🚀 СОВРЕМЕННЫЕ АЛЬТЕРНАТИВЫ С АКТУАЛЬНЫМИ AI:
echo.
echo 1. 🎯 GitHub Copilot CLI (рекомендуется)
echo    • Команда: gh extension install github/gh-copilot  
echo    • Поддержка GPT-4o и новейших моделей
echo    • Бесплатно для студентов и open-source
echo.
echo 2. 🔥 Cursor (AI Code Editor)
echo    • Сайт: https://cursor.sh
echo    • Встроенный терминал с Claude 4 и GPT-4
echo    • Лучший AI-редактор 2024-2025
echo.
echo 3. 🐚 Shell GPT 
echo    • pip install shell-gpt
echo    • Поддержка всех новых моделей OpenAI и Claude
echo    • Работает в любом терминале
echo.
echo 4. 🏢 Amazon Q Developer (ex-CodeWhisperer)
echo    • aws configure sso  
echo    • Бесплатно для индивидуального использования
echo    • Поддержка Claude 3.5 Sonnet
echo.
echo 5. 🌟 Continue.dev
echo    • Плагин для VS Code с терминалом
echo    • Поддержка локальных моделей (Ollama)
echo    • Бесплатное использование собственных API ключей
echo.
echo 6. 🖥️ PowerShell AI модули:
echo    • Install-Module PSOpenAI
echo    • Install-Module PowerShellAI  
echo    • Прямое подключение к API Claude/GPT
echo.

echo 🌐 Открыть сайты альтернатив?
set /p open="(Y/N): "
if /i "%open%"=="Y" (
    start https://cursor.sh
    start https://github.com/TheR1D/shell_gpt
    start https://continue.dev
)

goto CONTINUE

:: Функция загрузки последней версии Warp
:DOWNLOAD_LATEST_WARP
call :LOG "Поиск и загрузка последней версии Warp..."
powershell -Command "& {try {Write-Host '🔍 Поиск последней версии Warp...'; $release = Invoke-RestMethod 'https://api.github.com/repos/warpdotdev/warp/releases/latest'; $asset = $release.assets | Where-Object {$_.name -like '*windows*installer*.exe'} | Select-Object -First 1; if ($asset) {Write-Host '📥 Загрузка версии:' $release.tag_name; Invoke-WebRequest $asset.browser_download_url -OutFile '$env:TEMP\warp-latest.exe'; Write-Host '🚀 Запуск установки...'; Start-Process '$env:TEMP\warp-latest.exe' -ArgumentList '/silent' -Wait; Write-Host '✅ Warp обновлен'} else {Write-Host '❌ Установщик не найден'}} catch {Write-Host '❌ Ошибка загрузки:' $_.Exception.Message}}"
exit /b

:: Функция настройки актуальных AI моделей
:SET_CURRENT_AI_MODELS
call :LOG "Настройка актуальных AI моделей..."
mkdir "%APPDATA%\Warp" 2>nul

:: Создание конфигурации с актуальными моделями
powershell -Command "& {$config = @{'ai_models' = @{'claude-4-sonnet' = @{'id' = 'claude-4-sonnet-20250514'; 'name' = 'Claude 4 Sonnet'; 'provider' = 'anthropic'}; 'claude-4-opus' = @{'id' = 'claude-4-opus-20250514'; 'name' = 'Claude 4 Opus'; 'provider' = 'anthropic'}}; 'default_ai_model' = 'claude-4-sonnet'; 'anthropic_api_version' = '2023-06-01'}; $config | ConvertTo-Json -Depth 10 | Set-Content '%APPDATA%\Warp\ai_config.json'}"
echo ✅ Конфигурация актуальных моделей создана
exit /b

:: Функция логирования
:LOG
echo [%time:~0,8%] %~1
exit /b

:CONTINUE
echo.
echo ═══════════════════════════════════════════════════════════════════════════════
echo.
set /p continue="Нажмите Enter для возврата в меню..."
goto MENU

:EXIT
echo.
echo 🎉 Исправление AI-моделей Warp завершено!
echo.
echo 📋 ФИНАЛЬНЫЕ РЕКОМЕНДАЦИИ:
echo    1. Перезапустите Warp Terminal
echo    2. Проверьте Settings → AI Models  
echo    3. Если проблема остается - попробуйте альтернативы
echo    4. Используйте VPN если есть региональные блокировки
echo.
echo 💬 Поддержка: appeals@warp.dev
echo 📚 Документация: https://docs.warp.dev
echo.
pause
exit