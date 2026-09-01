from __future__ import annotations

import azure.functions as func

from handlers import pricing_status_main


def main(req: func.HttpRequest) -> func.HttpResponse:
    return pricing_status_main(req)