import base64
import json
import time
from typing import Any

import boto3
import pytest
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import padding, rsa

from auth import verify_code
from auth.codes import code_hash
from auth.store import save_code
from tests.conftest import SITE, event

pytestmark = pytest.mark.usefixtures("aws")

EMAIL = "visitor@example.com"
WRONG_PAGE = "/login-code.html?wrong=1#email=visitor@example.com"


def issue(code: str = "482913", email: str = EMAIL, ttl: int = 600) -> str:
    save_code(email, code_hash(email, code), int(time.time()) + ttl)
    return code


def verify(code: str, email: str = "visitor%40example.com", **kwargs: Any) -> dict[str, Any]:
    body = f"email={email}&code={code}"
    return verify_code.handler(event("POST", "/api/auth/verify", body=body, **kwargs), None)


def location(response: dict[str, Any]) -> str:
    return str(response["headers"]["Location"])


def cookie_values(response: dict[str, Any]) -> dict[str, str]:
    pairs = (cookie.split(";", 1)[0].split("=", 1) for cookie in response["cookies"])
    return {name: value for name, value in pairs}


def from_cloudfront_b64(value: str) -> bytes:
    return base64.b64decode(value.translate(str.maketrans("-_~", "+=/")))


def visitors() -> list[dict[str, Any]]:
    return boto3.resource("dynamodb").Table("visitors").scan()["Items"]


def test_correct_code_signs_in_once(signing_key: rsa.RSAPrivateKey) -> None:
    code = issue()
    response = verify(code)

    assert response["statusCode"] == 303
    assert location(response) == "/roles/"
    for cookie in response["cookies"]:
        assert "Path=/roles/" in cookie
        assert "Max-Age=432000" in cookie
        assert "Secure" in cookie and "HttpOnly" in cookie and "SameSite=Lax" in cookie

    values = cookie_values(response)
    assert values["CloudFront-Key-Pair-Id"] == "K2TESTKEYPAIR"
    policy = from_cloudfront_b64(values["CloudFront-Policy"])
    statement = json.loads(policy)["Statement"][0]
    assert statement["Resource"] == f"{SITE}/roles/*"
    expires = statement["Condition"]["DateLessThan"]["AWS:EpochTime"]
    assert abs(expires - (time.time() + 432000)) < 5
    signing_key.public_key().verify(
        from_cloudfront_b64(values["CloudFront-Signature"]),
        policy,
        padding.PKCS1v15(),
        hashes.SHA1(),
    )

    [visitor] = visitors()
    assert visitor["email"] == EMAIL
    assert visitor["sign_ins"] == 1

    assert location(verify(code)) == WRONG_PAGE


@pytest.mark.parametrize("typed", ["482 913", "482-913", " 482913 "])
def test_code_may_be_typed_with_separators(typed: str) -> None:
    issue()
    assert location(verify(typed.replace(" ", "+"))) == "/roles/"


def test_email_is_case_insensitive() -> None:
    issue()
    assert location(verify("482913", email="Visitor%40EXAMPLE.com")) == "/roles/"


def test_wrong_code_keeps_the_visitor_on_the_code_page() -> None:
    issue()
    assert location(verify("000000")) == WRONG_PAGE
    assert visitors() == []


# Concurrency isn't tested here: moto doesn't apply conditional updates atomically the
# way DynamoDB does, so a threaded test would exercise moto rather than this code.
def test_locked_after_max_attempts_even_with_the_right_code() -> None:
    code = issue()
    for _ in range(verify_code.MAX_ATTEMPTS):
        verify("000000")
    assert location(verify(code)) == WRONG_PAGE
    assert visitors() == []


def test_expired_code_is_refused() -> None:
    code = issue(ttl=-1)
    assert location(verify(code)) == WRONG_PAGE
    assert visitors() == []


def test_code_only_works_for_its_own_address() -> None:
    issue(email="someone-else@example.com")
    assert location(verify("482913")) == WRONG_PAGE


def test_malformed_code_stays_on_code_page_and_costs_no_attempt() -> None:
    issue()
    assert location(verify("12345")) == WRONG_PAGE
    [item] = boto3.resource("dynamodb").Table("codes").scan()["Items"]
    assert item["attempts"] == 0


def test_missing_email_starts_again() -> None:
    assert location(verify("482913", email="")) == "/login.html?expired=1"


def test_requests_that_bypass_cloudfront_are_refused() -> None:
    code = issue()
    response = verify(code, secret="x" * 40)
    assert response["statusCode"] == 403
    assert visitors() == []
