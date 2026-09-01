from __future__ import annotations

import azure.functions as func

from handlers import manual_refresh_main


def main(req: func.HttpRequest) -> func.HttpResponse:
    return manual_refresh_main(req)