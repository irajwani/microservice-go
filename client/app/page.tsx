"use client";

import { useState, useEffect } from "react";
import { useRouter } from "next/navigation";
import Image from "next/image";
import { Button } from "@/components/ui/button";
import { Sheet, SheetContent, SheetHeader, SheetTitle, SheetDescription } from "@/components/ui/sheet";
import { Plus, ArrowLeftRight, MoreHorizontal, Home as HomeIcon, Repeat2, Layers, ChevronDown } from "lucide-react";
import { Transaction } from "@/services/api";

// Mocked actions configuration (would come from API or config later)
const actions = [
  { label: "Add money", icon: Plus, color: "text-blue-600", bg: "bg-blue-100 dark:bg-blue-900" },
  { label: "Exchange", icon: ArrowLeftRight, color: "text-green-600", bg: "bg-green-100 dark:bg-green-900" },
  { label: "More", icon: MoreHorizontal, color: "text-gray-600", bg: "bg-gray-100 dark:bg-gray-800" }
];

const bottomNav = [
  { key: "Home", label: "Home", icon: HomeIcon },
  { key: "Transfer", label: "Transfer", icon: Repeat2 },
  { key: "Hub", label: "Hub", icon: Layers }
];

// Map a few common currency codes to symbols (fallback to code)
const currencySymbols: Record<string, string> = { GBP: "£", EUR: "€", USD: "$", CAD: "$", JPY: "¥" };
const currencyFlags: Record<string, string> = { GBP: "🇬🇧", EUR: "🇪🇺", USD: "🇺🇸", CAD: "🇨🇦", JPY: "🇯🇵" };

interface AccountState {
  currency: string;
  balance: number;
}

