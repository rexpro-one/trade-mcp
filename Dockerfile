# Entrypoint script dengan dukungan GET & POST
RUN cat << 'EOF' > /app/entrypoint.py
import uvicorn
import starlette.responses
from starlette.routing import Route
from tradingview_mcp.server import mcp

# Matikan proteksi strict host DNS jika ada
if hasattr(mcp, 'settings'):
    mcp.settings.transport_security = None
if hasattr(mcp, '_settings'):
    mcp._settings.transport_security = None

app = mcp.sse_app()

async def health(req):
    return starlette.responses.JSONResponse({"status": "ok"})

# Handler fallback jika Vertex AI mengirim POST langsung
async def handle_post_fallback(req):
    return starlette.responses.JSONResponse({
        "jsonrpc": "2.0",
        "error": {
            "code": -32600,
            "message": "Endpoint ini membutuhkan koneksi HTTP GET SSE. Untuk pesan JSON-RPC, gunakan URL session dari event SSE."
        },
        "id": None
    }, status_code=200)

app.routes.append(Route("/health", endpoint=health, methods=["GET"]))
app.routes.append(Route("/sse", endpoint=handle_post_fallback, methods=["POST"]))

if __name__ == "__main__":
    uvicorn.run(
        app, 
        host="0.0.0.0", 
        port=8000, 
        proxy_headers=True, 
        forwarded_allow_ips="*"
    )
EOF
