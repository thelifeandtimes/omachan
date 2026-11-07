"""Omabit v1 private stdin entry point. The normal client talks directly to Eyre."""
import json
import signal
import sys

from app_connection.instance import INSTANCE
from app_connection.journal import Journal, reconcile_request, reconciled, sync_directory
from app_connection.offer import HandoffError, acknowledgement, check_identity, decode, plugin_session
from app_connection.store import Store


def accept(raw, store):
    offer = decode(raw, INSTANCE)
    session = plugin_session(offer["session"])
    check_identity(offer["session"])
    with store.locked("direct"), store.locked():
        if store.account() is not None:
            raise HandoffError("account-exists")
        sync_directory(store.root.parent)
        journal = Journal(store.root)
        row = journal.begin(offer, session)
        store.save(offer, session)
        row["phase"] = "accepted"
        journal.save()
    return acknowledgement(offer)


def reconcile(raw, store):
    binding = reconcile_request(raw, INSTANCE)
    with store.locked():
        journal = Journal(store.root)
        row = journal.find(binding)
        if row is None:
            return reconciled(binding, "absent")
        if row["phase"] == "reconciled":
            return reconciled(binding, row["outcome"])
        request_id = row["request_id"]
        account = store.account()
        store.clear_secret(request_id, row["fingerprint"])
        outcome = "absent"
        if account is not None:
            outcome = "superseded"
            if account.get("application_request_id") == request_id:
                if (account["baseUrl"], "~" + account["ship"], account["fingerprint"]) != (
                        row["origin"], row["ship"], row["fingerprint"]):
                    raise HandoffError("account-changed")
                store.path.unlink()
                sync_directory(store.path.parent)
                outcome = "removed"
        journal.finish(row, outcome)
        return reconciled(binding, outcome)


def main():
    def timeout(*_):
        raise HandoffError("timeout")
    signal.signal(signal.SIGALRM, timeout)
    signal.alarm(25)
    try:
        raw = sys.stdin.buffer.read(16385)
        if not sys.argv[1:]:
            result = accept(raw, Store())
        elif sys.argv[1:] == ["--reconcile"]:
            result = reconcile(raw, Store())
        else:
            raise HandoffError("invalid")
    except HandoffError as error:
        result = {"version": 1, "status": "rejected", "code": str(error)}
    except Exception:
        result = {"version": 1, "status": "rejected", "code": "storage"}
    finally:
        signal.alarm(0)
    print(json.dumps(result, separators=(",", ":")), flush=True)
    return int(result["status"] == "rejected")


if __name__ == "__main__":
    sys.exit(main())
