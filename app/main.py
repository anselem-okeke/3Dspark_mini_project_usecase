from pathlib import Path

from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles
from prometheus_fastapi_instrumentator import Instrumentator

app = FastAPI(title="Spark Private Cloud Demo")

Instrumentator(
    should_group_status_codes=True,
    should_ignore_untemplated=True,
    excluded_handlers=["/metrics", "/health"],
).instrument(app).expose(app, endpoint="/metrics")

@app.get("/health")
def health():
    return {"ok": "ok"}

STATIC_DIR = Path(__file__).resolve().parent / "static"

# Mount, to allow /health and /metrics
app.mount("/", StaticFiles(directory=STATIC_DIR, html=True), name="site")

