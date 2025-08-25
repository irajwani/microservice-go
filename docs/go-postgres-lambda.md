# Go Lambda Postgres Integration

This document explains how the `create_job_lambda` function connects to the local Postgres instance and performs a transactional insert of both a `conversion_jobs` record and a matching `outbox` row (transactional outbox pattern).

## Overview

Request flow (POST /jobs via API Gateway REST):
1. API Gateway invokes Lambda with JSON body.
2. Lambda unmarshals into `JobRequest` and validates required fields.
3. Lambda initializes (or reuses) a global DB connection pool on cold start using environment variables.
4. If an `idempotency_key` is provided, Lambda first attempts to find an existing job with the same key.
5. If none exists, it starts a transaction:
   - Inserts the new job row into `conversion_jobs`.
   - Inserts an outbox row with topic `conversion-jobs` and a JSON payload of the job.
6. Commits the transaction and returns the job payload.

All DB operations share a short timeout (3s) to avoid hanging the Lambda execution.

## Environment Variables

Provisioned via Terraform in `lambda.tf`:
- `DB_HOST` (default `postgres`) – Docker Compose service name.
- `DB_PORT` (default `5432`).
- `DB_USER` (default `postgres`).
- `DB_PASSWORD` (default `postgrespw`).
- `DB_NAME` (default `jobsdb`).

You can override these by adjusting Terraform variables (`db_host`, `db_port`, `db_username`, `db_password`, `db_name`).

## Connection Management

A `sync.Once` guards initialization in `initDB`. Lambda execution environment is reused between invocations so the pool persists for warm starts. Settings:
- Max open & idle connections: 4 (small footprint locally).
- Idle timeout: 5 minutes.

If initialization fails (e.g., DB down) a 500 error is returned and the error is logged (`serverError`).

## Idempotency Handling

If `idempotency_key` is present:
1. `SELECT .. FROM conversion_jobs WHERE idempotency_key = $1`.
2. If found, return the existing job (HTTP 200) without inserting a new job or outbox message.
3. If not found, proceed to insert new job + outbox (HTTP 201).

This is a simple approach that avoids race conditions in most single-writer scenarios. For full concurrency safety you can enforce the partial unique index (already present) and catch conflicts, but that's deferred for clarity.

## Transactional Outbox

Both inserts happen inside a single transaction. If either fails the transaction rolls back, ensuring no outbox message without a job and vice versa. The outbox schema supports a future publisher that:
- Selects unsent rows `processed_at IS NULL` and not locked.
- Claims them with `locked_until` or `FOR UPDATE SKIP LOCKED`.
- Sends payload to SQS queue, then updates `processed_at`.

## SQL Executed

Job insert:
```
INSERT INTO conversion_jobs (
  job_id, client_id, source_currency, target_currency, source_amount, status, idempotency_key, created_at, updated_at
) VALUES ($1,$2,$3,$4,$5,'queued',$6,$7,$7)
```
Outbox insert:
```
INSERT INTO outbox (aggregate_type, aggregate_id, topic, payload)
VALUES ('conversion_job', $1, 'conversion-jobs', $2)
```

## Error Responses

- Validation / JSON issues: 400 with `{"error":"..."}`.
- Not found route: 404.
- DB or internal errors: 500 with generic `{"error":"internal"}` (details in CloudWatch logs / stdout under LocalStack).

## Local Testing

1. Ensure containers running:
```
docker compose up -d postgres localstack
```
2. (Re)apply Terraform to build & deploy Lambda:
```
cd terraform
sh apply.sh   # or terraform apply -auto-approve
```
3. Invoke endpoint (example payload):
```
curl -s -X POST \
  -H 'Content-Type: application/json' \
  -d '{"client_id":"c1","source_currency":"USD","target_currency":"EUR","source_amount":123.45}' \
  http://localhost:4566/restapis/$(aws --endpoint-url=http://localhost:4566 apigateway get-rest-apis --query 'items[?name==`currency-jobs-api`].id' --output text)/dev/_user_request_/jobs | jq .
```
4. Inspect DB (optional):
```
psql postgres://postgres:postgrespw@localhost:5432/jobsdb -c 'select job_id, client_id, status from conversion_jobs order by created_at desc limit 5;'
psql postgres://postgres:postgrespw@localhost:5432/jobsdb -c 'select outbox_id, aggregate_id, topic from outbox order by created_at desc limit 5;'
```

## Next Steps (Optional Enhancements)
- Catch unique violation on `idempotency_key` to eliminate race window (use `INSERT ... ON CONFLICT` returning existing row).
- Implement outbox dispatcher worker (Lambda or local Go binary) to push messages to SQS.
- Add structured logging & correlation IDs.
- Move DB credentials to a secret manager for production.
- Increase timeouts / pool size for higher throughput; add retry logic on transient errors.

## Learning Pointers (Go Concepts Illustrated)
- `sync.Once` for safe lazy initialization.
- Using `database/sql` with pgx driver.
- Context timeouts for external calls (DB) to bound execution.
- Marshaling/unmarshaling JSON for request/response and outbox payload.
- Simple idempotency pattern.

Refer back to `main.go` to trace each concept inline.
