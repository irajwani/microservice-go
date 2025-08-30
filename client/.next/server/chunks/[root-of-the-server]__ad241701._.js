module.exports = [
"[project]/systems/evolut/.next-internal/server/app/api/jobs/route/actions.js [app-rsc] (server actions loader, ecmascript)", ((__turbopack_context__, module, exports) => {

}),
"[externals]/next/dist/compiled/next-server/app-route-turbo.runtime.dev.js [external] (next/dist/compiled/next-server/app-route-turbo.runtime.dev.js, cjs)", ((__turbopack_context__, module, exports) => {

const mod = __turbopack_context__.x("next/dist/compiled/next-server/app-route-turbo.runtime.dev.js", () => require("next/dist/compiled/next-server/app-route-turbo.runtime.dev.js"));

module.exports = mod;
}),
"[externals]/next/dist/compiled/@opentelemetry/api [external] (next/dist/compiled/@opentelemetry/api, cjs)", ((__turbopack_context__, module, exports) => {

const mod = __turbopack_context__.x("next/dist/compiled/@opentelemetry/api", () => require("next/dist/compiled/@opentelemetry/api"));

module.exports = mod;
}),
"[externals]/next/dist/compiled/next-server/app-page-turbo.runtime.dev.js [external] (next/dist/compiled/next-server/app-page-turbo.runtime.dev.js, cjs)", ((__turbopack_context__, module, exports) => {

const mod = __turbopack_context__.x("next/dist/compiled/next-server/app-page-turbo.runtime.dev.js", () => require("next/dist/compiled/next-server/app-page-turbo.runtime.dev.js"));

module.exports = mod;
}),
"[externals]/next/dist/server/app-render/work-unit-async-storage.external.js [external] (next/dist/server/app-render/work-unit-async-storage.external.js, cjs)", ((__turbopack_context__, module, exports) => {

const mod = __turbopack_context__.x("next/dist/server/app-render/work-unit-async-storage.external.js", () => require("next/dist/server/app-render/work-unit-async-storage.external.js"));

module.exports = mod;
}),
"[externals]/next/dist/server/app-render/work-async-storage.external.js [external] (next/dist/server/app-render/work-async-storage.external.js, cjs)", ((__turbopack_context__, module, exports) => {

const mod = __turbopack_context__.x("next/dist/server/app-render/work-async-storage.external.js", () => require("next/dist/server/app-render/work-async-storage.external.js"));

module.exports = mod;
}),
"[externals]/next/dist/shared/lib/no-fallback-error.external.js [external] (next/dist/shared/lib/no-fallback-error.external.js, cjs)", ((__turbopack_context__, module, exports) => {

const mod = __turbopack_context__.x("next/dist/shared/lib/no-fallback-error.external.js", () => require("next/dist/shared/lib/no-fallback-error.external.js"));

module.exports = mod;
}),
"[project]/systems/evolut/services/api.ts [app-route] (ecmascript)", ((__turbopack_context__) => {
"use strict";

__turbopack_context__.s([
    "createConversionJob",
    ()=>createConversionJob,
    "fetchAccounts",
    ()=>fetchAccounts,
    "fetchTransactions",
    ()=>fetchTransactions
]);
const apiGatewayId = process.env.API_GATEWAY_ID;
const base = process.env.API_BASE_URL || "http://localhost:4566";
if (!apiGatewayId) {
    // Intentionally not throwing; caller can decide fallback.
    console.warn("API_GATEWAY_ID is not set in environment");
}
// Construct base URL for REST API (assuming 'dev' stage)
const stage = "dev";
const root = `${base}/restapis/${apiGatewayId}/${stage}/_user_request_`;
async function http(path, init) {
    const url = `${root}${path}`;
    const res = await fetch(url, {
        ...init,
        headers: {
            'Content-Type': 'application/json',
            ...init?.headers || {}
        }
    });
    if (!res.ok) {
        const text = await res.text();
        throw new Error(`API ${res.status} ${res.statusText}: ${text}`);
    }
    return res.json();
}
async function fetchAccounts(userId) {
    return http(`/balances?user_id=${encodeURIComponent(userId)}`);
}
async function createConversionJob(body) {
    return http(`/jobs`, {
        method: 'POST',
        body: JSON.stringify(body)
    });
}
async function fetchTransactions(userId, limit = 10) {
    return http(`/jobs?user_id=${encodeURIComponent(userId)}&limit=${limit}`);
}
}),
"[project]/systems/evolut/app/api/jobs/route.ts [app-route] (ecmascript)", ((__turbopack_context__) => {
"use strict";

__turbopack_context__.s([
    "POST",
    ()=>POST
]);
var __TURBOPACK__imported__module__$5b$project$5d2f$systems$2f$evolut$2f$services$2f$api$2e$ts__$5b$app$2d$route$5d$__$28$ecmascript$29$__ = __turbopack_context__.i("[project]/systems/evolut/services/api.ts [app-route] (ecmascript)");
;
async function POST(req) {
    try {
        const json = await req.json();
        const job = await (0, __TURBOPACK__imported__module__$5b$project$5d2f$systems$2f$evolut$2f$services$2f$api$2e$ts__$5b$app$2d$route$5d$__$28$ecmascript$29$__["createConversionJob"])(json);
        return Response.json(job, {
            status: 200
        });
    } catch (err) {
        const message = err instanceof Error ? err.message : 'Unknown error';
        return Response.json({
            error: message
        }, {
            status: 400
        });
    }
}
}),
];

//# sourceMappingURL=%5Broot-of-the-server%5D__ad241701._.js.map