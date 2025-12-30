# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Retrieval-Augmented Generation (RAG) chatbot system for querying course materials. It combines semantic search (ChromaDB + SentenceTransformers) with AI-powered response generation (Anthropic Claude) using a tool-calling architecture.

**Tech Stack**: Python 3.13+, FastAPI, ChromaDB, Anthropic Claude Sonnet 4, SentenceTransformers, Vanilla JavaScript frontend

## Important: Package Management

**ALWAYS use `uv` to manage ALL dependencies and run ALL Python files. DO NOT use `pip` or `python` directly.**

This project uses `uv` as its package manager for all operations:
- **Installing dependencies**: `uv sync` (NOT `pip install`)
- **Adding new packages**: `uv add package-name` (NOT `pip install package-name`)
- **Removing packages**: `uv remove package-name` (NOT `pip uninstall package-name`)
- **Running Python files**: `uv run python script.py` (NOT `python script.py`)
- **Running any Python tool**: `uv run <command>` (NOT direct execution)

**Critical**: Never execute Python files directly. Always prefix with `uv run`:
```bash
# ❌ WRONG - Do NOT do this
python backend/app.py
python -m pytest
python script.py

# ✅ CORRECT - Always do this
uv run python backend/app.py
uv run pytest
uv run python script.py
```

Using `pip` or running `python` directly will cause dependency conflicts and break the project environment.

## Development Commands

### Setup
```bash
# Install uv package manager
curl -LsSf https://astral.sh/uv/install.sh | sh

# Install dependencies
uv sync

# Create .env file with your Anthropic API key
echo "ANTHROPIC_API_KEY=your-key-here" > .env
```

### Running the Application
```bash
# Quick start (from root directory)
./run.sh

# Manual start (from backend/ directory)
cd backend
uv run uvicorn app:app --reload --port 8000
```

**Access**:
- Web Interface: http://localhost:8000
- API Documentation: http://localhost:8000/docs

### Managing Dependencies

**All dependency operations must use `uv`**:

```bash
# Add a new dependency (updates pyproject.toml)
uv add package-name

# Add a development dependency
uv add --dev package-name

# Remove a dependency
uv remove package-name

# Update all dependencies
uv sync --upgrade

# Install specific package version
uv add "package-name==1.2.3"

# Run any Python script
uv run python script.py

# Run pytest (if added)
uv run pytest

# Run any installed tool
uv run black .
```

**Never use**: `pip install`, `pip uninstall`, `python script.py`, or direct command execution.

### Running Python Files

**CRITICAL: Always use `uv run` to execute any Python file or command.**

```bash
# Run the server (from backend/ directory)
uv run uvicorn app:app --reload --port 8000

# Run a Python script
uv run python your_script.py

# Run with arguments
uv run python process_data.py --input data.txt --output results.json

# Run Python module
uv run python -m module_name

# Run interactive Python shell
uv run python

# Execute any installed Python tool
uv run black backend/
uv run mypy backend/
uv run flake8
```

**Why this matters**: `uv run` ensures the correct virtual environment and dependency versions are used. Running `python` directly will use the system Python and miss all project dependencies.

### Working with the Database
```bash
# ChromaDB is automatically initialized on first run
# Data persists in: backend/chroma_db/

# To rebuild vector database (clear existing data):
# Delete the chroma_db directory and restart the server
rm -rf backend/chroma_db/
./run.sh
```

### Adding Course Documents
Place `.txt`, `.pdf`, or `.docx` files in `docs/` directory. The system auto-loads them on startup.

**Expected format**:
```
Course Title: [title]
Course Link: [url]
Course Instructor: [name]

Lesson 0: Introduction
Lesson Link: [url]
[lesson content]

Lesson 1: Next Topic
[lesson content]
```

## Architecture

### Two-Stage Tool-Use Pattern

Unlike traditional RAG systems that always search, this uses **Claude's tool-calling** to decide when searches are needed:

1. **Stage 1**: Claude analyzes query → decides if `search_course_content` tool is needed
2. **Stage 2** (if tool used): Execute search → feed results back to Claude → generate answer

This makes the system efficient for general knowledge questions that don't require course content.

### Component Interaction Flow

```
POST /api/query
    ↓
app.py (FastAPI) → creates/retrieves session_id
    ↓
rag_system.py (orchestrator)
    ├→ session_manager.py → get conversation history (MAX_HISTORY=2 exchanges)
    ├→ ai_generator.py → call Claude API with tools
    │   └→ Claude decides: tool_use or text response
    ├→ tool_manager.py → execute search_course_content tool
    │   └→ search_tools.py (CourseSearchTool)
    │       └→ vector_store.py → ChromaDB semantic search
    │           ├→ course_catalog collection (for course name resolution)
    │           └→ course_content collection (for content search)
    └→ session_manager.py → store user query + AI response
```

### Two-Collection ChromaDB Strategy

The system uses **two separate collections**, not one:

1. **`course_catalog`**: Stores course metadata (title, instructor, lessons as JSON)
   - Used for fuzzy course name matching via semantic search
   - Example: "MCP" → resolves to "MCP: Build Rich-Context AI Apps"

2. **`course_content`**: Stores chunked course material with metadata
   - Metadata: `course_title`, `lesson_number`, `chunk_index`
   - Used for actual content retrieval with filtering

This enables smart two-stage search: resolve vague course names → filter content by exact title.

### Document Processing Pipeline

**Location**: `backend/document_processor.py`

1. **Parse metadata**: Extract course title, link, instructor from first 3 lines
2. **Identify lessons**: Regex `^Lesson\s+(\d+):\s*(.+)$` finds lesson boundaries
3. **Chunk text**: Sentence-based chunking (800 chars, 100 char overlap)
4. **Add context**: First chunk of each lesson gets prefix: `"Lesson {N} content: {text}"`
5. **Store**: Create `CourseChunk` objects with course/lesson metadata

