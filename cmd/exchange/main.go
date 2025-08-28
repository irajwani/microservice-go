package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"net/http"
	"os"
	"time"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
	"github.com/google/uuid"
	_ "github.com/jackc/pgx/v5/stdlib"
)

// ExchangeRequest expects user_id, source_currency, target_currency, amount
// Using user_id same as client_id for now.
type ExchangeRequest struct {
	UserID         string  `json:"user_id"`
	SourceCurrency string  `json:"source_currency"`
	TargetCurrency string  `json:"target_currency"`
	SourceAmount   float64 `json:"source_amount"`
}

type ExchangeResponse struct {
	JobID          string  `json:"job_id"`
	UserID         string  `json:"user_id"`
	SourceCurrency string  `json:"source_currency"`
	TargetCurrency string  `json:"target_currency"`
	SourceAmount   float64 `json:"source_amount"`
	TargetAmount   float64 `json:"target_amount"`
	Rate           float64 `json:"rate"`
	Fee            float64 `json:"fee"`
	Status         string  `json:"status"`
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
	c, cancel := context.WithTimeout(ctx, 2*time.Second)
	defer cancel()
	if err := db.PingContext(c); err != nil {
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

func validate(req ExchangeRequest) error {
	if req.UserID == "" {
		return errors.New("user_id required")
	}
	if len(req.SourceCurrency) != 3 || len(req.TargetCurrency) != 3 {
		return errors.New("currencies must be 3-letter")
	}
	if req.SourceCurrency == req.TargetCurrency {
		return errors.New("currencies must differ")
	}
	if req.SourceAmount <= 0 {
		return errors.New("source_amount must be > 0")
	}
	return nil
}

// mockRate returns rate, fee (absolute)
func mockRate(source, target string, amount float64) (rate float64, fee float64) {
	base := map[string]float64{"USD:EUR": 0.90, "EUR:USD": 1.16, "USD:GBP": 1.26, "GBP:USD": 0.79, "EUR:GBP": 1.16, "GBP:EUR": 0.90}
	rate = base[source+":"+target]
	if rate == 0 {
		rate = 1.0
	}
	// Tiered fee bps depending on amount
	bps := 30.0
	if amount > 1000 {
		bps = 20
	} else if amount > 10000 {
		bps = 10
	}
	fee = amount * rate * bps / 10000.0
	return
}

func handler(ctx context.Context, evt events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {
	if evt.HTTPMethod != http.MethodPost || evt.Path != "/exchange" {
		return events.APIGatewayProxyResponse{StatusCode: http.StatusNotFound, Body: `{"error":"not found"}`}, nil
	}
	var req ExchangeRequest
	if err := json.Unmarshal([]byte(evt.Body), &req); err != nil {
		return clientError(400, "invalid json")
	}
	if err := validate(req); err != nil {
		return clientError(400, err.Error())
	}

	db, err := initDB(ctx)
	if err != nil {
		return serverError(err)
	}

	rate, fee := mockRate(req.SourceCurrency, req.TargetCurrency, req.SourceAmount)
	targetAmount := req.SourceAmount*rate - fee
	if targetAmount < 0 {
		targetAmount = 0
	}
	jobID := uuid.NewString()

	tx, err := db.BeginTx(ctx, &sql.TxOptions{})
	if err != nil {
		return serverError(err)
	}
	defer tx.Rollback()

	// Ensure source and target accounts exist (upsert style)
	ensureAccount := func(user, cur string) (id string, err error) {
		// Try select
		if err = tx.QueryRowContext(ctx, `SELECT account_id FROM accounts WHERE user_id=$1 AND currency=$2`, user, cur).Scan(&id); err == nil {
			return
		}
		if errors.Is(err, sql.ErrNoRows) {
			if err = tx.QueryRowContext(ctx, `INSERT INTO accounts (user_id, currency, balance) VALUES ($1,$2,0) RETURNING account_id`, user, cur).Scan(&id); err != nil {
				return "", err
			}
			return id, nil
		}
		return "", err
	}
	sourceAcct, err := ensureAccount(req.UserID, req.SourceCurrency)
	if err != nil {
		return serverError(err)
	}
	targetAcct, err := ensureAccount(req.UserID, req.TargetCurrency)
	if err != nil {
		return serverError(err)
	}

	// Lock rows FOR UPDATE to prevent race
	var srcBalance, tgtBalance float64
	if err = tx.QueryRowContext(ctx, `SELECT balance FROM accounts WHERE account_id=$1 FOR UPDATE`, sourceAcct).Scan(&srcBalance); err != nil {
		return serverError(err)
	}
	if err = tx.QueryRowContext(ctx, `SELECT balance FROM accounts WHERE account_id=$1 FOR UPDATE`, targetAcct).Scan(&tgtBalance); err != nil {
		return serverError(err)
	}
	if srcBalance < req.SourceAmount {
		return clientError(400, "insufficient funds")
	}

	// Perform balance updates
	if _, err = tx.ExecContext(ctx, `UPDATE accounts SET balance = balance - $1 WHERE account_id=$2`, req.SourceAmount, sourceAcct); err != nil {
		return serverError(err)
	}
	if _, err = tx.ExecContext(ctx, `UPDATE accounts SET balance = balance + $1 WHERE account_id=$2`, targetAmount, targetAcct); err != nil {
		return serverError(err)
	}

	// Insert job (completed immediately here)
	if _, err = tx.ExecContext(ctx, `INSERT INTO conversion_jobs (job_id, client_id, source_currency, target_currency, source_amount, status, created_at, updated_at, target_amount, rate, fee, completed_at)
	 VALUES ($1,$2,$3,$4,$5,'completed',now(),now(),$6,$7,$8,now())`, jobID, req.UserID, req.SourceCurrency, req.TargetCurrency, req.SourceAmount, targetAmount, rate, fee); err != nil {
		return serverError(fmt.Errorf("insert job: %w", err))
	}

	// Double-entry ledger entries
	if _, err = tx.ExecContext(ctx, `INSERT INTO ledger_entries (job_id, account_id, entry_type, amount, currency) VALUES ($1,$2,'debit',$3,$4)`, jobID, sourceAcct, req.SourceAmount, req.SourceCurrency); err != nil {
		return serverError(err)
	}
	if _, err = tx.ExecContext(ctx, `INSERT INTO ledger_entries (job_id, account_id, entry_type, amount, currency) VALUES ($1,$2,'credit',$3,$4)`, jobID, targetAcct, targetAmount, req.TargetCurrency); err != nil {
		return serverError(err)
	}

	// Outbox event (simplified payload)
	payload, _ := json.Marshal(map[string]any{
		"event": "conversion.completed", "job_id": jobID, "user_id": req.UserID, "source_currency": req.SourceCurrency, "target_currency": req.TargetCurrency, "source_amount": req.SourceAmount, "target_amount": targetAmount, "rate": rate, "fee": fee,
	})
	if _, err = tx.ExecContext(ctx, `INSERT INTO outbox (aggregate_type, aggregate_id, topic, payload) VALUES ('conversion_job',$1,'conversion-events',$2)`, jobID, payload); err != nil {
		return serverError(err)
	}

	if err = tx.Commit(); err != nil {
		return serverError(err)
	}

	resp := ExchangeResponse{JobID: jobID, UserID: req.UserID, SourceCurrency: req.SourceCurrency, TargetCurrency: req.TargetCurrency, SourceAmount: req.SourceAmount, TargetAmount: targetAmount, Rate: rate, Fee: fee, Status: "completed"}
	b, _ := json.Marshal(resp)
	return events.APIGatewayProxyResponse{StatusCode: 201, Headers: map[string]string{"Content-Type": "application/json"}, Body: string(b)}, nil
}

func main() { lambda.Start(handler) }

func clientError(code int, msg string) (events.APIGatewayProxyResponse, error) {
	return events.APIGatewayProxyResponse{StatusCode: code, Body: fmt.Sprintf(`{"error":"%s"}`, msg), Headers: map[string]string{"Content-Type": "application/json"}}, nil
}
func serverError(err error) (events.APIGatewayProxyResponse, error) {
	fmt.Println("ERR:", err)
	return events.APIGatewayProxyResponse{StatusCode: 500, Body: `{"error":"internal"}`, Headers: map[string]string{"Content-Type": "application/json"}}, nil
}

// Avoid -0 values
func round(v float64) float64 {
	if math.Abs(v) < 1e-12 {
		return 0
	}
	return v
}
