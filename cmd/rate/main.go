package main

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"strconv"
	"strings"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
)

// RateResponse represents FX rate and fee information
// fee_bps = fee percent in basis points (25 => 0.25%)
type RateResponse struct {
	Source   string  `json:"source"`
	Target   string  `json:"target"`
	Rate     float64 `json:"rate"`
	FeeBps   int     `json:"fee_bps"`
	Provider string  `json:"provider"`
}

var defaultRates = map[string]RateResponse{
	// Aligned with client static mapping (intentionally not strict inverses):
	//  USD:EUR 0.90  EUR:USD 1.16  USD:GBP 1.26  GBP:USD 0.79  EUR:GBP 1.16  GBP:EUR 0.90
	"USD:EUR": {Source: "USD", Target: "EUR", Rate: 0.90, FeeBps: 30, Provider: "mock-fx"},
	"EUR:USD": {Source: "EUR", Target: "USD", Rate: 1.16, FeeBps: 30, Provider: "mock-fx"},
	"USD:GBP": {Source: "USD", Target: "GBP", Rate: 1.26, FeeBps: 30, Provider: "mock-fx"},
	"GBP:USD": {Source: "GBP", Target: "USD", Rate: 0.79, FeeBps: 30, Provider: "mock-fx"},
	"EUR:GBP": {Source: "EUR", Target: "GBP", Rate: 1.16, FeeBps: 30, Provider: "mock-fx"},
	"GBP:EUR": {Source: "GBP", Target: "EUR", Rate: 0.90, FeeBps: 30, Provider: "mock-fx"},
}

func handler(ctx context.Context, req events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {
	// Expect query params source, target OR override via body {source,target}
	source := strings.ToUpper(req.QueryStringParameters["source"])
	target := strings.ToUpper(req.QueryStringParameters["target"])
	if source == "" || target == "" {
		// Allow JSON body fallback
		var body struct{ Source, Target string }
		if req.Body != "" {
			_ = json.Unmarshal([]byte(req.Body), &body)
			if body.Source != "" {
				source = strings.ToUpper(body.Source)
			}
			if body.Target != "" {
				target = strings.ToUpper(body.Target)
			}
		}
	}
	if len(source) != 3 || len(target) != 3 {
		return clientError(400, "source/target must be 3-letter codes")
	}
	key := source + ":" + target
	resp, ok := defaultRates[key]
	if !ok {
		// Allow STATIC_RATE and STATIC_FEE_BPS env override for unknown pair
		if rStr := os.Getenv("STATIC_RATE"); rStr != "" {
			if r, err := strconv.ParseFloat(rStr, 64); err == nil {
				feeBps := 25
				if fStr := os.Getenv("STATIC_FEE_BPS"); fStr != "" {
					if f, err2 := strconv.Atoi(fStr); err2 == nil {
						feeBps = f
					}
				}
				resp = RateResponse{Source: source, Target: target, Rate: r, FeeBps: feeBps, Provider: "env-mock"}
				ok = true
			}
		}
	}
	if !ok {
		return clientError(404, "rate not found")
	}
	b, _ := json.Marshal(resp)
	return events.APIGatewayProxyResponse{StatusCode: 200, Body: string(b), Headers: map[string]string{"Content-Type": "application/json"}}, nil
}

func main() { lambda.Start(handler) }

func clientError(code int, msg string) (events.APIGatewayProxyResponse, error) {
	return events.APIGatewayProxyResponse{StatusCode: code, Body: fmt.Sprintf(`{"error":"%s"}`, msg), Headers: map[string]string{"Content-Type": "application/json"}}, nil
}

// For potential direct (non-APIGW) invocation we can add a simple entrypoint
// by defining another handler that accepts a custom event; omitted for brevity.
