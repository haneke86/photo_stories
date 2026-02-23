import { validateJwtAndGetUserId } from "./shared/auth";
import { checkAndIncrement, nextPeriodStart } from "./shared/usage-db";
import { streamAnthropic } from "./shared/anthropic-client";

/**
 * Streaming chat proxy — runs via Lambda Function URL with response streaming.
 * Receives POST with messages + systemPrompt, pipes SSE chunks from Anthropic.
 *
 * This handler uses the awslambda.streamifyResponse wrapper for streaming.
 */
declare const awslambda: {
  streamifyResponse: (handler: (event: LambdaFunctionUrlEvent, responseStream: NodeJS.WritableStream) => Promise<void>) => unknown;
  HttpResponseStream: {
    from: (stream: NodeJS.WritableStream, metadata: { statusCode: number; headers: Record<string, string> }) => NodeJS.WritableStream;
  };
};

interface LambdaFunctionUrlEvent {
  headers: Record<string, string>;
  body?: string;
  isBase64Encoded?: boolean;
  requestContext: {
    http: { method: string; path: string };
  };
}

export const handler = awslambda.streamifyResponse(
  async (event: LambdaFunctionUrlEvent, responseStream: NodeJS.WritableStream) => {
    // Handle CORS preflight
    if (event.requestContext.http.method === "OPTIONS") {
      const corsStream = awslambda.HttpResponseStream.from(responseStream, {
        statusCode: 204,
        headers: {
          "Access-Control-Allow-Origin": "*",
          "Access-Control-Allow-Methods": "POST, OPTIONS",
          "Access-Control-Allow-Headers": "Content-Type, Authorization",
        },
      });
      corsStream.end();
      return;
    }

    const sseHeaders = {
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache",
      "Connection": "keep-alive",
      "Access-Control-Allow-Origin": "*",
    };

    // Validate JWT manually (Function URLs bypass API Gateway authorizer)
    const authHeader = event.headers["authorization"] ?? event.headers["Authorization"];
    const userId = await validateJwtAndGetUserId(authHeader);

    if (!userId) {
      const errStream = awslambda.HttpResponseStream.from(responseStream, {
        statusCode: 401,
        headers: { "Content-Type": "application/json" },
      });
      errStream.write(JSON.stringify({ error: "Unauthorized" }));
      errStream.end();
      return;
    }

    // Check usage
    const usage = await checkAndIncrement(userId, "chats");
    if (!usage.allowed) {
      const errStream = awslambda.HttpResponseStream.from(responseStream, {
        statusCode: 429,
        headers: { "Content-Type": "application/json" },
      });
      errStream.write(JSON.stringify({
        error: "Monthly chat limit reached",
        remaining: 0,
        resetsAt: nextPeriodStart(),
      }));
      errStream.end();
      return;
    }

    // Parse request body
    const rawBody = event.isBase64Encoded
      ? Buffer.from(event.body ?? "", "base64").toString()
      : (event.body ?? "{}");
    const body = JSON.parse(rawBody);

    try {
      // Open streaming connection to Anthropic
      const anthropicStream = await streamAnthropic({
        model: body.model ?? "claude-sonnet-4-5-20250929",
        max_tokens: body.max_tokens ?? 1024,
        system: body.systemPrompt ?? body.system ?? "",
        messages: body.messages,
      });

      // Set up SSE response stream
      const httpStream = awslambda.HttpResponseStream.from(responseStream, {
        statusCode: 200,
        headers: sseHeaders,
      });

      // Pipe Anthropic SSE chunks to client
      const reader = anthropicStream.getReader();
      const decoder = new TextDecoder();

      while (true) {
        const { done, value } = await reader.read();
        if (done) break;

        const chunk = decoder.decode(value, { stream: true });
        httpStream.write(chunk);
      }

      httpStream.end();
    } catch (err) {
      console.error("Chat streaming error:", err);
      const errStream = awslambda.HttpResponseStream.from(responseStream, {
        statusCode: 500,
        headers: { "Content-Type": "application/json" },
      });
      errStream.write(JSON.stringify({ error: "Internal server error" }));
      errStream.end();
    }
  },
);
