from __future__ import annotations

import azure.functions as func

from handlers import pricing_hydrate_main


def main(req: func.HttpRequest) -> func.HttpResponse:
    return pricing_hydrate_main(req)