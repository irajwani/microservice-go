package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"time"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	awslambda "github.com/aws/aws-sdk-go-v2/service/lambda"
	_ "github.com/jackc/pgx/v5/stdlib"
)

// JobMessage mirrors what /jobs publishes
type JobMessage struct {
	JobID          string    `json:"job_id"`
	ClientID       string    `json:"client_id"`
	SourceCurrency string    `json:"source_currency"`
	TargetCurrency string    `json:"target_currency"`
	SourceAmount   float64   `json:"source_amount"`
	CreatedAt      time.Time `json:"created_at"`
}

type RateResponse struct {
	Source   string  `json:"source"`
	Target   string  `json:"target"`
	Rate     float64 `json:"rate"`
	FeeBps   int     `json:"fee_bps"`
	Provider string  `json:"provider"`
}

var (
	db    *sql.DB
	dbErr error
)

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
	dbErr = db.PingContext(ctxPing)
	return db, dbErr
}

func getenv(k, def string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return def
}

func handler(ctx context.Context, evt events.SQSEvent) error {
	if len(evt.Records) == 0 {
		return nil
	}
	// Init resources
	db, err := initDB(ctx)
	if err != nil {
		return fmt.Errorf("db: %w", err)
	}
	cfg, err := config.LoadDefaultConfig(ctx, config.WithRegion(getenv("AWS_REGION", "eu-central-1")))
	if err != nil {
		return fmt.Errorf("aws cfg: %w", err)
	}
	lambdaClient := awslambda.NewFromConfig(cfg)
	rateLambda := os.Getenv("RATE_LAMBDA_NAME")
	if rateLambda == "" {
		return fmt.Errorf("RATE_LAMBDA_NAME not set")
	}

	for _, r := range evt.Records {
		var msg JobMessage
		if err := json.Unmarshal([]byte(r.Body), &msg); err != nil {
			fmt.Println("bad msg", err)
			continue
		}

		// Transactional execution
		if err := processJob(ctx, db, lambdaClient, rateLambda, msg); err != nil {
			fmt.Println("job", msg.JobID, "error:", err)
			continue
		}
	}
	return nil
}

