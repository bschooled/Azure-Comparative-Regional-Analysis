from __future__ import annotations

import azure.functions as func

from handlers import health_check_main


def main(req: func.HttpRequest) -> func.HttpResponse:
    return health_check_main(req)