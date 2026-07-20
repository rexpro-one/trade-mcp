# ---- Stage 1: Build ----
FROM python:3.11-slim AS builder

RUN apt-get update && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/* \
    && curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR="/usr/local/bin" sh

WORKDIR /app
COPY . .
RUN uv pip install --system .

# ---- Stage 2: Runtime ----
FROM python:3.11-slim

WORKDIR /app

COPY --from=builder /usr/local/lib/python3.11/site-packages /usr/local/lib/python3.11/site-packages
COPY --from=builder /usr/local/bin/tradingview-mcp /usr/local/bin/tradingview-mcp
COPY --from=builder /app /app

# Clean Entrypoint script
RUN cat << 'EOF' > /app/entrypoint.py
import uvicorn
import starlette.responses
from starlette.routing import Route
from tradingview_mcp.server import mcp

# Disable strict transport/DNS host checks
if hasattr(mcp, 'settings'):
    mcp.settings.transport_security = None
if hasattr(mcp, '_settings'):
    mcp._settings.transport_security = None

app = mcp.sse_app()

async def health(req):
    return starlette.responses.JSONResponse({"status": "ok"})

async def root(req):
    return starlette.responses.JSONResponse({"status": "ok", "mcp_endpoint": "/sse"})

# Safely add supplementary routes without overriding /sse
app.routes.append(Route("/health", endpoint=health, methods=["GET"]))
app.routes.append(Route("/", endpoint=root, methods=["GET"]))

if __name__ == "__main__":
    uvicorn.run(
        app, 
        host="0.0.0.0", 
        port=8000, 
        proxy_headers=True, 
        forwarded_allow_ips="*"
    )
EOF

# Security & Permissions
RUN useradd -m mcpuser && chown -R mcpuser:mcpuser /app
USER mcpuser

EXPOSE 8000

# Health check
HEALTHCHECK --interval=10s --timeout=5s --retries=3 \
    CMD python3 -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')" || exit 1

CMD ["python3", "/app/entrypoint.py"]
