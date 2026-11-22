"""POST /api/auth/request: email a one-time sign-in link.

Every outcome except a malformed address gets the same redirect, so the endpoint can't be
used to find out which addresses have signed in before or have been rate-limited.
"""

import logging
import time
from typing import Any

from botocore.exceptions import ClientError
from pydantic import ValidationError

from auth.config import settings
from auth.http import Event, Response, forbidden, form_fields, from_cloudfront, redirect, viewer_ip
from auth.mailer import send_link
from auth.models import SignInRequest
from auth.store import allow, save_token
from auth.tokens import email_id, new_token, token_hash

logger = logging.getLogger(__name__)

SENT_PAGE = "/login-sent.html"
INVALID_PAGE = "/login.html?invalid=1"

HOUR = 3600
EMAIL_LIMIT = 3  # links per address per hour
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
        return redirect(SENT_PAGE)

    token = new_token()
    save_token(token_hash(token), request.email, now + config.token_ttl_seconds)
    try:
        send_link(request.email, f"{config.site_url}/api/auth/verify?token={token}")
    except ClientError:
        # Still the generic response; the log is where a sending problem shows up.
        logger.exception("failed to send sign-in link", extra={"email_id": who})
    else:
        logger.info("sign-in link sent", extra={"email_id": who})
    return redirect(SENT_PAGE)
