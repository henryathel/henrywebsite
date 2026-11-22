"""POST /api/auth/request: email a six-digit sign-in code.

Every outcome except a malformed address gets the same redirect, so the endpoint can't be
used to find out which addresses have signed in before or have been rate-limited.
"""

import logging
import time
from typing import Any

from botocore.exceptions import ClientError
from pydantic import ValidationError

from auth.codes import code_hash, email_id, new_code
from auth.config import settings
from auth.http import (
    Event,
    Response,
    code_page,
    forbidden,
    form_fields,
    from_cloudfront,
    redirect,
    viewer_ip,
)
from auth.mailer import send_code
from auth.models import SignInRequest
from auth.store import allow, save_code

logger = logging.getLogger(__name__)

INVALID_PAGE = "/login.html?invalid=1"

HOUR = 3600
EMAIL_LIMIT = 3  # codes per address per hour
IP_LIMIT = 10  # requests per address (or IPv6 /64) per hour


def handler(event: Event, context: Any) -> Response:  # noqa: ANN401
    config = settings()
    if not from_cloudfront(event, config.origin_secret):
        logger.warning("request did not come through CloudFront")
        return forbidden()

    try:
        request = SignInRequest.model_validate(form_fields(event))
    except (ValidationError, ValueError):
        return redirect(INVALID_PAGE)

    now = int(time.time())
    who = email_id(request.email)
    ip = viewer_ip(event)

    if not allow(f"ip#{ip}", IP_LIMIT, HOUR, now) or not allow(
        f"email#{who}", EMAIL_LIMIT, HOUR, now
    ):
        logger.warning("rate limited", extra={"email_id": who, "ip": ip})
        return redirect(code_page(request.email))

    code = new_code()
    save_code(request.email, code_hash(request.email, code), now + config.code_ttl_seconds)
    try:
        send_code(request.email, code)
    except ClientError:
        # Still the generic response; the log is where a sending problem shows up.
        logger.exception("failed to send sign-in code", extra={"email_id": who})
    else:
        logger.info("sign-in code sent", extra={"email_id": who})
    return redirect(code_page(request.email))
