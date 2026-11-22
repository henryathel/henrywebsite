"""Helpers for API Gateway HTTP API (payload format 2.0) events behind CloudFront."""

import base64
import hmac
import ipaddress
import json
from typing import Any
from urllib.parse import parse_qs, quote

Event = dict[str, Any]
Response = dict[str, Any]

MAX_BODY_BYTES = 4096


def _headers(event: Event) -> dict[str, str]:
    # HTTP APIs lower-case header names.
    headers: dict[str, str] = event.get("headers") or {}
    return headers


def from_cloudfront(event: Event, origin_secret: str) -> bool:
    """True if the request came through our distribution, which adds a secret header.

    Without this check, anyone could call the execute-api endpoint directly and forge the
    viewer-address header used for per-IP rate limits.
    """
    supplied = _headers(event).get("x-origin-verify", "")
    return hmac.compare_digest(supplied.encode(), origin_secret.encode())


def viewer_ip(event: Event) -> str:
    """The visitor's address as CloudFront saw it. IPv6 is grouped by /64, which is
    typically one household or device, so rotating through a prefix doesn't evade limits."""
    raw = _headers(event).get("cloudfront-viewer-address", "")
    host = raw.rsplit(":", 1)[0].strip("[]")
    try:
        address = ipaddress.ip_address(host)
    except ValueError:
        return "unknown"
    if address.version == 6:
        return str(ipaddress.ip_network(f"{address}/64", strict=False))
    return str(address)


def form_fields(event: Event) -> dict[str, str]:
    """Fields from a form-encoded or JSON body. Raises ValueError on anything malformed."""
    body: str = event.get("body") or ""
    if event.get("isBase64Encoded"):
        body = base64.b64decode(body, validate=True).decode()
    if len(body) > MAX_BODY_BYTES:
        raise ValueError("body too large")

    if _headers(event).get("content-type", "").startswith("application/json"):
        data = json.loads(body)
        if not isinstance(data, dict):
            raise ValueError("expected a JSON object")
        return {str(key): str(value) for key, value in data.items()}

    parsed = parse_qs(body, max_num_fields=10)
    return {key: values[0] for key, values in parsed.items()}


def redirect(location: str, cookies: list[str] | None = None) -> Response:
    response: Response = {
        "statusCode": 303,
        "headers": {"Location": location, "Cache-Control": "no-store"},
    }
    if cookies:
        response["cookies"] = cookies
    return response


def code_page(email: str, *, wrong: bool = False) -> str:
    """Where to enter the code. The address travels in the URL fragment, which browsers
    never send to a server, so it stays out of CloudFront and S3 requests."""
    query = "?wrong=1" if wrong else ""
    return f"/login-code.html{query}#email={quote(email, safe='@')}"


def forbidden() -> Response:
    return {"statusCode": 403, "headers": {"Content-Type": "text/plain"}, "body": "Forbidden"}
