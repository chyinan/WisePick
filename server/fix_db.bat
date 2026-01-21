@echo off
set PGPASSWORD=popcap
echo === Running database fix migration ===
"C:\Program Files\PostgreSQL\18\bin\psql.exe" -U postgres -h localhost -d wisepick -f "D:\Program\wisepick_dart_version\server\lib\database\migrations\002_fix_constraints.sql"
echo.
echo === Fix migration completed ===
