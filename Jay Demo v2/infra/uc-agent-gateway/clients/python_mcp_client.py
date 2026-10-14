"""Custom-harness client (e.g. a Python agent in AKS/ACA) calling Unity Catalog through the APIM MCP gateway.

Same path the Foundry agent uses: caller -> APIM (auth + rate limit + logs) -> managed identity -> Databricks MCP -> UC.
Standard library only, so it runs in any python:3.x image without pip.

Auth modes (--auth):
  key        APIM subscription key from env APIM_SUBSCRIPTION_KEY (Key Vault / secret mount in AKS)
  azcli      Entra token from `az account get-access-token` (local testing)
  mi         Entra token from the managed identity endpoint (Azure Container Apps, App Service)
  workload   Entra token via AKS workload identity (AZURE_FEDERATED_TOKEN_FILE exchange)
Entra modes need --audience (the gateway app ID URI) and APIM validates the token.

    set APIM_MCP_URL=https://<apim>.azure-api.net/uc/mcp
    set APIM_SUBSCRIPTION_KEY=<from Key Vault>
    python python_mcp_client.py --facility SLC
    python python_mcp_client.py --list
    python python_mcp_client.py --tool query_space_x --args "{\"query\": \"patients per facility\"}"
"""

import argparse
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

PROTOCOL_VERSION = "2025-06-18"


class GatewayHttpError(Exception):
    def __init__(self, code: int, reason: str, detail: str, retry_after: str | None) -> None:
        super().__init__(f"HTTP {code} {reason}: {detail}")
        self.code = code
        self.retry_after = retry_after


def entra_token(mode: str, audience: str) -> str:
    resource = audience.rstrip("/")
    if mode == "azcli":
        cmd = ["az", "account", "get-access-token", "--resource", resource, "--query", "accessToken", "-o", "tsv"]
        r = subprocess.run(cmd, capture_output=True, text=True, shell=os.name == "nt")
        if r.returncode != 0:
            raise SystemExit(f"# az could not get a token for {resource}: {r.stderr.strip()[:400]}")
        return r.stdout.strip()
    if mode == "mi":
        q = {"api-version": "2019-08-01", "resource": resource}
        if os.environ.get("AZURE_CLIENT_ID"):
            q["client_id"] = os.environ["AZURE_CLIENT_ID"]
        req = urllib.request.Request(
            f"{os.environ['IDENTITY_ENDPOINT']}?{urllib.parse.urlencode(q)}",
            headers={"X-IDENTITY-HEADER": os.environ["IDENTITY_HEADER"]},
        )
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                return json.loads(r.read())["access_token"]
        except urllib.error.HTTPError as e:
            raise SystemExit(f"# managed identity token for {resource} failed: HTTP {e.code} {e.read().decode()[:600]}")
    if mode == "workload":
        with open(os.environ["AZURE_FEDERATED_TOKEN_FILE"]) as f:
            assertion = f.read().strip()
        authority = os.environ.get("AZURE_AUTHORITY_HOST", "https://login.microsoftonline.com/").rstrip("/")
        data = urllib.parse.urlencode({
            "client_id": os.environ["AZURE_CLIENT_ID"],
            "scope": f"{resource}/.default",
            "grant_type": "client_credentials",
            "client_assertion_type": "urn:ietf:params:oauth:client-assertion-type:jwt-bearer",
            "client_assertion": assertion,
        }).encode()
        url = f"{authority}/{os.environ['AZURE_TENANT_ID']}/oauth2/v2.0/token"
        with urllib.request.urlopen(urllib.request.Request(url, data), timeout=30) as r:
            return json.loads(r.read())["access_token"]
    raise ValueError(mode)


class McpClient:
    def __init__(self, url: str, auth_headers: dict) -> None:
        self.url = url
        self.auth_headers = auth_headers
        self.session_id = None
        self._id = 0

    def _post(self, payload: dict) -> dict | None:
        headers = {
            "Content-Type": "application/json",
            "Accept": "application/json, text/event-stream",
            "MCP-Protocol-Version": PROTOCOL_VERSION,
            **self.auth_headers,
        }
        if self.session_id:
            headers["Mcp-Session-Id"] = self.session_id
        req = urllib.request.Request(self.url, json.dumps(payload).encode(), headers, method="POST")
        try:
            with urllib.request.urlopen(req, timeout=180) as resp:
                self.session_id = resp.headers.get("Mcp-Session-Id", self.session_id)
                corr = resp.headers.get("x-imh-correlation-id")
                ctype = resp.headers.get("Content-Type", "")
                body = resp.read().decode()
        except urllib.error.HTTPError as e:
            detail = e.read().decode()[:500]
            raise GatewayHttpError(e.code, e.reason, detail, e.headers.get("Retry-After"))
        if corr:
            block = resp.headers.get("x-imh-gateway-block")
            print(f"# {payload.get('method')}: HTTP 200, correlation id {corr}" + (f", gateway block: {block}" if block else ""))
        if not body.strip():
            return None
        if ctype.startswith("text/event-stream"):
            data = [ln[5:].strip() for ln in body.splitlines() if ln.startswith("data:")]
            body = data[-1] if data else "{}"
        msg = json.loads(body)
        if "error" in msg:
            raise RuntimeError(msg["error"])
        return msg.get("result")

    def request(self, method: str, params: dict | None = None) -> dict | None:
        self._id += 1
        return self._post({"jsonrpc": "2.0", "id": self._id, "method": method, "params": params or {}})

    def initialize(self) -> None:
        self.request("initialize", {
            "protocolVersion": PROTOCOL_VERSION,
            "capabilities": {},
            "clientInfo": {"name": "uc-agent-gateway-sample", "version": "1.1"},
        })
        self._post({"jsonrpc": "2.0", "method": "notifications/initialized"})


