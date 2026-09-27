@echo off
title Rick ^& Morty AI Executor - Cowork Bridge
cd /d "%~dp0"

where node >nul 2>nul
if errorlevel 1 (
    echo.
    echo   Node.js was not found on your PATH.
    echo   Install it from https://nodejs.org ^(LTS, 18 or newer^) and run this file again.
    echo.
    pause
    exit /b 1
)

echo.
echo   Starting the Cowork bridge on http://localhost:7896 ...
echo.

start "" "http://localhost:7896"
node "%~dp0server.js"

echo.
echo   Bridge stopped.
pause
