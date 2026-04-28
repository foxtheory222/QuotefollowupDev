import os
import time

import requests
from azure.identity import DefaultAzureCredential


class DataverseClient:
    def __init__(self, base_url, credential=None, session=None):
        self.base_url = str(base_url).rstrip("/")
        self.api_root = f"{self.base_url}/api/data/v9.2"
        self.credential = credential or DefaultAzureCredential(exclude_interactive_browser_credential=True)
        self.session = session or requests.Session()
        self._token = <REDACTED>
        self._expires_on = 0

    @classmethod
    def from_env(cls):
        base_url = os.getenv("QFU_DATAVERSE_URL", "").strip()
        if not base_url:
            raise RuntimeError("QFU_DATAVERSE_URL must be configured for the hosted freight parser.")
        return cls(base_url=base_url)

    def _get_access_token(self):
        if self._token and (self._expires_on - 120) > time.time():
            return self._token

        scope = os.getenv("QFU_DATAVERSE_SCOPE", "").strip() or f"{self.base_url}/.default"
        token = <REDACTED>
        self._token = <REDACTED>
        self._expires_on = int(token.expires_on)
        return self._token

    def _headers(self, extra_headers=None):
        headers = {
            "Accept": "application/json",
            "Authorization": f"Bearer {self._get_access_token()}",
            "Content-Type": "application/json; charset=utf-8",
            "OData-MaxVersion": "4.0",
            "OData-Version": "4.0",
        }
        if extra_headers:
            headers.update(extra_headers)
        return headers

    def request(self, method, path, *, params=None, json_body=None, extra_headers=None):
        response = self.session.request(
            method=method,
            url=f"{self.api_root}/{path.lstrip('/')}",
            headers=self._headers(extra_headers=extra_headers),
            params=params,
            json=json_body,
            timeout=60,
        )
        if response.status_code >= 400:
            detail = response.text.strip()
            raise RuntimeError(f"Dataverse {method} {path} failed with {response.status_code}: {detail}")
        if response.status_code == 204 or not response.text.strip():
            return None
        return response.json()

    def list_records(self, entity_set, *, select=None, filter_expr=None, top=None, orderby=None):
        params = {}
        if select:
            params["$select"] = ",".join(select) if isinstance(select, (list, tuple)) else str(select)
        if filter_expr:
            params["$filter"] = filter_expr
        if top is not None:
            params["$top"] = int(top)
        if orderby:
            params["$orderby"] = str(orderby)
        response = self.request("GET", entity_set, params=params)
        return list(response.get("value", []))

    def create_record(self, entity_set, fields):
        return self.request("POST", entity_set, json_body=fields)

    def update_record(self, entity_set, record_id, fields):
        self.request("PATCH", f"{entity_set}({record_id})", json_body=fields)

