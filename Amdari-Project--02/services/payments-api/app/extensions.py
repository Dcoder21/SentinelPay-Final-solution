"""Shared Flask extensions."""

import os

from urllib.parse import quote

from flask_limiter import Limiter
from flask_limiter.util import get_remote_address


# ============================================================================
# V-APP-08: SINGLE SHARED RATE-LIMITER
# ============================================================================
#
# FUNCTIONALITY:
# This module owns the application's one Flask-Limiter instance.
#
# REMEDIATION:
# Keeping a single extension prevents route modules from accidentally creating
# independent limiter instances that are never attached to the served Flask
# application.
limiter = Limiter(
    key_func=get_remote_address,
    storage_uri=os.getenv(
        "RATELIMIT_STORAGE_URI",
        (f"rediss://:{quote(os.environ['REDIS_AUTH_TOKEN'], safe='')}@{os.environ['REDIS_HOST']}:6379/2?ssl_cert_reqs=required"
         if os.environ.get("REDIS_HOST") else "redis://redis:6379/2"),
    ),
)