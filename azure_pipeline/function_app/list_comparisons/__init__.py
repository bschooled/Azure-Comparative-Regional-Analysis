from __future__ import annotations

import azure.functions as func

from handlers import list_comparisons_main


def main(req: func.HttpRequest) -> func.HttpResponse:
    return list_comparisons_main(req)