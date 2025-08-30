import { NextRequest } from "next/server";
import { fetchAccounts } from "@/services/api";

// Simple proxy route so the client doesn't need direct API Gateway details
export async function GET(req: NextRequest) {
  const { searchParams } = new URL(req.url);
  const userId = searchParams.get("user_id") || "c1";
  try {
  const data = await fetchAccounts(userId);
    return Response.json(data, { status: 200 });
  } catch (err) {
    const message = err instanceof Error ? err.message : "Unknown error";
    return Response.json({ error: message }, { status: 500 });
  }
}