export default function Home() {
  const [activeNav, setActiveNav] = useState<string>("Home");
  const router = useRouter();
  const [accounts, setAccounts] = useState<AccountState[]>([]);
  const [accountError, setAccountError] = useState<string | null>(null);
  const [accountsLoading, setAccountsLoading] = useState<boolean>(false);
  const [selectedIndex, setSelectedIndex] = useState(0);
  const [showAccountSheet, setShowAccountSheet] = useState(false);
  const [transactions, setTransactions] = useState<Transaction[]>([]);
  const [transactionsLoading, setTransactionsLoading] = useState<boolean>(false);
  const [transactionsError, setTransactionsError] = useState<string | null>(null);

  const loadData = async () => {
    const controller = new AbortController();
    
    // Load accounts
    setAccountsLoading(true);
    setAccountError(null);
    try {
      const res = await fetch(`/api/balance?user_id=c1`, { signal: controller.signal });
      if (!res.ok) throw new Error(await res.text());
      const data = await res.json();
      if (Array.isArray(data.accounts)) {
        setAccounts(data.accounts.map((a: { currency: string; balance: number }) => ({ currency: a.currency, balance: a.balance })));
        setSelectedIndex(0);
      } else {
        setAccountError('Malformed response');
      }
    } catch (e: unknown) {
      if (e instanceof DOMException && e.name === 'AbortError') return;
      if (e instanceof Error) {
        setAccountError(e.message);
      } else {
        setAccountError('Failed to load accounts');
      }
    } finally {
      setAccountsLoading(false);
    }

    // Load transactions
    setTransactionsLoading(true);
    setTransactionsError(null);
    try {
      const res = await fetch(`/api/transactions?user_id=c1&limit=10`, { signal: controller.signal });
      if (!res.ok) throw new Error(await res.text());
      const transactionsData = await res.json();
      setTransactions(transactionsData.jobs);
    } catch (e: unknown) {
      if (e instanceof DOMException && e.name === 'AbortError') return;
      if (e instanceof Error) {
        setTransactionsError(e.message);
      } else {
        setTransactionsError('Failed to load transactions');
      }
    } finally {
      setTransactionsLoading(false);
    }
  };

  useEffect(() => {
    loadData();
    
    // Make loadData available globally for refresh from other pages
    (window as Window & { refreshHomeData?: () => Promise<void> }).refreshHomeData = loadData;
    
    return () => {
      delete (window as Window & { refreshHomeData?: () => Promise<void> }).refreshHomeData;
    };
  }, []);

  return (
  <div className="min-h-screen">
        {/* Header */}
        <div className="flex items-center justify-between px-6 py-4">
          <div className="w-8 h-8 rounded-full overflow-hidden relative">
            <Image
              src="https://images.unsplash.com/photo-1438761681033-6461ffad8d80?w=64&h=64&fit=crop&crop=face"
              alt="Female user avatar"
              fill
              sizes="32px"
              className="object-cover"
            />
          </div>
          <h1 className="text-lg font-semibold">Home</h1>
          <div className="w-6 h-6">
            <svg fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z" />
            </svg>
          </div>
        </div>

        {/* Navigation Tabs */}
        <div className="flex px-6 mb-6 overflow-x-auto scrollbar-hide pt-2">
          <div className="flex space-x-6 text-sm min-w-max">
            <button className="font-semibold text-foreground border-b-2 border-foreground pb-2">Accounts</button>
            <button className="text-muted-foreground">Cards</button>
            <button className="text-muted-foreground">Linked</button>
            <button className="text-muted-foreground relative">
              Vaults
              <span className="absolute -top-1 -right-2 w-2 h-2 bg-red-500 rounded-full"></span>
            </button>
          </div>
        </div>

        {/* Balance Section */}
        <div className="px-6 mb-8">
          <div className="glass-card p-6 mb-4">
            <div className="flex items-center justify-between mb-4">
              <div className="relative">
                <button
                  type="button"
                  className="flex items-center gap-2 h-12 pr-4 pl-0 cursor-pointer select-none group"
                  onClick={() => setShowAccountSheet(true)}
                >
                  {accountsLoading && (
                    <span className="text-xl font-light animate-pulse text-muted-foreground">Loading…</span>
                  )}
                  {!accountsLoading && accounts.length > 0 && (
                    <>
                      <span className="text-3xl font-light leading-none group-hover:opacity-90 transition-opacity">
                        {currencySymbols[accounts[selectedIndex].currency] || accounts[selectedIndex].currency}
                        {accounts[selectedIndex].balance.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}
                      </span>
                      <ChevronDown className="w-4 h-4 text-muted-foreground" />
                    </>
                  )}
                  {!accountsLoading && accounts.length === 0 && !accountError && (
                    <span className="text-xl font-light text-muted-foreground">—</span>
                  )}
                  {!accountsLoading && accountError && (
                    <span className="text-sm text-red-500" title={accountError}>Failed</span>
                  )}
                </button>
                <p className="text-sm text-muted-foreground mt-1">{accounts[selectedIndex]?.currency || 'Account'}</p>
              </div>
              <div className="w-12 h-12 flex items-center justify-center">
                <span className="text-3xl md:text-[2.2rem] leading-none">{currencyFlags[accounts[selectedIndex]?.currency ?? ""] || '🏳️'}</span>
              </div>
            </div>
          

            {/* Action Buttons */}
            <div className="grid grid-cols-3 gap-4">
              {actions.map(({ label, icon: Icon, color, bg }) => (
                <Button
                  key={label}
                  variant="outline"
                  className="glass-button flex-col h-16 gap-1"
                  onClick={() => {
                    if (label === "Exchange") router.push("/exchange");
                  }}
                >
                  <div className={`w-6 h-6 rounded-full flex items-center justify-center ${bg}`}>
                    <Icon className={`w-4 h-4 ${color}`} />
                  </div>
                  <span className="text-xs">{label}</span>
                </Button>
              ))}
            </div>
          
            {/* Transactions Section */}
            <div className="flex items-center justify-between mt-4">
              <p className="text-sm text-muted-foreground">Transactions</p>
            </div>
            <div className="space-y-3 max-h-96 overflow-y-auto scrollbar-hide pr-2">
              {transactionsLoading && (
                <div className="p-4 text-center">
                  <span className="text-sm text-muted-foreground animate-pulse">Loading transactions...</span>
                </div>
              )}
              {transactionsError && (
                <div className="p-4 text-center">
                  <span className="text-sm text-red-500">Failed to load transactions</span>
                </div>
              )}
              {!transactionsLoading && !transactionsError && transactions.length === 0 && (
                <div className="p-4 text-center">
                  <span className="text-sm text-muted-foreground">No transactions yet</span>
                </div>
              )}
              {!transactionsLoading && !transactionsError && transactions.map(tx => {
                const fromSymbol = currencySymbols[tx.source_currency] || tx.source_currency;
                const toSymbol = currencySymbols[tx.target_currency] || tx.target_currency;
                const date = new Date(tx.created_at).toLocaleDateString('en-US', { 
                  month: 'short', 
                  day: 'numeric',
                  hour: '2-digit',
                  minute: '2-digit'
                });
                
                return (
                  <div key={tx.job_id} className="p-4">
                    <div className="flex items-center justify-between">
                      <div className="flex items-center gap-3">
                        <div className="w-10 h-10 glass-tertiary rounded-lg flex items-center justify-center">
                          <ArrowLeftRight className="w-5 h-5" />
                        </div>
                        <div>
                          <p className="font-medium">{tx.source_currency} → {tx.target_currency} Exchange</p>
                          <p className="text-sm text-muted-foreground">{date}</p>
                          <p className="text-xs text-muted-foreground">
                            {fromSymbol}{tx.source_amount.toFixed(2)} → {toSymbol}{tx.target_amount.toFixed(2)}
                          </p>
                          <p className="text-xs text-muted-foreground">Status: {tx.status}</p>
                        </div>
                      </div>
                      <span className="text-sm font-semibold text-green-600">
                        +{toSymbol}{tx.target_amount.toFixed(2)}
                      </span>
                    </div>
                  </div>
                );
              })}
            </div>

          </div>
        </div>

        {/* Bottom Navigation */}
        <div className="fixed bottom-0 left-1/2 transform -translate-x-1/2 w-full max-w-sm sm:max-w-md md:max-w-lg lg:max-w-3xl">
          <div className="mx-4 mb-4 p-3 rounded-xl bg-muted/70 dark:bg-gray-900/70 border border-border backdrop-blur-sm">
            <div className="grid grid-cols-3 gap-2 md:gap-4">
              {bottomNav.map(item => {
                const Icon = item.icon;
                const active = activeNav === item.key;
                return (
                  <button
                    key={item.key}
                    onClick={() => setActiveNav(item.key)}
                    className="flex flex-col items-center gap-1 group"
                  >
                    <div
                      className={`w-11 h-11 rounded-xl flex items-center justify-center transition-colors border border-transparent group-hover:border-border/40 group-active:scale-95 ${
                        active ? "bg-blue-100 dark:bg-blue-900/40" : "bg-transparent"
                      }`}
                    >
                      <Icon className={`w-5 h-5 ${active ? "text-blue-600" : "text-muted-foreground group-hover:text-foreground"}`} />
                    </div>
                    <span className={`text-xs ${active ? "text-blue-600 font-medium" : "text-muted-foreground group-hover:text-foreground"}`}>{item.label}</span>
                  </button>
                );
              })}
            </div>
          </div>
        </div>
        <Sheet open={showAccountSheet} onOpenChange={setShowAccountSheet}>
          <SheetContent>
            <SheetHeader>
              <div>
                <SheetTitle>Currency accounts</SheetTitle>
              </div>
            </SheetHeader>
            <div className="p-4 space-y-2">
              {accountsLoading && <div className="text-sm text-muted-foreground animate-pulse">Loading accounts…</div>}
              {accountError && <div className="text-sm text-red-500">{accountError}</div>}
              {!accountsLoading && !accountError && accounts.map((a, i) => (
                <button
                  key={a.currency}
                  className={`w-full flex items-center justify-between px-4 py-3 rounded-md border text-left transition-colors hover:bg-accent/40 ${i === selectedIndex ? 'bg-accent/20 border-accent' : ''}`}
                  onClick={() => { setSelectedIndex(i); setShowAccountSheet(false); }}
                >
                  <span className="flex items-center gap-2"><span className="text-xl leading-none">{currencyFlags[a.currency] || '🏳️'}</span>{a.currency}</span>
                  <span className="tabular-nums text-sm font-medium">{(currencySymbols[a.currency] || '')}{a.balance.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}</span>
                </button>
              ))}
              {!accountsLoading && !accountError && accounts.length <= 1 && (
                <p className="text-xs text-muted-foreground">Only one account available.</p>
              )}
            </div>
          </SheetContent>
        </Sheet>
    </div>
  );
}
