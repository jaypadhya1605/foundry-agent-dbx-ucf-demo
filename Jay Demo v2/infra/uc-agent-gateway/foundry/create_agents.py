"""Create (or add a version to) the Foundry prompt agent that calls Unity Catalog through APIM.

Prereqs: azure/ deployed with a Foundry connection (foundryConnectionName output), `az login` as a user
with Azure AI User (or higher) on the project. No keys are handled here: the APIM key lives in the
Foundry connection.

    pip install -r requirements.txt
    set FOUNDRY_PROJECT_ENDPOINT=https://<account>.services.ai.azure.com/api/projects/<project>
    python create_agents.py --mcp-url https://<apim>.azure-api.net/uc/mcp --connection uc-fn-via-apim-umi-iac
"""

import argparse
import os

from azure.ai.projects import AIProjectClient
from azure.ai.projects.models import MCPTool, PromptAgentDefinition
from azure.identity import DefaultAzureCredential

INSTRUCTIONS_UC = """You answer questions about patients using only the get_patients tool.
- Always call the tool; never invent rows.
- Pass the facility code (e.g. SLC) as fac when the user names one. When the user asks for all patients or every
  facility, call the tool with no arguments: leave fac out completely and never send an empty string.
- Show results as a table. Wrap SSN and name values in backticks so masked values (***-**-1234, REDACTED)
  render exactly as returned.
- If a value is masked or rows are missing, say Unity Catalog policy limited what this identity can see.
  Do not guess hidden values.
- If the tool says the gateway blocked the result (too large or rate limited), tell the user and suggest a
  narrower question, such as one facility."""

INSTRUCTIONS_GENIE = """You answer questions about patients using only the Genie tools.
- Call query_space_* with the user's question. Genie answers asynchronously: if the status is not COMPLETED,
  call poll_response_* with the conversation_id and message_id until it is COMPLETED or FAILED.
- Never invent rows. Show results as a table. Wrap SSN and name values in backticks so masked values
  (***-**-1234, REDACTED) render exactly as returned.
- If values are masked or rows are missing, say Unity Catalog policy limited what this identity can see.
- Show the SQL Genie generated, if it returned one."""

PRESETS = {
    "uc": ("imh-uc-apim-umi-agent-iac", "uc_functions_via_apim", INSTRUCTIONS_UC),
    "genie": ("imh-genie-apim-umi-agent", "genie_via_apim", INSTRUCTIONS_GENIE),
}


def ask(project: AIProjectClient, agent_name: str, question: str) -> str:
    """Run one turn against the agent through the project's OpenAI-compatible Responses API."""
    oai = project.get_openai_client()
    last = None
    for key in ("agent_reference", "agent"):
        try:
            resp = oai.responses.create(input=question, extra_body={key: {"name": agent_name, "type": "agent_reference"}})
            return resp.output_text
        except Exception as e:  # SDK/service versions differ on the field name
            last = e
    raise last


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--endpoint", default=os.environ.get("FOUNDRY_PROJECT_ENDPOINT"))
    p.add_argument("--kind", choices=sorted(PRESETS), default="uc", help="uc = UC functions tool, genie = Genie space tool")
    p.add_argument("--agent-name", default=None)
    p.add_argument("--model", default="gpt-4.1")
    p.add_argument("--mcp-url", required=True, help="APIM MCP URL, e.g. https://<apim>.azure-api.net/uc/mcp")
    p.add_argument("--connection", required=True, help="Foundry project connection name holding the APIM key")
    p.add_argument("--server-label", default=None)
    p.add_argument("--allowed-tools", default=None,
                   help="Comma-separated MCP tool names the agent may call, e.g. imh_demo__clinical__get_patients. "
                        "Recommended: the schema also exposes get_patients_limited, which bypasses the APIM row cap.")
    p.add_argument("--ask", default=None, help="Optional question to run once the agent version exists")
    p.add_argument("--ask-only", action="store_true", help="Skip creating a version; just run --ask")
    args = p.parse_args()
    if not args.endpoint:
        p.error("set --endpoint or FOUNDRY_PROJECT_ENDPOINT")
    default_name, default_label, instructions = PRESETS[args.kind]
    agent_name = args.agent_name or default_name

    project = AIProjectClient(endpoint=args.endpoint, credential=DefaultAzureCredential())
    if not args.ask_only:
        connection = project.connections.get(args.connection)
        tool_args = dict(
            server_label=args.server_label or default_label,
            server_url=args.mcp_url,
            require_approval="never",
            # The Foundry portal only shows tools whose connection is referenced by name, not full ID.
            project_connection_id=connection.name,
        )
        if args.allowed_tools:
            tool_args["allowed_tools"] = [t.strip() for t in args.allowed_tools.split(",") if t.strip()]
        tool = MCPTool(**tool_args)
        agent = project.agents.create_version(
            agent_name=agent_name,
            definition=PromptAgentDefinition(model=args.model, instructions=instructions, tools=[tool]),
        )
        print(f"agent={agent.name} version={agent.version}")
    if args.ask:
        print(f"Q: {args.ask}")
        print(ask(project, agent_name, args.ask))


if __name__ == "__main__":
    main()
