import os
import uuid
from dataclasses import dataclass

import boto3
from langchain.agents.middleware import after_agent, dynamic_prompt
from langchain_core.messages import AIMessage, HumanMessage
# >> The AgentCore Memory integration for LangGraph: checkpointer and store
from langgraph_checkpoint_aws import AgentCoreMemorySaver, AgentCoreMemoryStore
# <<

# >> Memory ID from `~/environment/.envrc`
MEMORY_ID = os.environ["AGENTCORE_MEMORY_ID"]
# <<
REGION = os.environ.get("AWS_REGION") or boto3.session.Session().region_name

# >> Short-term memory: the checkpointer saves the conversation state per actor and session
checkpointer = AgentCoreMemorySaver(MEMORY_ID, region_name=REGION)
# <<
# >> Long-term memory: the store saves messages as events for extraction and searches the extracted records
store = AgentCoreMemoryStore(memory_id=MEMORY_ID, region_name=REGION)
# <<


@dataclass
class Context:
    actor_id: str
    session_id: str


# >> Discover LTM strategy namespaces at startup — no need to save individual strategy IDs
def discover_namespaces():
    control = boto3.client("bedrock-agentcore-control", region_name=REGION)
    memory = control.get_memory(memoryId=MEMORY_ID)["memory"]
    return [(s["strategyId"], ns) for s in memory.get("strategies", []) for ns in s["namespaces"]]
# <<


NAMESPACES = discover_namespaces()


# >> The session header has the format `actorId` or `actorId:sessionId`. The checkpointer reads `thread_id` and `actor_id` from the config
def memory_config(conversation_id):
    actor_id, _, session_id = conversation_id.partition(":")
    session_id = session_id or "default-session"
    config = {"configurable": {"thread_id": session_id, "actor_id": actor_id}}
    return Context(actor_id, session_id), config
# <<


def with_long_term_memory(system_prompt):
    # >> Before each model call, search the strategy namespaces of the actor and add the facts to the system prompt
    @dynamic_prompt
    def prompt(request):
        actor_id = request.runtime.context.actor_id
        question = next((m.text for m in reversed(request.messages) if isinstance(m, HumanMessage)), "")
        facts = []
        for strategy_id, ns in NAMESPACES:
            path = ns.replace("{memoryStrategyId}", strategy_id).replace("{actorId}", actor_id)
            facts += [item.value["content"] for item in store.search(tuple(path.strip("/").split("/")), query=question, limit=3)]
        if not facts:
            return system_prompt
        return system_prompt + "\nWhat you know about the user:\n" + "\n".join(f"- {fact}" for fact in facts)
    # <<

    return prompt


# >> After each turn, save the question and the answer as events; AgentCore Memory extracts facts and preferences from them
@after_agent
def save_turn(state, runtime):
    ctx = runtime.context
    human = next((m for m in reversed(state["messages"]) if isinstance(m, HumanMessage)), None)
    answer = state["messages"][-1]
    for message in (human, answer):
        if isinstance(message, (HumanMessage, AIMessage)) and message.text:
            store.put((ctx.actor_id, ctx.session_id), str(uuid.uuid4()), {"message": message})
# <<
