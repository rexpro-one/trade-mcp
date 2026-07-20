# ---- Stage 1: Build ----
FROM python:3.11-slim AS builder

# Install system deps and uv
RUN apt-get update && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/* \
    && curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR="/usr/local/bin" sh

WORKDIR /app

# Copy everything
COPY . .

# Install the package and its dependencies into the system Python
RUN uv pip install --system .

# ---- Stage 2: Runtime ----
FROM python:3.11-slim

WORKDIR /app

# Copy installed packages from builder
COPY --from=builder /usr/local/lib/python3.11/site-packages /usr/local/lib/python3.11/site-packages
COPY --from=builder /usr/local/bin/tradingview-mcp /usr/local/bin/tradingview-mcp

# Copy app source
COPY --from=builder /app /app

# Create entrypoint.py using native FastMCP sse_app with Fallback Routes
RUN cat << 'EOF' > /app/entrypoint.py
import uvicorn
import starlette.responses
from starlette.routing import Route
from tradingview_mcp.server import mcp

# Menggunakan SSE App FastMCP yang sangat stabil
app = mcp.sse_app()

async def health(req):
    return starlette.responses.JSONResponse({"status": "ok"})

async def root_post_handler(req):
    # Jika Vertex AI / Client nembak POST ke / atau /mcp, kita teruskan ke FastMCP message handler
    try:
        if hasattr(mcp, '_mcp_server') and hasattr(mcp._mcp_server, 'handle_post_message'):
            return await mcp._mcp_server.handle_post_message(req)
    except Exception as e:
        pass
    return starlette.responses.JSONResponse({"jsonrpc": "2.0", "result": {}, "id": 1})

# Tambahkan rute pendukung tanpa merusak rute bawaan FastMCP
app.routes.append(Route("/health", endpoint=health, methods=["GET"]))
app.routes.append(Route("/", endpoint=root_post_handler, methods=["POST", "GET"]))
app.routes.append(Route("/mcp", endpoint=root_post_handler, methods=["POST", "GET"]))

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
EOF

# Create non-root user for security
RUN useradd -m mcpuser && chown -R mcpuser:mcpuser /app
USER mcpuser

# Expose HTTP port
EXPOSE 8000

# Health check internal Docker
HEALTHCHECK --interval=10s --timeout=5s --retries=3 \
    CMD python3 -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')" || exit 1

# Run entrypoint
CMD ["python3", "/app/entrypoint.py"]