def print_result(result: dict) -> None:
    for part in result.get("content", []):
        print(part.get("text", part))


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--url", default=os.environ.get("APIM_MCP_URL"))
    p.add_argument("--auth", choices=["key", "azcli", "mi", "workload"], default=os.environ.get("APIM_AUTH", "key"))
    p.add_argument("--audience", default=os.environ.get("APIM_AUDIENCE"), help="Gateway app ID URI for Entra modes")
    p.add_argument("--facility", default="SLC")
    p.add_argument("--list", action="store_true", help="List tools with input schemas and exit")
    p.add_argument("--tool", default=os.environ.get("MCP_TOOL"), help="Tool name; default = first *get_patients tool")
    p.add_argument("--args", default=os.environ.get("MCP_ARGS"), help="Tool arguments as JSON")
    p.add_argument("--query", default=None, help="Natural-language question for a Genie space (query_space_* tool)")
    p.add_argument("--repeat", type=int, default=1, help="Call the tool N times (shows APIM 429 rate limiting)")
    a = p.parse_args()
    if not a.url:
        p.error("set APIM_MCP_URL or --url")

    if a.auth == "key":
        key = os.environ.get("APIM_SUBSCRIPTION_KEY")
        if not key:
            p.error("set APIM_SUBSCRIPTION_KEY")
        auth_headers = {"Ocp-Apim-Subscription-Key": key}
    else:
        if not a.audience:
            p.error("--audience (or APIM_AUDIENCE) is required for Entra auth")
        auth_headers = {"Authorization": f"Bearer {entra_token(a.auth, a.audience)}"}
    print(f"# url={a.url} auth={a.auth}")

    client = McpClient(a.url, auth_headers)
    client.initialize()
    tools = (client.request("tools/list") or {}).get("tools", [])
    if a.list:
        for t in tools:
            print(json.dumps({"name": t["name"], "description": t.get("description", "")[:200],
                              "inputSchema": t.get("inputSchema")}, indent=1))
        return
    names = [t["name"] for t in tools]
    print("# tools:", names)
    if a.query:
        name = a.tool or next((t for t in names if t.startswith("query_space_")), None)
        args = {"query": a.query}
    else:
        name = a.tool or next((t for t in names if t.endswith("get_patients")), None)
        args = json.loads(a.args) if a.args else {"fac": a.facility}
    if not name:
        raise SystemExit("tool not found; use --list and --tool")
    for i in range(a.repeat):
        if a.repeat > 1:
            print(f"# call {i + 1}/{a.repeat}")
        try:
            result = client.request("tools/call", {"name": name, "arguments": args}) or {}
        except GatewayHttpError as e:
            print(f"# gateway refused the call: {e}" + (f" (retry after {e.retry_after}s)" if e.retry_after else ""))
            if a.repeat == 1:
                raise SystemExit(1)
            time.sleep(0.5)
            continue
        if name.startswith("query_space_"):
            result = poll_genie(client, name.replace("query_space_", "poll_response_", 1), result)
        print_result(result)
        sys.stdout.flush()
        if a.repeat > 1:
            time.sleep(0.5)


def poll_genie(client: McpClient, poll_tool: str, result: dict, timeout_s: int = 120) -> dict:
    """Genie answers asynchronously: keep calling poll_response_* until the message completes."""
    deadline = time.time() + timeout_s
    while time.time() < deadline:
        try:
            msg = json.loads(result["content"][0]["text"])
        except (KeyError, IndexError, ValueError, TypeError):
            return result
        status = msg.get("status", "")
        if status in ("COMPLETED", "FAILED", "CANCELLED", "QUERY_RESULT_EXPIRED") or not msg.get("messageId"):
            return result
        print(f"# genie status {status}; polling")
        time.sleep(3)
        result = client.request("tools/call", {"name": poll_tool, "arguments": {
            "conversation_id": msg["conversationId"], "message_id": msg["messageId"]}}) or {}
    return result


if __name__ == "__main__":
    try:
        main()
    except GatewayHttpError as err:
        print(f"# gateway refused the request: {err}")
        sys.exit(1)
