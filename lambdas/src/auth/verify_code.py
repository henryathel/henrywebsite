"""POST /api/auth/verify: exchange an email address and code for CloudFront signed cookies.

A wrong, expired, used-up or never-issued code all get the same response, so the endpoint
doesn't reveal whether someone recently requested a code for an address.
"""

import logging
import time
from typing import Any

from pydantic import ValidationError

from auth.codes import code_hash, email_id
from auth.config import required, settings
from auth.cookies import signed_cookies
from auth.http import Event, Response, code_page, forbidden, form_fields, from_cloudfront, redirect
from auth.models import VerifyRequest
from auth.store import record_visit, use_code

logger = logging.getLogger(__name__)

PROTECTED_PREFIX = "/roles/"
MAX_ATTEMPTS = 5  # guesses per code

START_AGAIN_PAGE = "/login.html?expired=1"


def handler(event: Event, context: Any) -> Response:  # noqa: ANN401
    config = settings()
    if not from_cloudfront(event, config.origin_secret):
        logger.warning("request did not come through CloudFront")
        return forbidden()

    try:
        fields = form_fields(event)
    except ValueError:
        return redirect(START_AGAIN_PAGE)
    try:
        request = VerifyRequest.model_validate(fields)
    except ValidationError:
        # A mistyped code still keeps the visitor on the code page, if the address is usable.
        email = fields.get("email", "").strip().lower()
        return redirect(code_page(email, wrong=True) if "@" in email else START_AGAIN_PAGE)

    now = int(time.time())
    who = email_id(request.email)
    if not use_code(request.email, code_hash(request.email, request.code), now, MAX_ATTEMPTS):
        logger.info("wrong, expired or used code", extra={"email_id": who})
        return redirect(code_page(request.email, wrong=True))

    record_visit(request.email, now)
    cookies = signed_cookies(
        resource=f"{config.site_url}{PROTECTED_PREFIX}*",
        expires_at=now + required(config.cookie_ttl_seconds, "COOKIE_TTL_SECONDS"),
        path=PROTECTED_PREFIX,
    )
    logger.info("signed in", extra={"email_id": who})
    return redirect(PROTECTED_PREFIX, cookies)
