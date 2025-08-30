"use client";
import * as React from "react";
import { createPortal } from "react-dom";
import { cn } from "@/lib/utils";

interface SheetProps {
  open: boolean;
  onOpenChange?: (open: boolean) => void;
  children: React.ReactNode;
}

const Sheet = ({ open, onOpenChange, children }: SheetProps) => {
  const [mounted, setMounted] = React.useState(false);
  React.useEffect(() => { setMounted(true); }, []);

  React.useEffect(() => {
    if (!mounted) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape' && open) onOpenChange?.(false);
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [open, onOpenChange, mounted]);

  // Avoid SSR mismatch: render nothing until mounted; render portal only when open (or keep for exit animation optionally)
  if (!mounted) return null;
  if (typeof document === 'undefined') return null;
  if (!open) return null; // simplify: no hidden skeleton in SSR output

  return createPortal(
    <div className="fixed inset-0 z-50 flex pointer-events-auto" aria-hidden={false}>
      <div
        className="absolute inset-0 bg-background/60 dark:bg-black/70 backdrop-blur-sm opacity-100"
        onClick={() => onOpenChange?.(false)}
      />
      <div
        className="ml-auto h-full w-full sm:max-w-md bg-card border-l flex flex-col shadow-xl translate-x-0 animate-in slide-in-from-right duration-300"
        role="dialog"
        aria-modal="true"
      >
        {children}
      </div>
    </div>,
    document.body
  );
};

const SheetHeader = ({ className, children }: { className?: string; children?: React.ReactNode }) => (
  <div className={cn("px-6 py-4 border-b flex items-center justify-between", className)}>{children}</div>
);
const SheetTitle = ({ className, children }: { className?: string; children?: React.ReactNode }) => (
  <h2 className={cn("text-lg font-semibold leading-none", className)}>{children}</h2>
);
const SheetDescription = ({ className, children }: { className?: string; children?: React.ReactNode }) => (
  <p className={cn("text-sm text-muted-foreground", className)}>{children}</p>
);
const SheetContent = ({ className, children }: { className?: string; children?: React.ReactNode }) => (
  <div className={cn("flex-1 overflow-y-auto", className)}>{children}</div>
);

export { Sheet, SheetContent, SheetHeader, SheetTitle, SheetDescription };