func processJob(ctx context.Context, db *sql.DB, lambdaClient *awslambda.Client, rateLambda string, msg JobMessage) error {
	tx, err := db.BeginTx(ctx, &sql.TxOptions{})
	if err != nil {
		return err
	}
	defer tx.Rollback()

	// Lock job row (must exist & be queued). If status already completed/failed, skip (idempotent)
	var status string
	row := tx.QueryRowContext(ctx, `SELECT status FROM conversion_jobs WHERE job_id=$1 FOR UPDATE`, msg.JobID)
	if err := row.Scan(&status); err != nil {
		return fmt.Errorf("load job: %w", err)
	}
	if status != "queued" { // nothing to do
		return nil
	}

	// Ensure accounts exist
	srcAcct, err := ensureAccount(ctx, tx, msg.ClientID, msg.SourceCurrency)
	if err != nil {
		return err
	}
	tgtAcct, err := ensureAccount(ctx, tx, msg.ClientID, msg.TargetCurrency)
	if err != nil {
		return err
	}

	// Lock source & target balances
	var srcBalance float64
	if err = tx.QueryRowContext(ctx, `SELECT balance FROM accounts WHERE account_id=$1 FOR UPDATE`, srcAcct).Scan(&srcBalance); err != nil {
		return err
	}
	if srcBalance < msg.SourceAmount { // fail job
		if _, e := tx.ExecContext(ctx, `UPDATE conversion_jobs SET status='failed', updated_at=now(), metadata = jsonb_set(metadata,'{"error"}', to_jsonb('insufficient_funds')) WHERE job_id=$1`, msg.JobID); e != nil {
			return fmt.Errorf("fail job: %v original %w", e, errors.New("insufficient funds"))
		}
		return tx.Commit()
	}

	// Rate lookup (inside txn for simplicity). We must invoke the rate lambda with an API Gateway proxy style
	// request because the rate lambda expects events.APIGatewayProxyRequest. Provide queryStringParameters.
	payloadReq := fmt.Sprintf(`{"resource":"/rate","path":"/rate","httpMethod":"GET","queryStringParameters":{"source":"%s","target":"%s"},"headers":{},"isBase64Encoded":false}`, msg.SourceCurrency, msg.TargetCurrency)
	invOut, err := lambdaClient.Invoke(ctx, &awslambda.InvokeInput{FunctionName: aws.String(rateLambda), Payload: []byte(payloadReq)})
	if err != nil {
		return fmt.Errorf("invoke rate: %w", err)
	}
	if invOut.FunctionError != nil {
		return fmt.Errorf("rate lambda error: %s", *invOut.FunctionError)
	}

	var rateResp RateResponse
	// Try API Gateway proxy response envelope first
	type apigwResp struct {
		StatusCode      int               `json:"statusCode"`
		Body            string            `json:"body"`
		IsBase64Encoded bool              `json:"isBase64Encoded"`
		Headers         map[string]string `json:"headers"`
	}
	var gw apigwResp
	if err := json.Unmarshal(invOut.Payload, &gw); err == nil && gw.Body != "" { // looks like proxy envelope
		if gw.StatusCode != 200 {
			return fmt.Errorf("rate lambda status %d", gw.StatusCode)
		}
		if err := json.Unmarshal([]byte(gw.Body), &rateResp); err != nil {
			return fmt.Errorf("decode rate body: %w", err)
		}
	} else {
		// Fall back: attempt direct decode into RateResponse
		if err2 := json.Unmarshal(invOut.Payload, &rateResp); err2 != nil {
			return fmt.Errorf("decode rate: %v (envelope err: %v)", err2, err)
		}
	}
	if rateResp.Rate <= 0 {
		return fmt.Errorf("invalid rate response: %+v", rateResp)
	}
	feePct := float64(rateResp.FeeBps) / 10000.0
	targetAmount := msg.SourceAmount * rateResp.Rate * (1 - feePct)
	fee := msg.SourceAmount * rateResp.Rate * feePct
	if targetAmount <= 0 {
		return fmt.Errorf("computed non-positive target amount (rate %.8f feePct %.6f src %.8f)", rateResp.Rate, feePct, msg.SourceAmount)
	}

	// Update balances
	if _, err = tx.ExecContext(ctx, `UPDATE accounts SET balance = balance - $1 WHERE account_id=$2`, msg.SourceAmount, srcAcct); err != nil {
		return err
	}
	if _, err = tx.ExecContext(ctx, `UPDATE accounts SET balance = balance + $1 WHERE account_id=$2`, targetAmount, tgtAcct); err != nil {
		return err
	}

	// Ledger entries
	if _, err = tx.ExecContext(ctx, `INSERT INTO ledger_entries (job_id, account_id, entry_type, amount, currency) VALUES ($1,$2,'debit',$3,$4)`, msg.JobID, srcAcct, msg.SourceAmount, msg.SourceCurrency); err != nil {
		return err
	}
	if _, err = tx.ExecContext(ctx, `INSERT INTO ledger_entries (job_id, account_id, entry_type, amount, currency) VALUES ($1,$2,'credit',$3,$4)`, msg.JobID, tgtAcct, targetAmount, msg.TargetCurrency); err != nil {
		return err
	}

	// Update job
	if _, err = tx.ExecContext(ctx, `UPDATE conversion_jobs SET status='completed', target_amount=$2, rate=$3, fee=$4, completed_at=now(), updated_at=now() WHERE job_id=$1`, msg.JobID, targetAmount, rateResp.Rate, fee); err != nil {
		return err
	}

	// Outbox event
	payload, _ := json.Marshal(map[string]any{"event": "conversion.completed", "job_id": msg.JobID, "user_id": msg.ClientID, "source_currency": msg.SourceCurrency, "target_currency": msg.TargetCurrency, "source_amount": msg.SourceAmount, "target_amount": targetAmount, "rate": rateResp.Rate, "fee": fee})
	if _, err = tx.ExecContext(ctx, `INSERT INTO outbox (aggregate_type, aggregate_id, topic, payload) VALUES ('conversion_job',$1,'conversion-events',$2)`, msg.JobID, payload); err != nil {
		return err
	}

	return tx.Commit()
}

func ensureAccount(ctx context.Context, tx *sql.Tx, user, currency string) (string, error) {
	var id string
	err := tx.QueryRowContext(ctx, `SELECT account_id FROM accounts WHERE user_id=$1 AND currency=$2`, user, currency).Scan(&id)
	if err == nil {
		return id, nil
	}
	if errors.Is(err, sql.ErrNoRows) {
		if e := tx.QueryRowContext(ctx, `INSERT INTO accounts (user_id, currency, balance) VALUES ($1,$2,0) RETURNING account_id`, user, currency).Scan(&id); e != nil {
			return "", e
		}
		return id, nil
	}
	return "", err
}

func main() { lambda.Start(handler) }
