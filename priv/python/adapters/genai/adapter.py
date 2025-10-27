"""
GenAI Adapter for SnakeBridge - Google Gemini with Streaming

Specialized adapter for google-genai library providing:
- Simple text generation
- Streaming token-by-token generation
- Error handling for API keys
- Model shortcuts

Install: pip install google-genai==1.46.0
Requires: GEMINI_API_KEY environment variable
"""

import os
import logging
from typing import Optional, Iterator

try:
    from snakepit_bridge.base_adapter_threaded import ThreadSafeAdapter, tool
    HAS_SNAKEPIT = True
except ImportError:
    ThreadSafeAdapter = object
    HAS_SNAKEPIT = False

    def tool(description="", **kwargs):
        def decorator(func):
            return func
        return decorator

logger = logging.getLogger(__name__)


class GenAIAdapter(ThreadSafeAdapter):
    """
    Specialized adapter for Google GenAI library.

    Provides optimized integration with proper:
    - Client management
    - Streaming support
    - Error handling
    """

    def __init__(self):
        if HAS_SNAKEPIT:
            super().__init__()
        self.client = None
        self.initialized = False
        logger.info("GenAIAdapter initialized")

    def set_session_context(self, session_context):
        """Set session context."""
        self.session_context = session_context

    async def initialize(self):
        """Initialize GenAI client."""
        try:
            import google.genai as genai

            api_key = os.getenv("GEMINI_API_KEY")
            if not api_key:
                raise ValueError("GEMINI_API_KEY environment variable not set")

            self.client = genai.Client(api_key=api_key)
            self.initialized = True
            logger.info("GenAI client initialized")

        except Exception as e:
            logger.error(f"Failed to initialize GenAI: {e}")
            raise

    async def cleanup(self):
        """Cleanup resources."""
        self.client = None
        self.initialized = False
        logger.info("GenAI adapter cleaned up")

    def execute_tool(self, tool_name: str, arguments: dict, context) -> dict:
        """Dispatch tool calls."""
        if tool_name == "generate_text":
            return self.generate_text(
                model=arguments.get("model", "gemini-2.0-flash-exp"),
                prompt=arguments.get("prompt", "")
            )
        elif tool_name == "generate_text_stream":
            return self.generate_text_stream(
                model=arguments.get("model", "gemini-2.0-flash-exp"),
                prompt=arguments.get("prompt", "")
            )
        else:
            return {"success": False, "error": f"Unknown tool: {tool_name}"}

    @tool(description="Generate text with Gemini (non-streaming)")
    def generate_text(self, model: str, prompt: str) -> dict:
        """
        Generate text from Gemini model.

        Args:
            model: Model name (e.g., "gemini-2.0-flash-exp", "gemini-flash-lite-latest")
            prompt: Text prompt

        Returns:
            {"success": true, "text": "generated text..."}
        """
        if not self.initialized:
            return {"success": False, "error": "Client not initialized"}

        try:
            response = self.client.models.generate_content(
                model=model,
                contents=prompt
            )

            return {
                "success": True,
                "text": response.text,
                "model": model
            }

        except Exception as e:
            logger.error(f"GenAI generation error: {e}")
            return {
                "success": False,
                "error": str(e)
            }

    @tool(description="Generate text with streaming", supports_streaming=True)
    def generate_text_stream(self, model: str, prompt: str) -> Iterator[dict]:
        """
        Stream text generation from Gemini.

        Args:
            model: Model name
            prompt: Text prompt

        Yields:
            {"chunk": "token..."} for each chunk
        """
        if not self.initialized:
            yield {"success": False, "error": "Client not initialized"}
            return

        try:
            response = self.client.models.generate_content_stream(
                model=model,
                contents=prompt
            )

            for chunk in response:
                if hasattr(chunk, 'text') and chunk.text:
                    yield {"chunk": chunk.text}

            yield {"success": True, "done": True}

        except Exception as e:
            logger.error(f"GenAI streaming error: {e}")
            yield {"success": False, "error": str(e)}
