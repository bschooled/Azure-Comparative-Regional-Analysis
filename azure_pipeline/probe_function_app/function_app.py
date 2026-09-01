from __future__ import annotations

import json

import azure.functions as func


app = func.FunctionApp(http_auth_level=func.AuthLevel.ANONYMOUS)


@app.function_name(name='probe_health')
@app.route(route='health', methods=['GET'], auth_level=func.AuthLevel.ANONYMOUS)
def probe_health(_: func.HttpRequest) -> func.HttpResponse:
    return func.HttpResponse(
        json.dumps({'status': 'ok', 'app': 'probe'}),
        mimetype='application/json',
        status_code=200,
    )