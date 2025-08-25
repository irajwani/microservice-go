// main.go
package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"os"
	"sync"
	"time"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/sqs"
	"github.com/google/uuid"
	_ "github.com/jackc/pgx/v5/stdlib"
)

// JobRequest represents an incoming job creation payload
type JobRequest struct {
	ClientID       string  `json:"client_id"`
	SourceCurrency string  `json:"source_currency"`
	TargetCurrency string  `json:"target_currency"`
	SourceAmount   float64 `json:"source_amount"`
	IdempotencyKey *string `json:"idempotency_key,omitempty"`
}

// JobResponse represents the response returned to the caller
type JobResponse struct {
	JobID          string    `json:"job_id"`
	Status         string    `json:"status"`
	ClientID       string    `json:"client_id"`
	SourceCurrency string    `json:"source_currency"`
	TargetCurrency string    `json:"target_currency"`
	SourceAmount   float64   `json:"source_amount"`
	IdempotencyKey *string   `json:"idempotency_key,omitempty"`
	CreatedAt      time.Time `json:"created_at"`
}

func validate(req JobRequest) error {
	if req.ClientID == "" {
		return errors.New("client_id is required")
	}
	if req.SourceCurrency == "" || len(req.SourceCurrency) != 3 {
		return errors.New("source_currency must be 3-letter code")
	}
	if req.TargetCurrency == "" || len(req.TargetCurrency) != 3 {
		return errors.New("target_currency must be 3-letter code")
	}
	if req.SourceAmount <= 0 {
		return errors.New("source_amount must be > 0")
	}
	return nil
}

// handler supports API Gateway REST proxy POST /jobs
var (
	dbInit sync.Once
	db     *sql.DB
	dbErr  error
)

var (
	sqsInit sync.Once
	sqsCli  *sqs.Client
	sqsErr  error
)

func initDB(ctx context.Context) (*sql.DB, error) {
	dbInit.Do(func() {
		host := getenv("DB_HOST", "localhost")
		port := getenv("DB_PORT", "5432")
		user := getenv("DB_USER", "postgres")
		pass := getenv("DB_PASSWORD", "postgrespw")
		name := getenv("DB_NAME", "jobsdb")
		dsn := fmt.Sprintf("postgres://%s:%s@%s:%s/%s?sslmode=disable", user, pass, host, port, name)
		db, dbErr = sql.Open("pgx", dsn)
		if dbErr != nil {
			return
		}
		// Set modest pool limits appropriate for Lambda reuse
		db.SetMaxOpenConns(4)
		db.SetMaxIdleConns(4)
		db.SetConnMaxIdleTime(5 * time.Minute)
		// Ping with timeout
		c, cancel := context.WithTimeout(ctx, 2*time.Second)
		defer cancel()
		dbErr = db.PingContext(c)
	})
	return db, dbErr
}

func getenv(k, def string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return def
}

