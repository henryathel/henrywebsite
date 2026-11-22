"""/api/auth/verify: exchange a one-time token for CloudFront signed cookies.

GET only shows a confirmation page; the token is consumed by the POST its button sends.
Corporate mail filters often fetch every link in an email before the recipient sees it,
which would use up a single-use link if GET consumed it.
"""

import html
import logging
import time
from typing import Any

from pydantic import ValidationError

from auth.config import required, settings
from auth.cookies import signed_cookies
from auth.http import Event, Response, forbidden, form_fields, from_cloudfront, redirect
from auth.http import html as html_response
from auth.models import VerifyRequest
from auth.store import consume_token, record_visit
from auth.tokens import email_id, token_hash

logger = logging.getLogger(__name__)

EXPIRED_PAGE = "/login.html?expired=1"
PROTECTED_PREFIX = "/roles/"

CONFIRM_PAGE = """\
<!doctype html>
<html lang="en-GB">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="robots" content="noindex">
  <meta name="referrer" content="no-referrer">
  <title>Sign in · Henry Ashton</title>
  <link rel="stylesheet" href="/assets/site.css">
</head>
<body>
  <main>
    <h1>Finish signing in</h1>
    <p class="lede">Select the button to open the detailed write-ups in this browser.</p>
    <form method="post" action="/api/auth/verify">
      <input type="hidden" name="token" value="{token}">
      <button type="submit">Sign in</button>
    </form>
    <p class="note">This extra step stops email security scanners from using up your
    one-time link before you do.</p>
  </main>
</body>
</html>
"""


def handler(event: Event, context: Any) -> Response:  # noqa: ANN401
    config = settings()
    if not from_cloudfront(event, config.origin_secret):
        logger.warning("request did not come through CloudFront")
        return forbidden()

    if event["requestContext"]["http"]["method"] == "GET":
        try:
            request = VerifyRequest.model_validate(event.get("queryStringParameters") or {})
        except ValidationError:
            return redirect(EXPIRED_PAGE)
        return html_response(CONFIRM_PAGE.format(token=html.escape(request.token)))

    try:
        request = VerifyRequest.model_validate(form_fields(event))
    except (ValidationError, ValueError):
        return redirect(EXPIRED_PAGE)

    now = int(time.time())
    email = consume_token(token_hash(request.token), now)
    if email is None:
        logger.info("expired or already-used link")
        return redirect(EXPIRED_PAGE)

    record_visit(email, now)
    cookies = signed_cookies(
        resource=f"{config.site_url}{PROTECTED_PREFIX}*",
        expires_at=now + required(config.cookie_ttl_seconds, "COOKIE_TTL_SECONDS"),
        path=PROTECTED_PREFIX,
    )
    logger.info("signed in", extra={"email_id": email_id(email)})
    return redirect(PROTECTED_PREFIX, cookies)
