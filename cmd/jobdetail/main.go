package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"os"
	"strconv"
	"time"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
	_ "github.com/jackc/pgx/v5/stdlib"
)

type Job struct {
	JobID          string    `json:"job_id"`
	ClientID       string    `json:"client_id"`
	SourceCurrency string    `json:"source_currency"`
	TargetCurrency string    `json:"target_currency"`
	SourceAmount   float64   `json:"source_amount"`
	TargetAmount   float64   `json:"target_amount"`
	Rate           float64   `json:"rate"`
	Fee            float64   `json:"fee"`
	Status         string    `json:"status"`
	CreatedAt      time.Time `json:"created_at"`
	CompletedAt    time.Time `json:"completed_at"`
}

var db *sql.DB
var dbErr error

func initDB(ctx context.Context) (*sql.DB, error) {
	if db != nil || dbErr != nil {
		return db, dbErr
	}
	host := getenv("DB_HOST", "postgres")
	port := getenv("DB_PORT", "5432")
	user := getenv("DB_USER", "postgres")
	pass := getenv("DB_PASSWORD", "postgrespw")
	name := getenv("DB_NAME", "jobsdb")
	dsn := fmt.Sprintf("postgres://%s:%s@%s:%s/%s?sslmode=disable", user, pass, host, port, name)
	db, dbErr = sql.Open("pgx", dsn)
	if dbErr != nil {
		return nil, dbErr
	}
	ctxPing, cancel := context.WithTimeout(ctx, 2*time.Second)
	defer cancel()
	if err := db.PingContext(ctxPing); err != nil {
		dbErr = err
	}
	return db, dbErr
}

func getenv(k, def string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return def
}

// handler supports:
// 1. GET /jobs/{job_id}?user_id=...  -> single completed job (optionally verify user)
// 2. GET /jobs?user_id=...&limit=N   -> list of completed jobs for user (default limit 50)
func handler(ctx context.Context, evt events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {
	if evt.HTTPMethod != http.MethodGet {
		return notFound(), nil
	}
	_, err := initDB(ctx)
	if err != nil {
		return serverError(err)
	}

	jobID := evt.PathParameters["job_id"]
	if jobID != "" { // single job path
		userFilter := evt.QueryStringParameters["user_id"]
		query := `SELECT job_id, client_id, source_currency, target_currency, source_amount, target_amount, rate, fee, status, created_at, completed_at
		FROM conversion_jobs WHERE job_id=$1 AND status='completed'`
		args := []any{jobID}
		if userFilter != "" {
			query += " AND client_id=$2"
			args = append(args, userFilter)
		}
		row := db.QueryRowContext(ctx, query, args...)
		var j Job
		if err := row.Scan(&j.JobID, &j.ClientID, &j.SourceCurrency, &j.TargetCurrency, &j.SourceAmount, &j.TargetAmount, &j.Rate, &j.Fee, &j.Status, &j.CreatedAt, &j.CompletedAt); err != nil {
			if errors.Is(err, sql.ErrNoRows) {
				return notFound(), nil
			}
			return serverError(err)
		}
		b, _ := json.Marshal(j)
		return events.APIGatewayProxyResponse{StatusCode: 200, Body: string(b), Headers: map[string]string{"Content-Type": "application/json"}}, nil
	}

	// list mode requires user_id
	userID := evt.QueryStringParameters["user_id"]
	if userID == "" {
		return clientError(400, "user_id required")
	}
	limit := 50
	if lStr := evt.QueryStringParameters["limit"]; lStr != "" {
		if n, err := strconv.Atoi(lStr); err == nil && n > 0 && n <= 500 {
			limit = n
		}
	}
	rows, err := db.QueryContext(ctx, `SELECT job_id, client_id, source_currency, target_currency, source_amount, target_amount, rate, fee, status, created_at, completed_at
	FROM conversion_jobs WHERE client_id=$1 AND status='completed' ORDER BY completed_at DESC NULLS LAST, created_at DESC LIMIT $2`, userID, limit)
	if err != nil {
		return serverError(err)
	}
	defer rows.Close()
	var out struct {
		UserID string `json:"user_id"`
		Jobs   []Job  `json:"jobs"`
	}
	out.UserID = userID
	for rows.Next() {
		var j Job
		if err := rows.Scan(&j.JobID, &j.ClientID, &j.SourceCurrency, &j.TargetCurrency, &j.SourceAmount, &j.TargetAmount, &j.Rate, &j.Fee, &j.Status, &j.CreatedAt, &j.CompletedAt); err != nil {
			return serverError(err)
		}
		out.Jobs = append(out.Jobs, j)
	}
	if err := rows.Err(); err != nil {
		return serverError(err)
	}
	b, _ := json.Marshal(out)
	return events.APIGatewayProxyResponse{StatusCode: 200, Body: string(b), Headers: map[string]string{"Content-Type": "application/json"}}, nil
}

func notFound() events.APIGatewayProxyResponse {
	return events.APIGatewayProxyResponse{StatusCode: 404, Body: `{"error":"not found"}`, Headers: map[string]string{"Content-Type": "application/json"}}
}
func clientError(code int, msg string) (events.APIGatewayProxyResponse, error) {
	return events.APIGatewayProxyResponse{StatusCode: code, Body: fmt.Sprintf(`{"error":"%s"}`, msg), Headers: map[string]string{"Content-Type": "application/json"}}, nil
}
func serverError(err error) (events.APIGatewayProxyResponse, error) {
	fmt.Println("ERR:", err)
	return events.APIGatewayProxyResponse{StatusCode: 500, Body: `{"error":"internal"}`, Headers: map[string]string{"Content-Type": "application/json"}}, nil
}

func main() { lambda.Start(handler) }
