import pytest

from auth.http import form_fields, from_cloudfront, viewer_ip
from tests.conftest import SECRET, event


def test_origin_secret_must_match() -> None:
    assert from_cloudfront(event("POST", "/x"), SECRET)
    assert not from_cloudfront(event("POST", "/x", secret="wrong"), SECRET)
    assert not from_cloudfront({"headers": {}}, SECRET)


@pytest.mark.parametrize(
    ("viewer", "expected"),
    [
        ("198.51.100.7:51234", "198.51.100.7"),
        ("2001:db8:1:2:3:4:5:6:443", "2001:db8:1:2::/64"),
        ("[2001:db8::1]:443", "2001:db8::/64"),
        ("garbage", "unknown"),
    ],
)
def test_viewer_ip(viewer: str, expected: str) -> None:
    assert viewer_ip(event("POST", "/x", viewer=viewer)) == expected


def test_form_and_json_bodies() -> None:
    assert form_fields(event("POST", "/x", body="email=a%40b.com")) == {"email": "a@b.com"}
    assert form_fields(
        event("POST", "/x", body='{"email": "a@b.com"}', content_type="application/json")
    ) == {"email": "a@b.com"}


@pytest.mark.parametrize(
    ("body", "content_type"),
    [
        ("x" * 5000, "application/x-www-form-urlencoded"),
        ("[1, 2]", "application/json"),
        ("{not json", "application/json"),
    ],
)
def test_malformed_bodies_raise(body: str, content_type: str) -> None:
    with pytest.raises(ValueError):
        form_fields(event("POST", "/x", body=body, content_type=content_type))
