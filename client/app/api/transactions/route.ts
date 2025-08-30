import { NextRequest } from "next/server";
import { fetchTransactions } from "@/services/api";

// Simple proxy route so the client doesn't need direct API Gateway details
export async function GET(req: NextRequest) {
  const { searchParams } = new URL(req.url);
  const userId = searchParams.get("user_id") || "c1";
  const limit = parseInt(searchParams.get("limit") || "10");
  
  try {
    const data = await fetchTransactions(userId, limit);
    return Response.json(data, { status: 200 });
  } catch (err) {
    const message = err instanceof Error ? err.message : "Unknown error";
    return Response.json({ error: message }, { status: 500 });
  }
}
