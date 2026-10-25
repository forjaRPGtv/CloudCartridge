@echo off
chcp 65001 >nul
title Publicar CloudCartridge no GitHub
cls
echo =========================================================================
echo              PUBLICAR CLOUDCARTRIDGE NO SEU GITHUB
echo =========================================================================
echo.
echo Este script conecta esta pasta local ao seu repositorio no GitHub.
echo.
echo 1. Crie um novo repositorio vazio no seu GitHub:
echo    Exemplo: https://github.com/SEU_USUARIO/CloudCartridge
echo    (Deixe desmarcada a opcao de criar README no GitHub para nao dar conflito)
echo.
set /p REPO_URL="Cole aqui o link HTTPS do seu repositorio GitHub: "

if "%REPO_URL%"=="" (
    echo.
    echo [Erro] Nenhum link informado. Operacao cancelada.
    pause
    exit /b 1
)

echo.
echo [1/3] Configurando branch principal (main)...
git branch -M main

echo [2/3] Vinculando ao repositorio remoto...
git remote remove origin 2>nul
git remote add origin %REPO_URL%

echo [3/3] Enviando arquivos para o GitHub...
git push -u origin main

if %errorlevel% equ 0 (
    echo.
    echo =========================================================================
    echo  SUCESSO! O CloudCartridge foi publicado no seu GitHub!
    echo =========================================================================
) else (
    echo.
    echo [Aviso] Se o envio falhou por diferencas de branch, tentando com force-push...
    git push -u origin main --force
)

echo.
pause
