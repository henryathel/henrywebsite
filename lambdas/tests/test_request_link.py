from typing import Any
from urllib.parse import parse_qs, urlparse

import boto3
import pytest

from auth import request_link
from auth.tokens import token_hash
from tests.conftest import SITE, event, sent_messages

pytestmark = pytest.mark.usefixtures("aws")


def request(email: str, **kwargs: Any) -> dict[str, Any]:
    return request_link.handler(
        event("POST", "/api/auth/request", body=f"email={email}", **kwargs), None
    )


def test_sends_link_and_stores_only_the_hash() -> None:
    response = request("Visitor%40Example.com")

    assert response["statusCode"] == 303
    assert response["headers"]["Location"] == "/login-sent.html"

    [message] = sent_messages()
    assert message["destinations"]["ToAddresses"] == ["visitor@example.com"]
    link = next(line for line in message["body"].splitlines() if line.startswith(SITE))
    assert urlparse(link).path == "/api/auth/verify"
    token = parse_qs(urlparse(link).query)["token"][0]

    items = boto3.resource("dynamodb").Table("tokens").scan()["Items"]
    assert [item["token_hash"] for item in items] == [token_hash(token)]
    assert token not in str(items)
    assert items[0]["email"] == "visitor@example.com"


def test_invalid_email_is_rejected_without_sending() -> None:
    response = request("not-an-email")
    assert response["headers"]["Location"] == "/login.html?invalid=1"
    assert sent_messages() == []


def test_per_email_limit_gives_the_same_response() -> None:
    responses = [request("a%40example.com", viewer=f"198.51.100.{i}:1") for i in range(5)]
    assert {r["headers"]["Location"] for r in responses} == {"/login-sent.html"}
    assert len(sent_messages()) == request_link.EMAIL_LIMIT


def test_per_ip_limit() -> None:
    for i in range(request_link.IP_LIMIT + 2):
        request(f"person{i}%40example.com")
    assert len(sent_messages()) == request_link.IP_LIMIT


def test_requests_that_bypass_cloudfront_are_refused() -> None:
    response = request("a%40example.com", secret="guessed")
    assert response["statusCode"] == 403
    assert sent_messages() == []
