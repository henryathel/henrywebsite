"""Sends the sign-in code with SES."""

from functools import cache
from typing import TYPE_CHECKING

import boto3

from auth.config import required, settings

# Type stubs are dev-only; they aren't in the Lambda package.
if TYPE_CHECKING:
    from mypy_boto3_sesv2 import SESV2Client

# The code is in the subject so it shows in notifications, for reading on a phone and
# typing on another device.
SUBJECT = "{code} is your sign-in code for henryashton.dev"

BODY = """\
Hello,

Your code for reading Henry Ashton's detailed role write-ups is:

{code}

Enter it on the sign-in page. It works once and expires in {minutes} minutes. If you
didn't ask for it, you can ignore this email.

This mailbox doesn't receive replies.
"""


@cache
def _ses() -> "SESV2Client":
    return boto3.client("sesv2")


def send_code(to: str, code: str) -> None:
    config = settings()
    _ses().send_email(
        FromEmailAddress=required(config.sender, "SENDER"),
        Destination={"ToAddresses": [to]},
        Content={
            "Simple": {
                "Subject": {"Data": SUBJECT.format(code=code), "Charset": "UTF-8"},
                "Body": {
                    "Text": {
                        "Data": BODY.format(code=code, minutes=config.code_ttl_seconds // 60),
                        "Charset": "UTF-8",
                    }
                },
            }
        },
    )
