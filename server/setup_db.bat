@echo off
set PGPASSWORD=popcap
"C:\Program Files\PostgreSQL\18\bin\psql.exe" -U postgres -h localhost -c "CREATE DATABASE wisepick WITH ENCODING='UTF8';"
echo Database creation completed.
"C:\Program Files\PostgreSQL\18\bin\psql.exe" -U postgres -h localhost -d wisepick -f "D:\Program\wisepick_dart_version\server\lib\database\migrations\001_create_user_tables.sql"
echo Migration completed.
