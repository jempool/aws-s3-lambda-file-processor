"""Pure business logic: validate a transactions file and summarize it.

Kept free of AWS dependencies so it can be unit tested locally.
"""

import json
import math

REQUIRED_FIELDS = ("id", "customer", "amount")


def process_file(body: bytes) -> dict:
    """Return a PROCESSED summary, or a FAILED result listing every problem found."""
    try:
        transactions = json.loads(body.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError):
        return _failed(["File is not valid JSON"])

    if not isinstance(transactions, list):
        return _failed(["File must contain a JSON array of transactions"])
    if not transactions:
        return _failed(["File contains no transactions"])

    errors = [
        error
        for position, transaction in enumerate(transactions, start=1)
        for error in _validate(position, transaction)
    ]
    if errors:
        return _failed(errors)

    total = sum(t["amount"] for t in transactions)
    return {
        "status": "PROCESSED",
        "total_transactions": len(transactions),
        "total_amount": round(total, 2),
        "average_amount": round(total / len(transactions), 2),
    }


def _validate(position: int, transaction) -> list:
    label = f"Transaction {position}"
    if not isinstance(transaction, dict):
        return [f"{label}: must be a JSON object"]

    errors = [
        f"{label}: missing field '{field}'"
        for field in REQUIRED_FIELDS
        if field not in transaction
    ]
    if "amount" in transaction and not _is_number(transaction["amount"]):
        errors.append(f"{label}: 'amount' must be a number")
    return errors


def _is_number(value) -> bool:
    # bool is a subclass of int in Python; NaN/Infinity are not real amounts.
    return (
        isinstance(value, (int, float))
        and not isinstance(value, bool)
        and math.isfinite(value)
    )


def _failed(errors: list) -> dict:
    return {"status": "FAILED", "errors": errors}
