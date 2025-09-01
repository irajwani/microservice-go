#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob
HOST="${POSTGRES_HOST:-postgres}"
USER="${POSTGRES_USER:-postgres}"
DB="${POSTGRES_DB:-postgres}" 
PASS="${POSTGRES_PASSWORD:-}"
export PGPASSWORD="$PASS"
FILES=(/migrations/*.sql)
if [ ${#FILES[@]} -eq 0 ]; then
  echo "No migration files found"; exit 0
fi
for file in "${FILES[@]}"; do
  echo "Applying $file";
  psql -v ON_ERROR_STOP=1 -h "$HOST" -U "$USER" -d "$DB" -f "$file";
  echo "Applied $file"
done
echo "All migrations applied"