func handler(ctx context.Context, evt events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {
	// Basic routing: only care about POST /jobs
	if evt.HTTPMethod != http.MethodPost || evt.Path != "/jobs" {
		return events.APIGatewayProxyResponse{StatusCode: http.StatusNotFound, Body: `{"message":"not found"}`}, nil
	}

	var jr JobRequest
	if err := json.Unmarshal([]byte(evt.Body), &jr); err != nil {
		return clientError(http.StatusBadRequest, fmt.Sprintf("invalid json: %v", err))
	}
	if err := validate(jr); err != nil {
		return clientError(http.StatusBadRequest, err.Error())
	}

	// Initialize DB (cold start or first invocation)
	db, err := initDB(ctx)
	if err != nil {
		return serverError(fmt.Errorf("db init: %w", err))
	}
	// Context with timeout for DB ops
	opCtx, cancel := context.WithTimeout(ctx, 3*time.Second)
	defer cancel()

	// Idempotency: if key present, return existing job if found
	if jr.IdempotencyKey != nil {
		var existing JobResponse
		row := db.QueryRowContext(opCtx, `SELECT job_id, status, client_id, source_currency, target_currency, source_amount, idempotency_key, created_at
			FROM conversion_jobs WHERE idempotency_key = $1`, *jr.IdempotencyKey)
		if err := row.Scan(&existing.JobID, &existing.Status, &existing.ClientID, &existing.SourceCurrency, &existing.TargetCurrency, &existing.SourceAmount, &existing.IdempotencyKey, &existing.CreatedAt); err == nil {
			b, _ := json.Marshal(existing)
			return events.APIGatewayProxyResponse{StatusCode: http.StatusOK, Headers: map[string]string{"Content-Type": "application/json"}, Body: string(b)}, nil
		}
	}

	jobID := uuid.NewString()
	createdAt := time.Now().UTC()

	tx, err := db.BeginTx(opCtx, &sql.TxOptions{})
	if err != nil {
		return serverError(fmt.Errorf("begin tx: %w", err))
	}
	defer func() { _ = tx.Rollback() }()

	// Insert job
	_, err = tx.ExecContext(opCtx, `INSERT INTO conversion_jobs (job_id, client_id, source_currency, target_currency, source_amount, status, idempotency_key, created_at, updated_at)
		VALUES ($1,$2,$3,$4,$5,'queued',$6,$7,$7)`, jobID, jr.ClientID, jr.SourceCurrency, jr.TargetCurrency, jr.SourceAmount, jr.IdempotencyKey, createdAt)
	if err != nil {
		return serverError(fmt.Errorf("insert job: %w", err))
	}

	resp := JobResponse{
		JobID:          jobID,
		Status:         "queued",
		ClientID:       jr.ClientID,
		SourceCurrency: jr.SourceCurrency,
		TargetCurrency: jr.TargetCurrency,
		SourceAmount:   jr.SourceAmount,
		IdempotencyKey: jr.IdempotencyKey,
		CreatedAt:      createdAt,
	}
	payload, _ := json.Marshal(resp)

	// Insert outbox row
	_, err = tx.ExecContext(opCtx, `INSERT INTO outbox (aggregate_type, aggregate_id, topic, payload) VALUES ($1,$2,$3,$4)`,
		"conversion_job", jobID, "conversion-jobs", payload)
	if err != nil {
		return serverError(fmt.Errorf("insert outbox: %w", err))
	}

	if err = tx.Commit(); err != nil {
		return serverError(fmt.Errorf("commit: %w", err))
	}

	// Publish to SQS (best effort). Failure does not roll back DB commit.
	publishCtx, cancelPub := context.WithTimeout(ctx, 2*time.Second)
	defer cancelPub()
	queueURL := os.Getenv("QUEUE_URL")
	if queueURL != "" {
		sqsInit.Do(func() {
			cfg, e := config.LoadDefaultConfig(publishCtx, config.WithRegion(getenv("AWS_REGION", "eu-central-1")))
			if e != nil {
				sqsErr = e
				return
			}
			sqsCli = sqs.NewFromConfig(cfg)
		})
		if sqsErr == nil && sqsCli != nil {
			if _, e := sqsCli.SendMessage(publishCtx, &sqs.SendMessageInput{QueueUrl: &queueURL, MessageBody: ptr(string(payload))}); e != nil {
				fmt.Println("WARN: failed to publish SQS message:", e)
			}
		} else if sqsErr != nil {
			fmt.Println("WARN: sqs init error:", sqsErr)
		}
	}

	b, _ := json.Marshal(resp)
	return events.APIGatewayProxyResponse{StatusCode: http.StatusCreated, Headers: map[string]string{"Content-Type": "application/json"}, Body: string(b)}, nil
}

func clientError(code int, msg string) (events.APIGatewayProxyResponse, error) {
	body := fmt.Sprintf(`{"error":"%s"}`, msg)
	return events.APIGatewayProxyResponse{StatusCode: code, Body: body, Headers: map[string]string{"Content-Type": "application/json"}}, nil
}

func main() {
	lambda.Start(handler)
}

func serverError(err error) (events.APIGatewayProxyResponse, error) {
	fmt.Println("ERROR:", err)
	return events.APIGatewayProxyResponse{StatusCode: http.StatusInternalServerError, Body: `{"error":"internal"}`, Headers: map[string]string{"Content-Type": "application/json"}}, nil
}

func ptr[T any](v T) *T { return &v }
