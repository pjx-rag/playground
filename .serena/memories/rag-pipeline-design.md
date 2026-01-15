# RAG Pipeline Design

## Two Modes

### 1. RAG Mode (Simple, Fast)
- **Flow**: Question → Search → Answer
- **Steps**: 
  1. Generate embedding from question
  2. Execute hybrid search
  3. Generate answer with citations
- **Use case**: Fast, straightforward Q&A
- **Latency**: ~2-3 seconds
- **Cost**: 1 embedding call + 1 LLM call

### 2. Agentic RAG Mode (Advanced, Intelligent)
- **Flow**: Question → Gate → Decompose → Search → Rerank → Reason → Answer
- **Steps**:
  1. **Gate**: Decide if retrieval needed (saves cost for general questions)
  2. **Decompose**: Break complex questions into sub-queries (optional)
  3. **Search**: Execute hybrid search for each sub-query
  4. **Rerank**: LLM scores chunk relevance
  5. **Reason**: Check if context sufficient, loop back if needed (multi-hop)
  6. **Answer**: Generate response with citations
- **Use case**: Complex questions, multi-part queries, follow-up reasoning
- **Latency**: ~5-10 seconds (depends on iterations)
- **Cost**: 3-5 LLM calls + embeddings

## Configuration

App setting: `rag_mode` = "rag" | "agentic_rag"

## Architecture

```elixir
# Context flows through pipeline
ctx = Agent.new(question, organization_id)

# RAG mode
ctx
|> Agent.search()
|> Agent.answer()

# Agentic RAG mode
ctx
|> Agent.gate()        # Skip retrieval if not needed
|> Agent.decompose()   # Split complex questions
|> Agent.search()      # Hybrid search
|> Agent.rerank()      # Score relevance
|> Agent.reason()      # Multi-hop if insufficient
|> Agent.answer()      # Generate with citations
```

## Multi-Tenancy

All queries scoped by `organization_id` from context.

## Event Logging

Each step logs to event_logs with:
- LLM calls (via api_request_log FK)
- Search queries
- Decomposition results
- Reranking scores
- Multi-hop iterations
