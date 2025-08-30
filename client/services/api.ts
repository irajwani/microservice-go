export interface AccountEntry {
  currency: string;
  balance: number;
}

export interface AccountsResponse {
  user_id: string;
  accounts: AccountEntry[];
  [k: string]: unknown;
}

const apiGatewayId = process.env.API_GATEWAY_ID;
const base = process.env.API_BASE_URL || "http://localhost:4566";

if (!apiGatewayId) {
  // Intentionally not throwing; caller can decide fallback.
  console.warn("API_GATEWAY_ID is not set in environment");
}

// Construct base URL for REST API (assuming 'dev' stage)
const stage = "dev";
const root = `${base}/restapis/${apiGatewayId}/${stage}/_user_request_`;

async function http<T>(path: string, init?: RequestInit): Promise<T> {
  const url = `${root}${path}`;
  const res = await fetch(url, { ...init, headers: { 'Content-Type': 'application/json', ...(init?.headers || {}) } });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`API ${res.status} ${res.statusText}: ${text}`);
  }
  return res.json() as Promise<T>;
}

export async function fetchAccounts(userId: string): Promise<AccountsResponse> {
  return http<AccountsResponse>(`/balances?user_id=${encodeURIComponent(userId)}`);
}

// --- Jobs (currency conversion) ---
export interface ConversionJobRequest {
  client_id: string;
  source_currency: string;
  target_currency: string;
  source_amount: number;
}

export interface ConversionJobResponse extends ConversionJobRequest {
  job_id: string;
  status: string; // queued | processing | completed | failed
  created_at: string;
  [k: string]: unknown;
}

export async function createConversionJob(body: ConversionJobRequest): Promise<ConversionJobResponse> {
  return http<ConversionJobResponse>(`/jobs`, { method: 'POST', body: JSON.stringify(body) });
}

// --- Transactions (Jobs History) ---
export interface Transaction {
  job_id: string;
  client_id: string;
  source_currency: string;
  target_currency: string;
  source_amount: number;
  target_amount: number;
  rate: number;
  fee: number;
  status: string;
  created_at: string;
  completed_at?: string;
}

export interface TransactionsResponse {
  user_id: string;
  jobs: Transaction[];
}

export async function fetchTransactions(userId: string, limit: number = 10): Promise<TransactionsResponse> {
  return http<TransactionsResponse>(`/jobs?user_id=${encodeURIComponent(userId)}&limit=${limit}`);
}
