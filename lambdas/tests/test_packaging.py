"""The handlers must import with only what the Lambda package contains.

Dev-only packages (type stubs, test tools) are installed here but not in the deployment
zip, so an accidental runtime import of one passes every other test and then fails in
Lambda with Runtime.ImportModuleError.
"""

import importlib
import sys

import pytest

DEV_ONLY = ("mypy_boto3_dynamodb", "mypy_boto3_sesv2", "mypy_boto3_ssm", "moto", "pytest")
HANDLERS = ("auth.request_code", "auth.verify_code")


@pytest.mark.parametrize("handler", HANDLERS)
def test_handler_imports_without_dev_packages(
    handler: str, monkeypatch: pytest.MonkeyPatch
) -> None:
    for name in list(sys.modules):
        if name == "auth" or name.startswith("auth."):
            monkeypatch.delitem(sys.modules, name)
    for name in DEV_ONLY:
        if name != "pytest":
            # A None entry makes `import name` raise ImportError.
            monkeypatch.setitem(sys.modules, name, None)

    importlib.import_module(handler)
