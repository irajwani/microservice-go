package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"net/http"
	"os"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
	_ "github.com/jackc/pgx/v5/stdlib"
)

type Balance struct {
	Currency string  `json:"currency"`
	Balance  float64 `json:"balance"`
}

type BalanceResponse struct {
	UserID   string    `json:"user_id"`
	Accounts []Balance `json:"accounts"`
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
	return db, dbErr
}

func getenv(k, def string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return def
}

func handler(ctx context.Context, evt events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {
	if evt.HTTPMethod != http.MethodGet || evt.Path != "/balances" {
		return events.APIGatewayProxyResponse{StatusCode: 404, Body: `{"error":"not found"}`}, nil
	}
	userID := evt.QueryStringParameters["user_id"]
	if userID == "" {
		return clientError(400, "user_id required")
	}
	_, err := initDB(ctx)
	if err != nil {
		return serverError(err)
	}
	rows, err := db.QueryContext(ctx, `SELECT currency, balance FROM accounts WHERE user_id=$1 ORDER BY currency`, userID)
	if err != nil {
		return serverError(err)
	}
	defer rows.Close()
	res := BalanceResponse{UserID: userID}
	for rows.Next() {
		var b Balance
		if err := rows.Scan(&b.Currency, &b.Balance); err != nil {
			return serverError(err)
		}
		res.Accounts = append(res.Accounts, b)
	}
	if err := rows.Err(); err != nil {
		return serverError(err)
	}
	body, _ := json.Marshal(res)
	return events.APIGatewayProxyResponse{StatusCode: 200, Body: string(body), Headers: map[string]string{"Content-Type": "application/json"}}, nil
}

func main() { lambda.Start(handler) }

func clientError(code int, msg string) (events.APIGatewayProxyResponse, error) {
	return events.APIGatewayProxyResponse{StatusCode: code, Body: fmt.Sprintf(`{"error":"%s"}`, msg), Headers: map[string]string{"Content-Type": "application/json"}}, nil
}
func serverError(err error) (events.APIGatewayProxyResponse, error) {
	fmt.Println("ERR:", err)
	return events.APIGatewayProxyResponse{StatusCode: 500, Body: `{"error":"internal"}`, Headers: map[string]string{"Content-Type": "application/json"}}, nil
}
