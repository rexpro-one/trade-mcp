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

# Create custom entrypoint script to add /health route dynamically
RUN echo 'import uvicorn \n\
import starlette.responses \n\
from starlette.routing import Route \n\
from tradingview_mcp.server import mcp \n\
\n\
app = mcp.sse_app() \n\
async def health(req): \n\
    return starlette.responses.JSONResponse({"status": "ok"}) \n\
app.routes.append(Route("/health", endpoint=health)) \n\
\n\
if __name__ == "__main__": \n\
    uvicorn.run(app, host="0.0.0.0", port=8000) \n\
' > /app/entrypoint.py

# Create non-root user for security
RUN useradd -m mcpuser && chown -R mcpuser:mcpuser /app
USER mcpuser

# Expose the HTTP/SSE port
EXPOSE 8000

# Health check
HEALTHCHECK --interval=10s --timeout=5s --retries=3 \
    CMD python3 -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')" || exit 1

# Run the entrypoint
CMD ["python3", "/app/entrypoint.py"]
