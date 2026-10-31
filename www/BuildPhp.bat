@echo off
chcp 65001 >nul

REM ----------------------------------------------------------
REM RamsesDB - Spoustec PHP sestaveni
REM ----------------------------------------------------------

echo Spoustim PHP build skript...
php "../BuildRelease.php" BuildListPhp.txt

pause