**Fallback**: If no lessons found, treats entire document as single chunk.

### Session Management

**Location**: `backend/session_manager.py`

- **In-memory only** (lost on server restart)
- Session IDs: `session_1`, `session_2`, etc. (predictable, not production-ready)
- Stores last `MAX_HISTORY=2` exchanges (4 messages total)
- History formatted as plain text: `"User: {query}\nAssistant: {response}"`

### Source Tracking Pattern

**Important**: Sources are tracked separately from search results via stateful tool execution.

1. `CourseSearchTool.execute()` stores sources in `self.last_sources`
2. After AI generates response, `ToolManager.get_last_sources()` retrieves them
3. Sources are reset via `reset_sources()` to prevent stale data
4. Frontend displays sources in collapsible section

## Configuration Settings

**Location**: `backend/config.py`

| Setting | Default | Impact |
|---------|---------|--------|
| `CHUNK_SIZE` | 800 | Text chunk size; affects context quality vs. search precision |
| `CHUNK_OVERLAP` | 100 | Prevents context loss at chunk boundaries |
| `MAX_RESULTS` | 5 | Top-K results from vector search |
| `MAX_HISTORY` | 2 | Conversation exchanges to remember (affects cost) |
| `EMBEDDING_MODEL` | `all-MiniLM-L6-v2` | SentenceTransformer model (384-dim embeddings) |
| `ANTHROPIC_MODEL` | `claude-sonnet-4-20250514` | Claude model for response generation |

**Critical**: Changing `EMBEDDING_MODEL` requires rebuilding ChromaDB (delete `chroma_db/` directory).

## System Prompt Strategy

**Location**: `backend/ai_generator.py:8-30`

The `AIGenerator.SYSTEM_PROMPT` contains critical directives:
- "One search per query maximum" - prevents excessive tool calls
- "No meta-commentary" - directs Claude to give direct answers without explaining its process
- Distinguishes general knowledge (no search) vs. course-specific questions (search required)

When modifying behavior, update this prompt rather than adding few-shot examples.

## Key Implementation Details

### Course De-duplication
`rag_system.py:add_course_folder()` checks existing courses by title before adding. However, it still **processes documents** even if they exist (inefficient). The check happens after document parsing.

### Conversation Context
History is passed to Claude as a string in the system prompt:
```python
system_content = f"{SYSTEM_PROMPT}\n\nPrevious conversation:\n{history}"
```

This limits flexibility for future multi-turn features.

### Frontend State
- Uses **relative API URLs** (`/api`) for proxy compatibility
- Manual cache busting via version strings: `style.css?v=9`
- Markdown rendering via `marked.js`
- Session ID stored in JavaScript `currentSessionId` variable

### Course Name Resolution
When users provide course names, `vector_store.py:_resolve_course_name()` uses semantic search on `course_catalog` to find best match. This enables fuzzy matching but can be fooled by similar titles.

## Common Gotchas

1. **Always use uv to run Python files**: Never execute Python files directly with `python script.py` or `python -m module`. Always use `uv run python script.py` or `uv run <command>`. Running Python directly will use the system Python interpreter and miss all project dependencies, causing import errors and version conflicts. Similarly, never use `pip` - use `uv add`/`uv remove` instead.

2. **Server restart loses sessions**: In-memory session storage means conversation history is lost on restart.

3. **Embedding model changes break database**: If you change `EMBEDDING_MODEL` in config, you must delete `chroma_db/` and rebuild.

4. **No duplicate prevention during processing**: The system re-parses documents even if they already exist in the database (wasteful for large folders).

5. **CORS is fully permissive**: `allow_origins=["*"]` is set for development. Tighten for production.

6. **Sources can be stale**: If you forget to call `reset_sources()` after a query, next response may show previous sources.

7. **Lesson links must follow title**: The parser expects `Lesson Link:` on the line immediately after `Lesson N: Title`, or it's treated as content.

## Testing

**Current State**: No test infrastructure exists.

To add tests:
```bash
# Install pytest using uv
uv add --dev pytest pytest-asyncio

# Run tests (once created)
uv run pytest

# Run specific test file
uv run pytest tests/test_vector_store.py
```

Create tests for:
- Document chunking algorithm edge cases
- Course title fuzzy matching accuracy
- Session history management
- Tool execution error handling
- Vector search filtering (by course, by lesson)

## File References

**Core Backend**:
- `backend/app.py` - FastAPI routes and startup logic
- `backend/rag_system.py` - Main orchestrator
- `backend/ai_generator.py` - Claude API integration with tool handling
- `backend/vector_store.py` - ChromaDB interface with two-collection strategy
- `backend/search_tools.py` - Tool definitions and execution
- `backend/document_processor.py` - Text chunking and metadata extraction
- `backend/session_manager.py` - Conversation history management
- `backend/config.py` - Configuration settings

**Frontend**:
- `frontend/script.js` - Chat UI logic and API calls
- `frontend/index.html` - Chat interface layout
- `frontend/style.css` - Dark theme styling

**Data**:
- `docs/` - Course material files (auto-loaded on startup)
- `backend/chroma_db/` - Persistent vector database (auto-created)

## Deployment Notes

- FastAPI serves both API (`/api/*`) and static frontend (`/`)
- ChromaDB data persists in `backend/chroma_db/`
- Environment variable `ANTHROPIC_API_KEY` must be set
- Server runs on port 8000 by default
- `--reload` flag enables auto-restart on code changes (development only)
- **Always start server with**: `uv run uvicorn app:app --port 8000` (NOT `python -m uvicorn` or `uvicorn` directly)
