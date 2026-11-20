@echo off
chcp 65001 >nul

REM ----------------------------------------------------------
REM RamsesDB - Spoustec PHP sestaveni
REM ----------------------------------------------------------

echo Spoustim PHP build skript...
php "../BuildRelease.php" BuildListDb.txt ..\temp\BcmOsirisDb00.txt 380000

xcopy /Y F:\OneDrive\AktualneSePracuje\BcmOsiris ..\temp\
xcopy /Y ../Knowledge.txt ..\temp\

pause