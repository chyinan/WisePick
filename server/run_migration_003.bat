@echo off
chcp 65001 >nul
echo Running migration 003_add_security_questions...
echo.

REM Database connection parameters
set DB_HOST=localhost
set DB_PORT=5432
set DB_NAME=wisepick
set DB_USER=postgres
set PGCLIENTENCODING=UTF8

REM Run migration script
psql -h %DB_HOST% -p %DB_PORT% -d %DB_NAME% -U %DB_USER% -f "lib\database\migrations\003_add_security_questions.sql"

echo.
echo Migration completed!
pause
