"use client";
import { useRouter } from "next/navigation";
import { ArrowLeft, ArrowDown } from "lucide-react";
import { Button } from "@/components/ui/button";
import { useState, useEffect, useCallback } from "react";
import { Loader2, AlertCircle } from "lucide-react";

// Simple currency symbol map (match home page style)
const currencySymbols: Record<string, string> = { USD: "$", EUR: "€", GBP: "£", CAD: "$", JPY: "¥" };

interface AccountState { currency: string; balance: number }

// Static FX rates mapping (from:to => rate)
const RATES: Record<string, number> = {
  "USD:EUR": 0.90,
  "EUR:USD": 1.16,
  "USD:GBP": 1.26,
  "GBP:USD": 0.79,
  "EUR:GBP": 1.16,
  "GBP:EUR": 0.90,
};

export default function ExchangePage() {
  const router = useRouter();
  const [accounts, setAccounts] = useState<AccountState[]>([]);
  const [accountsLoading, setAccountsLoading] = useState(false);
  const [accountError, setAccountError] = useState<string | null>(null);
  const [from, setFrom] = useState<{ code: string; symbol: string; balance: number }>({ code: "USD", symbol: "$", balance: 0 });
  const [to, setTo] = useState<{ code: string; symbol: string; balance: number }>({ code: "EUR", symbol: "€", balance: 0 });
  const [rate, setRate] = useState<number>(() => RATES["USD:EUR"]);
  const [amount, setAmount] = useState<string>("100"); // from amount (no symbol)
  const [flipped, setFlipped] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [submitError, setSubmitError] = useState<string | null>(null);
  const [jobId, setJobId] = useState<string | null>(null);
  // jobId indicates a successful submission already queued

  const parsed = parseFloat(amount || "0") || 0;
  const toAmount = parsed * rate;

  const formatNumber = (n: number, maxDecimals = 6) => {
    if (!isFinite(n)) return "0";
    const fixed = n.toFixed(maxDecimals);
    return fixed.replace(/\.?(0+)$/, "");
  };

  const recomputeRate = useCallback((fromCode: string, toCode: string) => {
    if (fromCode === toCode) return 1;
    return RATES[`${fromCode}:${toCode}`] ?? 1;
  }, []);

  const swap = () => {
    // Pre-calc new state
    const nextFrom = to;
    const nextTo = from;
    setFrom(nextFrom);
    setTo(nextTo);
    setRate(recomputeRate(nextFrom.code, nextTo.code));
    if (!isNaN(toAmount) && toAmount > 0) {
      const next = formatNumber(toAmount, 6);
      setAmount(next);
    }
    setFlipped(f => !f);
  };

  // Load accounts similar to home page
  useEffect(() => {
    const loadAccounts = async () => {
      setAccountsLoading(true);
      setAccountError(null);
      try {
        const res = await fetch(`/api/balance?user_id=c1`);
        if (!res.ok) throw new Error(await res.text());
        const data = await res.json();
        if (Array.isArray(data.accounts)) {
          const loaded: AccountState[] = data.accounts.map((a: { currency: string; balance: number }) => ({ currency: a.currency, balance: a.balance }));
          setAccounts(loaded);
          // Pick initial from (USD if present else first) and to (EUR if present else second else same)
          const usd = loaded.find(a => a.currency === 'USD') || loaded[0];
            // Ensure distinct 'to'
          const eur = loaded.find(a => a.currency === 'EUR' && a.currency !== usd?.currency) || loaded.find(a => a.currency !== usd?.currency) || loaded[1] || loaded[0];
          if (usd) setFrom({ code: usd.currency, symbol: currencySymbols[usd.currency] || usd.currency, balance: usd.balance });
          if (eur) setTo({ code: eur.currency, symbol: currencySymbols[eur.currency] || eur.currency, balance: eur.balance });
          if (usd && eur) setRate(recomputeRate(usd.currency, eur.currency));
        } else {
          setAccountError('Malformed response');
        }
      } catch (e) {
        setAccountError(e instanceof Error ? e.message : 'Failed to load accounts');
      } finally {
        setAccountsLoading(false);
      }
    };
    loadAccounts();
  }, [recomputeRate]);

  // Keep balances in sync if accounts array updates (e.g., refresh)
  useEffect(() => {
    if (!accounts.length) return;
    const f = accounts.find(a => a.currency === from.code);
    const t = accounts.find(a => a.currency === to.code);
    if (f && (f.balance !== from.balance)) {
      setFrom(prev => ({ ...prev, balance: f.balance, symbol: currencySymbols[f.currency] || f.currency }));
    }
    if (t && (t.balance !== to.balance)) {
      setTo(prev => ({ ...prev, balance: t.balance, symbol: currencySymbols[t.currency] || t.currency }));
    }
  }, [accounts, from.code, to.code, from.balance, to.balance]);

  const canSubmit = parsed > 0 && !submitting && !jobId;

  const handleSubmit = async () => {
    if (!canSubmit) return;
    setSubmitting(true);
    setSubmitError(null);
    setJobId(null);
  // no queued UI text variant; we keep button label but disable after submit
    try {
      const body = {
        client_id: 'c1',
        source_currency: from.code,
        target_currency: to.code,
        source_amount: parsed,
      };
      const res = await fetch('/api/jobs', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
      if (!res.ok) {
        const txt = await res.text();
        throw new Error(txt);
      }
      const data = await res.json();
      setJobId(data.job_id);
      // Wait 5 seconds before navigating back to home page and reloading balances and transactions
      setTimeout(() => {
        router.push("/");
        // Trigger a page refresh to reload balances and transactions
        window.location.reload();
      }, 7000);
    } catch (e) {
      setSubmitError(e instanceof Error ? e.message : 'Failed to submit job');
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <div className="min-h-screen w-full flex flex-col relative pb-12">
        {/* Top bar */}
        <div className="flex items-center justify-between px-6 pt-8 pb-4">
            <button onClick={() => router.back()} className="flex items-center gap-1 text-sm font-medium hover:opacity-80">
            <ArrowLeft className="w-4 h-4" /> Back
            </button>
            <h1 className="text-lg font-semibold">Sell {from.code}</h1>
            <div className="w-10" />
        </div>

        {/* Rate banner */}
        <div className="px-6 mb-6">
            <div className="inline-flex items-center gap-2 px-3 py-1.5 text-xs font-medium bg-glass-primary text-accent shadow-glass-border shadow">
            <span>Rate</span>
            <span className="font-mono">{from.symbol}1 = {to.symbol}{rate.toFixed(4)}</span>
            </div>
        </div>



        {/* From currency panel */}
        <div className="flex-1 flex flex-col items-center px-4 w-full">
          {/* From + To Panels Wrapper */}
          <div className="w-full max-w-sm relative mt-2 grid gap-2">
            {/* From Panel */}
            <div className="glass-card p-6 rounded-xl">
            <div className="flex items-start justify-between">
              <span className="text-2xl font-semibold tracking-wide select-none">{from.code}</span>
              <input
                type="text"
                inputMode="decimal"
                autoComplete="off"
                className="w-44 bg-transparent text-2xl font-light text-right outline-none focus:ring-0 placeholder:text-muted-foreground/40"
                value={amount ? `-${from.symbol}${amount}` : ""}
                onChange={(e) => {
                  const v = e.target.value
                    .replace(/[^0-9.]/g, "")
                    .replace(/(\.)(?=.*\.)/g, "");
                  setAmount(v);
                }}
                placeholder={`-${from.symbol}0`}
              />
            </div>
              <div className="mt-3">
                <span className="text-xs text-muted-foreground">Balance: {from.symbol}{from.balance.toFixed(2)}{accountsLoading && ' …'}</span>
                {accountError && <span className="block text-xs text-red-500 mt-0.5">{accountError}</span>}
              </div>
            </div>
            {/* To Panel */}
            <div className="glass-tertiary p-6 rounded-xl border border-border/60 relative">
              <div className="flex items-start justify-between">
                <span className="text-xl font-semibold tracking-wide select-none">{to.code}</span>
                <span className="text-2xl font-light text-right min-w-[7rem]">+{to.symbol}{toAmount ? formatNumber(toAmount, 6) : "0"}</span>
              </div>
              <div className="mt-3">
                <span className="text-xs text-muted-foreground">Balance: {to.symbol}{to.balance.toFixed(2)}{accountsLoading && ' …'}</span>
              </div>
            </div>
            {/* Overlapping swap icon centered between panels using absolute + translate */}
            <button
              type="button"
              onClick={swap}
              className={`absolute left-1/2 top-1/2 -translate-x-1/2 -translate-y-1/2 z-30 grid place-items-center w-14 h-14 rounded-full bg-background/80 dark:bg-gray-900/80 border border-border shadow-md hover:shadow-lg backdrop-blur-sm transition-all duration-500 ease-out ${flipped ? 'rotate-180' : 'rotate-0'}`}
              aria-label="Swap currencies"
            >
              <ArrowDown className="w-6 h-6 transition-transform duration-500" />
            </button>
          </div>
          {/* Action Button inside same logical section */}
          <div className="mt-32 space-y-3 w-full max-w-sm">
            {submitError && (
              <div className="flex items-center gap-2 text-sm text-red-600 bg-red-50/70 dark:bg-red-900/30 border border-red-300/50 dark:border-red-800/50 px-3 py-2 rounded-md">
                <AlertCircle className="w-4 h-4" />
                <span className="line-clamp-2">{submitError}</span>
              </div>
            )}
            {jobId && !submitError && (
              <div className="flex items-center justify-between text-xs text-muted-foreground px-1">
                <span className="truncate">Job: {jobId}</span>
                {submitting && <Loader2 className="w-4 h-4 animate-spin" />}
              </div>
            )}
            <Button
              onClick={handleSubmit}
              disabled={!canSubmit}
              className="w-full h-12 text-base font-medium relative bg-accent hover:bg-green-600 text-white border-green-500 hover:border-green-600 disabled:bg-green-300 disabled:border-green-300"
            >
              {submitting && <Loader2 className="w-5 h-5 animate-spin absolute left-4" />}
              Verify order
            </Button>
          </div>
        </div>
    </div>
  );
}
