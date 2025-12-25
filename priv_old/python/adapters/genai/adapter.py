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

# Import base adapter
from snakebridge_adapter.adapter import SnakeBridgeAdapter

try:
    from snakepit_bridge.base_adapter_threaded import tool
    HAS_SNAKEPIT = True
except ImportError:
    HAS_SNAKEPIT = False

    def tool(description="", **kwargs):
        def decorator(func):
            return func
        return decorator

logger = logging.getLogger(__name__)


class GenAIAdapter(SnakeBridgeAdapter):
    """
    Specialized adapter for Google GenAI library.

    Inherits from SnakeBridgeAdapter for describe_library and call_python,
    and adds specialized tools for text generation.

    This fixes the previous issue of instantiating a fresh generic adapter
    per call - now we properly inherit and reuse the parent's capabilities.
    """

    def __init__(self, ttl_seconds: int = 3600, max_instances: int = 1000):
        """Initialize GenAI adapter with parent capabilities."""
        super().__init__(ttl_seconds=ttl_seconds, max_instances=max_instances)
        self.genai_client = None
        self._genai_initialized = False
        logger.info("GenAIAdapter initialized (inheriting from SnakeBridgeAdapter)")

    async def initialize(self):
        """Initialize both parent and GenAI client."""
        await super().initialize()
        try:
            self._init_genai_client()
        except Exception as e:
            logger.warning(f"GenAI client initialization deferred: {e}")

    async def cleanup(self):
        """Cleanup resources."""
        self.genai_client = None
        self._genai_initialized = False
        await super().cleanup()
        logger.info("GenAI adapter cleaned up")

    def execute_tool(self, tool_name: str, arguments: dict, context):
        """
        Dispatch tool calls.

        GenAI-specific tools are handled here, all others fall through
        to the parent SnakeBridgeAdapter.
        """
        logger.debug(f"GenAIAdapter.execute_tool: {tool_name}")

        # Handle GenAI-specific tools
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

        # Delegate to parent for describe_library, call_python, etc.
        return super().execute_tool(tool_name, arguments, context)

    def _init_genai_client(self):
        """Initialize the GenAI client lazily."""
        if self._genai_initialized:
            return

        try:
            import google.genai as genai

            api_key = os.getenv("GEMINI_API_KEY")
            if not api_key:
                raise ValueError("GEMINI_API_KEY environment variable not set")

            self.genai_client = genai.Client(api_key=api_key)
            self._genai_initialized = True
            logger.info("GenAI client initialized")

        except ImportError as e:
            logger.error(f"google-genai not installed: {e}")
            raise
        except Exception as e:
            logger.error(f"Failed to initialize GenAI: {e}")
            raise

    def _ensure_genai_initialized(self):
        """Ensure GenAI client is ready."""
        if not self._genai_initialized:
            self._init_genai_client()

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
        try:
            self._ensure_genai_initialized()
        except Exception as e:
            return {"success": False, "error": f"Failed to initialize: {str(e)}"}

        try:
            response = self.genai_client.models.generate_content(
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
    def generate_text_stream(self, model: str, prompt: str):
        """
        Stream text generation from Gemini.

        Args:
            model: Model name
            prompt: Text prompt

        Yields:
            {"chunk": "token..."} for each chunk
        """
        import asyncio

        logger.debug("generate_text_stream called")

        try:
            self._ensure_genai_initialized()
        except Exception as e:
            yield {"success": False, "error": f"Failed to initialize: {str(e)}"}
            return

        try:
            # Get or create event loop
            try:
                loop = asyncio.get_event_loop()
            except RuntimeError:
                loop = asyncio.new_event_loop()
                asyncio.set_event_loop(loop)

            # Create the async generator
            async_response = self.genai_client.models.generate_content_stream(
                model=model,
                contents=prompt
            )

            # Consume it synchronously
            while True:
                try:
                    chunk = loop.run_until_complete(async_response.__anext__())
                    if hasattr(chunk, 'text') and chunk.text:
                        yield {"chunk": chunk.text}
                except StopAsyncIteration:
                    break

            yield {"success": True, "done": True}

        except Exception as e:
            logger.error(f"GenAI streaming error: {e}")
            yield {"success": False, "error": str(e)}
