import { NextRequest } from "next/server";
import { createConversionJob } from "@/services/api";

export async function POST(req: NextRequest) {
  try {
    const json = await req.json();
    const job = await createConversionJob(json);
    return Response.json(job, { status: 200 });
  } catch (err) {
    const message = err instanceof Error ? err.message : 'Unknown error';
    return Response.json({ error: message }, { status: 400 });
  }
}
