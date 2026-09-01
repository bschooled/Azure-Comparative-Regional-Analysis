from __future__ import annotations

import azure.functions as func

from handlers import scheduled_refresh_main


def main(timer: func.TimerRequest) -> None:
    scheduled_refresh_main(timer)