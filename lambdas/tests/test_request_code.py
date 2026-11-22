import re
from typing import Any

import boto3
import pytest

from auth import request_code
from auth.codes import code_hash
from tests.conftest import event, sent_messages

pytestmark = pytest.mark.usefixtures("aws")

CODE_PAGE = "/login-code.html#email=visitor@example.com"


def request(email: str, **kwargs: Any) -> dict[str, Any]:
    body = f"email={email}"
    return request_code.handler(event("POST", "/api/auth/request", body=body, **kwargs), None)


def test_sends_code_and_stores_only_its_hash() -> None:
    response = request("Visitor%40Example.com")

    assert response["statusCode"] == 303
    assert response["headers"]["Location"] == CODE_PAGE

    [message] = sent_messages()
    assert message["destinations"]["ToAddresses"] == ["visitor@example.com"]
    match = re.search(r"^(\d{6}) is your sign-in code", message["subject"])
    assert match
    code = match.group(1)
    assert f"\n{code}\n" in message["body"]
    assert "10 minutes" in message["body"]

    [item] = boto3.resource("dynamodb").Table("codes").scan()["Items"]
    assert item["email"] == "visitor@example.com"
    assert item["code_hash"] == code_hash("visitor@example.com", code)
    assert code not in str(item)
    assert item["attempts"] == 0


def test_new_code_replaces_the_old_one() -> None:
    request("visitor%40example.com")
    request("visitor%40example.com")
    assert boto3.resource("dynamodb").Table("codes").scan()["Count"] == 1


def test_invalid_email_is_rejected_without_sending() -> None:
    response = request("not-an-email")
    assert response["headers"]["Location"] == "/login.html?invalid=1"
    assert sent_messages() == []


def test_per_email_limit_gives_the_same_response() -> None:
    responses = [request("visitor%40example.com", viewer=f"198.51.100.{i}:1") for i in range(5)]
    assert {r["headers"]["Location"] for r in responses} == {CODE_PAGE}
    assert len(sent_messages()) == request_code.EMAIL_LIMIT


def test_per_ip_limit() -> None:
    for i in range(request_code.IP_LIMIT + 2):
        request(f"person{i}%40example.com")
    assert len(sent_messages()) == request_code.IP_LIMIT


def test_requests_that_bypass_cloudfront_are_refused() -> None:
    response = request("visitor%40example.com", secret="guessed")
    assert response["statusCode"] == 403
    assert sent_messages() == []
