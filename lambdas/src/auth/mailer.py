"""Sends the sign-in link with SES."""

from functools import cache

import boto3
from mypy_boto3_sesv2 import SESV2Client

from auth.config import required, settings

SUBJECT = "Your sign-in link for henryashton.dev"

BODY = """\
Hello,

Use this link to read Henry Ashton's detailed role write-ups:

{link}

It works once and expires in {minutes} minutes. If you didn't ask for it, you can ignore
this email.

This mailbox doesn't receive replies.
"""


@cache
def _ses() -> SESV2Client:
    return boto3.client("sesv2")


def send_link(to: str, link: str) -> None:
    config = settings()
    _ses().send_email(
        FromEmailAddress=required(config.sender, "SENDER"),
        Destination={"ToAddresses": [to]},
        Content={
            "Simple": {
                "Subject": {"Data": SUBJECT, "Charset": "UTF-8"},
                "Body": {
                    "Text": {
                        "Data": BODY.format(link=link, minutes=config.token_ttl_seconds // 60),
                        "Charset": "UTF-8",
                    }
                },
            }
        },
    )
